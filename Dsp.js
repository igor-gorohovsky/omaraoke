.pragma library

// Color Organ signal core: a multi-resolution Goertzel filter bank over the
// captured sink monitor, plus the dynamics that turn raw band energy into
// channels a visual can consume directly. No QML dependency anywhere in this
// file — tests/dsp.js loads it verbatim under node, so the algorithm is
// checkable without a shell, a sound card, or a compositor.
//
// Two clocks, deliberately separate:
//   feed()      hop rate   (~31 Hz) — spectrum and beat detection
//   advance(dt) frame rate (~60 Hz) — gain, envelopes, derived channels
// Envelopes therefore run at frame rate and are smooth by construction; the
// hop rate only has to be high enough that no beat lands between two looks.

var DEFAULTS = {
  sampleRate: 8000,     // capture rate; Nyquist sits just above the top band

  // The hop is the update quantum: 32 ms, also od's line width, so one line of
  // capture output is exactly one hop. Analysis windows are chosen per band
  // (see planBands) and overlap the hop rather than tiling it.
  hopSize: 256,
  minWindow: 64,        // 8 ms — time resolution for hi-hats
  maxWindow: 512,       // 64 ms — frequency resolution for the bottom bands

  bandCount: 12,
  fMin: 55,             // A1: the lowest note most mixes actually carry
  fMax: 3500,           // above this a monitor mix has little a colour maps to

  // Bands are integrated, so pink noise would already read flat. Real music
  // rolls off well below pink above ~1 kHz, and without a lift the top bands
  // barely move. (f/fMin)^0.35 is ~+2 dB/octave — enough to keep the highs
  // alive, small enough that a bright mix does not wash out the bass.
  tilt: 0.35,

  peakDecay: 4.0,       // s — rolling peak time constant for the auto-gain
  headroom: 3.0,        // a band this many times the mix RMS reads as full
  noiseFloor: 0.002,    // ~-54 dBFS: below this the input is silence, not a
                        // quiet master, and must not be gained up into noise
  gamma: 0.7,           // perceptual lift; 1.0 leaves quiet mixes looking dead

  attack: 0.04,         // s
  release: 0.35,        // s

  // Photosensitivity guard. No channel a scene may map to brightness can
  // change faster than this per second, so a full 0->1 swing takes >= 1/6 s
  // however percussive the track — at most three full-contrast transitions a
  // second, under the 3 Hz flash threshold. The small movements that carry the
  // music are well inside the cap and pass through untouched.
  maxSlew: 6.0,
  pulseRise: 16.0,      // 1/s — beatPulse drives geometry, not area brightness,
                        // so it may snap in ~60 ms, but still not instantly

  beatWindow: 32,       // hops (~1 s) of bass flux history
  beatThreshold: 1.6,   // flux must exceed this multiple of the running mean
  beatFloor: 0.02,      // ...and this absolute rise, so silence never beats
  beatRefractory: 0.25, // s — a 240 BPM ceiling
  pulseDecay: 0.30      // s — beatPulse 1 -> 0 time constant
}

function clamp01(x) {
  return x < 0 ? 0 : (x > 1 ? 1 : x)
}

// Geometric band centres: equal ratio per band, so each covers the same
// musical interval rather than the same number of hertz.
function bandCentres(count, fMin, fMax) {
  var out = []
  var r = count > 1 ? Math.pow(fMax / fMin, 1 / (count - 1)) : 1
  for (var k = 0; k < count; k++)
    out.push(fMin * Math.pow(r, k))
  return out
}

function pow2Clamp(x, lo, hi) {
  var w = Math.pow(2, Math.round(Math.log(x) / Math.LN2))
  return Math.max(lo, Math.min(hi, w))
}

// Per-band analysis plan. One window size for the whole bank would have to
// serve the bottom two bands, a quarter-tone apart, and so would smear every
// hi-hat across 64 ms — and cost ~8x more. Instead each band gets the shortest
// power-of-two window whose bins still fit about three across it: 64 ms at the
// bottom, 8 ms at the top. That is the constant-Q shape a colour organ wants,
// and it is where the whole bank's cost went.
//
// A single Goertzel probe resolves one DFT bin — a Hann main lobe ~2 bins
// wide — so a band is covered by a row of probes spaced 1.5 bins apart and
// summed in power: overlapping enough that the ripple between them stays
// around 1 dB, which is what makes a tone anywhere in the band read at full
// strength instead of falling down a gap.
function planBands(centres, opts) {
  var nyquist = opts.sampleRate / 2
  var ceiling = nyquist * 0.95
  var r = centres.length > 1
    ? Math.pow(centres[centres.length - 1] / centres[0], 1 / (centres.length - 1))
    : 1
  var half = Math.sqrt(r)

  var plan = []
  for (var k = 0; k < centres.length; k++) {
    var lo = centres[k] / half
    var hi = Math.min(centres[k] * half, ceiling)
    var width = Math.max(1e-6, hi - lo)

    var window = pow2Clamp(3 * opts.sampleRate / width, opts.minWindow, opts.maxWindow)
    var lobeHz = 1.5 * opts.sampleRate / window
    var n = Math.max(1, Math.round(width / lobeHz))

    var freqs = []
    for (var p = 0; p < n; p++) {
      // Probes sit at the centres of n equal slices, so the row is centred in
      // the band and the outermost probes do not straddle its edges.
      var f = n === 1 ? centres[k] : lo * Math.pow(hi / lo, (p + 0.5) / n)
      freqs.push(Math.min(f, ceiling))
    }
    plan.push({ window: window, frequencies: freqs })
  }
  return plan
}

function createAnalyzer(options) {
  var o = {}
  for (var key in DEFAULTS)
    o[key] = DEFAULTS[key]
  if (options)
    for (var ok in options)
      if (options[ok] !== undefined)
        o[ok] = options[ok]

  var H = o.hopSize
  var N = o.maxWindow                 // ring length: the longest window
  var centres = bandCentres(o.bandCount, o.fMin, o.fMax)
  var plan = planBands(centres, o)

  // Group bands by window size. Each group unrolls and windows the ring once
  // per placement, then runs every probe in the group over that one buffer —
  // the windowing, not the filtering, is what a naive layout pays twice for.
  //
  // A window shorter than the hop would only see the tail of it, so such a
  // group is evaluated at several placements tiling the hop and the band keeps
  // the loudest: a hi-hat inside the hop reads at full strength wherever it
  // fell, instead of being averaged down by the quiet part around it.
  var groups = []
  var byWindow = {}
  for (var b = 0; b < plan.length; b++) {
    var w = plan[b].window
    if (!byWindow[w]) {
      var hann = new Float64Array(w)
      for (var i = 0; i < w; i++)
        hann[i] = 0.5 - 0.5 * Math.cos(2 * Math.PI * i / w)
      // Offsets are "samples back from the newest sample" for the start of
      // each placement. A window longer than the hop needs only the newest
      // one: consecutive hops already overlap it.
      var starts = []
      if (w >= H) {
        starts.push(w)
      } else {
        for (var j = 0; j < H / w; j++)
          starts.push(H - j * w)
      }
      byWindow[w] = { window: w, hann: hann, scratch: new Float64Array(w),
                      starts: starts, coeff: [], owner: [] }
      groups.push(byWindow[w])
    }
    var g = byWindow[w]
    for (var p = 0; p < plan[b].frequencies.length; p++) {
      g.coeff.push(2 * Math.cos(2 * Math.PI * plan[b].frequencies[p] / o.sampleRate))
      g.owner.push(b)
    }
  }
  var probeCount = 0
  for (var gi = 0; gi < groups.length; gi++) {
    groups[gi].coeff = Float64Array.from(groups[gi].coeff)
    groups[gi].owner = Int32Array.from(groups[gi].owner)
    probeCount += groups[gi].coeff.length
  }

  // Pink-noise compensation, normalised so the lowest band is unweighted.
  var tiltW = []
  for (var t = 0; t < centres.length; t++)
    tiltW.push(Math.pow(centres[t] / o.fMin, o.tilt))

  // Region membership by frequency rather than by index, so changing
  // bandCount never silently re-cuts bass/mid/high.
  var isBass = [], isMid = [], isHigh = []
  for (var c = 0; c < centres.length; c++) {
    isBass.push(centres[c] < 250)
    isMid.push(centres[c] >= 250 && centres[c] < 1200)
    isHigh.push(centres[c] >= 1200)
  }

  var self = {
    options: o,
    centres: centres,
    plan: plan,
    probeCount: probeCount,
    hopSeconds: H / o.sampleRate,

    // ---- Public signal API. Every value is 0..1 and safe to read per frame.
    bands: new Float64Array(o.bandCount),     // enveloped, slew-limited
    bass: 0,
    mid: 0,
    high: 0,
    energy: 0,
    beatPulse: 0,

    // ---- Introspection, for the tests and for diagnosing a quiet capture.
    raw: new Float64Array(o.bandCount),       // pre-envelope, post-gain targets
    magnitude: new Float64Array(o.bandCount), // pre-gain amplitude estimate
    peak: 0,
    level: 0,     // this hop's mix RMS, pre-gain
    gate: 0,      // 0 while the input is silence rather than a quiet mix
    hops: 0,
    beats: 0
  }

  // Ring of the most recent maxWindow samples: successive windows overlap
  // without any re-buffering.
  var ring = new Float64Array(N)
  var ringAt = 0
  var primed = 0
  var sinceHop = 0

  var placement = new Float64Array(o.bandCount)
  var env = new Float64Array(o.bandCount)
  var pulseRising = false
  var bassPrev = 0
  var flux = new Float64Array(o.beatWindow)
  var fluxAt = 0
  var fluxSum = 0
  var fluxSeen = 0
  var clock = 0          // seconds of audio consumed; drives the refractory
  var lastBeat = -1e9
  var pendingBeats = 0

  function analyse() {
    var i, k, g, s

    for (k = 0; k < o.bandCount; k++)
      self.magnitude[k] = 0

    for (g = 0; g < groups.length; g++) {
      var grp = groups[g]
      var w = grp.window
      var hann = grp.hann
      var scratch = grp.scratch
      var coeff = grp.coeff
      var owner = grp.owner
      var probes = coeff.length

      for (s = 0; s < grp.starts.length; s++) {
        var base = (ringAt + N - grp.starts[s]) % N
        for (i = 0; i < w; i++)
          scratch[i] = ring[(base + i) % N] * hann[i]

        for (k = 0; k < o.bandCount; k++)
          placement[k] = 0

        for (var p = 0; p < probes; p++) {
          var cf = coeff[p]
          var s1 = 0, s2 = 0, s0
          for (i = 0; i < w; i++) {
            s0 = scratch[i] + cf * s1 - s2
            s2 = s1
            s1 = s0
          }
          var power = s1 * s1 + s2 * s2 - cf * s1 * s2
          if (power < 0)
            power = 0
          // Amplitude of a tone at this probe, in sample units: Hann's 0.5
          // mean is what makes 4/w recover it exactly. Summed in power across
          // a band's probes, so one tone anywhere in the band yields ~1 and
          // two tones add as energy rather than cancelling.
          var amp = Math.sqrt(power) * 4 / w
          placement[owner[p]] += amp * amp
        }

        for (k = 0; k < o.bandCount; k++)
          if (placement[k] > self.magnitude[k])
            self.magnitude[k] = placement[k]
      }
    }

    var sumSq = 0
    for (k = 0; k < o.bandCount; k++) {
      var m = Math.sqrt(self.magnitude[k]) * tiltW[k]
      self.magnitude[k] = m
      sumSq += m * m
    }
    self.level = Math.sqrt(sumSq / o.bandCount)

    // Auto-gain: a rolling peak of the *mix* level, not of the loudest band.
    // Normalising against the loudest band would pin whichever band dominates
    // (usually the bass) at 1.0 forever, and the kick would stop reading.
    self.peak = Math.max(self.level, self.peak * Math.exp(-self.hopSeconds / o.peakDecay))

    // Silence is not a quiet master: hold the gate shut until the mix clears
    // the noise floor, so dither and room hiss are never gained up to full.
    self.gate = clamp01((self.peak - o.noiseFloor) / (3 * o.noiseFloor))

    var divisor = Math.max(self.peak, o.noiseFloor) * o.headroom
    var bassNow = 0
    for (k = 0; k < o.bandCount; k++) {
      var v = Math.pow(clamp01(self.magnitude[k] / divisor), o.gamma) * self.gate
      self.raw[k] = v
      if (isBass[k] && v > bassNow)
        bassNow = v
    }

    // Beat: positive bass flux against its own ~1 s mean. Flux rather than
    // level, so a sustained bass note does not read as a beat every hop.
    var rise = bassNow - bassPrev
    bassPrev = bassNow
    if (rise < 0)
      rise = 0

    var mean = fluxSeen > 0 ? fluxSum / fluxSeen : 0
    if (rise > o.beatFloor && rise > mean * o.beatThreshold
        && clock - lastBeat >= o.beatRefractory) {
      lastBeat = clock
      pendingBeats++
      self.beats++
    }

    // The just-tested hop joins the history afterwards, so a beat is never
    // compared against itself.
    fluxSum -= flux[fluxAt]
    flux[fluxAt] = rise
    fluxSum += rise
    fluxAt = (fluxAt + 1) % o.beatWindow
    if (fluxSeen < o.beatWindow)
      fluxSeen++

    clock += self.hopSeconds
    self.hops++
  }

  // Accepts any array-like of int16 samples, in any chunking: the ring carries
  // partial hops over, so the capture pipeline's line width is not a contract.
  // Nothing is analysed until a full ring has arrived, so the first result is
  // never half zeros.
  self.feed = function (samples, count) {
    var len = count === undefined ? samples.length : count
    for (var i = 0; i < len; i++) {
      ring[ringAt] = samples[i] / 32768
      ringAt = (ringAt + 1) % N
      if (primed < N)
        primed++
      if (++sinceHop >= H) {
        sinceHop = 0
        if (primed >= N)
          analyse()
      }
    }
  }

  // One frame step. dt in seconds; everything below is dt-correct, so a
  // dropped frame costs resolution and nothing else.
  self.advance = function (dt) {
    if (!(dt > 0))
      return
    if (dt > 0.25)
      dt = 0.25   // a stall must not teleport the envelopes

    var slew = o.maxSlew * dt
    var kA = 1 - Math.exp(-dt / o.attack)
    var kR = 1 - Math.exp(-dt / o.release)

    var bass = 0, mid = 0, high = 0, sumSq = 0
    for (var k = 0; k < o.bandCount; k++) {
      var target = self.raw[k]
      env[k] += (target - env[k]) * (target > env[k] ? kA : kR)

      var d = env[k] - self.bands[k]
      if (d > slew) d = slew
      else if (d < -slew) d = -slew
      var v = self.bands[k] + d
      self.bands[k] = v

      // Regions take the max of their members: a colour organ answers "is
      // there energy here", and a mean would dilute a solo band to 1/n.
      if (isBass[k]) { if (v > bass) bass = v }
      else if (isMid[k]) { if (v > mid) mid = v }
      else if (isHigh[k]) { if (v > high) high = v }
      sumSq += v * v
    }
    self.bass = bass
    self.mid = mid
    self.high = high

    // Overall loudness, not "the loudest band" — which the auto-gain pins at 1.
    var energyTarget = Math.min(1, Math.sqrt(sumSq / o.bandCount) * 2)
    var de = energyTarget - self.energy
    if (de > slew) de = slew
    else if (de < -slew) de = -slew
    self.energy += de

    // beatPulse: a rise-limited attack to 1, then an exponential release. A
    // beat arriving mid-release restarts the attack from wherever it is, so a
    // fast passage stacks into a sustained pulse rather than chattering.
    if (pendingBeats > 0) {
      pulseRising = true
      pendingBeats = 0
    }
    if (pulseRising) {
      self.beatPulse += o.pulseRise * dt
      if (self.beatPulse >= 1) {
        self.beatPulse = 1
        pulseRising = false
      }
    } else {
      self.beatPulse *= Math.exp(-dt / o.pulseDecay)
    }
  }

  // No data is arriving — the pipeline died, or is between restarts. Drop the
  // targets rather than holding the last hop: the envelopes then release to
  // zero over their own time constant, so a scene fades out instead of
  // freezing mid-swell on whatever the last thing it heard was.
  self.silence = function () {
    for (var k = 0; k < o.bandCount; k++)
      self.raw[k] = 0
    self.gate = 0
  }

  // Capture died, or the Session ended: leave nothing lit behind.
  self.reset = function () {
    ringAt = 0
    primed = 0
    sinceHop = 0
    for (var r = 0; r < N; r++)
      ring[r] = 0
    pulseRising = false
    bassPrev = 0
    fluxAt = 0
    fluxSum = 0
    fluxSeen = 0
    pendingBeats = 0
    self.peak = 0
    self.level = 0
    self.gate = 0
    self.bass = self.mid = self.high = self.energy = self.beatPulse = 0
    for (var k = 0; k < o.bandCount; k++) {
      env[k] = 0
      self.raw[k] = 0
      self.bands[k] = 0
      self.magnitude[k] = 0
    }
    for (var f = 0; f < o.beatWindow; f++)
      flux[f] = 0
  }

  return self
}
