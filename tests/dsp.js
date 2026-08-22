#!/usr/bin/env node
// Standalone checks for Dsp.js, the Color Organ's signal core. No QML, no
// audio device: synthetic signals in, assertions on the channels out.
//
//   node tests/dsp.js
//
// Dsp.js is loaded verbatim (minus the QML `.pragma` line) so these run
// against exactly the code the shell runs.

'use strict'

const fs = require('fs')
const path = require('path')

const src = fs.readFileSync(path.join(__dirname, '..', 'Dsp.js'), 'utf8')
  .replace(/^\.pragma\s+library\s*$/m, '')
const Dsp = {}
new Function('exports', src + '\n;exports.createAnalyzer = createAnalyzer' +
  ';exports.bandCentres = bandCentres')(Dsp)

// ---- harness ---------------------------------------------------------------

let failures = 0
let checks = 0

function check(name, ok, detail) {
  checks++
  if (ok) return
  failures++
  console.error(`FAIL  ${name}${detail !== undefined ? '  — ' + detail : ''}`)
}

function group(name) {
  console.log(`\n${name}`)
}

const FPS = 60

// Feed `seconds` of a generator through the analyser, advancing the frame clock
// in lockstep with the audio clock so envelope behaviour is what it would be
// live. `onFrame` sees every frame step.
function run(an, seconds, gen, onFrame) {
  const sr = an.options.sampleRate
  const total = Math.round(seconds * sr)
  const perFrame = Math.max(1, Math.round(sr / FPS))
  const dt = perFrame / sr
  const buf = new Int16Array(perFrame)
  let n = 0
  while (n < total) {
    const count = Math.min(perFrame, total - n)
    for (let i = 0; i < count; i++) {
      const v = gen((n + i) / sr)
      buf[i] = Math.max(-32768, Math.min(32767, Math.round(v * 32767)))
    }
    an.feed(buf, count)
    an.advance(count / sr)
    n += count
    if (onFrame) onFrame(an, n / sr)
  }
  return an
}

const sine = (f, a) => (t) => a * Math.sin(2 * Math.PI * f * t)
const silence = () => 0

function argmax(arr) {
  let best = 0
  for (let i = 1; i < arr.length; i++) if (arr[i] > arr[best]) best = i
  return best
}

// ---- band layout -----------------------------------------------------------

group('band layout')
{
  const an = Dsp.createAnalyzer()
  const c = an.centres
  check('12 bands', c.length === 12, c.length)
  check('spans 55 Hz to 3.5 kHz',
    Math.abs(c[0] - 55) < 0.01 && Math.abs(c[11] - 3500) < 0.01,
    `${c[0].toFixed(1)}..${c[11].toFixed(1)}`)
  check('geometric spacing', c.every((f, i) =>
    i === 0 || Math.abs(f / c[i - 1] - c[1] / c[0]) < 1e-9))
  check('every probe below Nyquist',
    an.plan.every(b => b.frequencies.every(f => f < an.options.sampleRate / 2)))
  check('the bottom band gets the longest window',
    an.plan[0].window === an.options.maxWindow, an.plan[0].window)
  check('the top band gets the shortest window',
    an.plan[11].window === an.options.minWindow, an.plan[11].window)
  check('windows shrink monotonically with frequency',
    an.plan.every((b, i) => i === 0 || b.window <= an.plan[i - 1].window),
    an.plan.map(b => b.window).join(','))
  console.log('      window per band:  ' + an.plan.map(b => b.window).join(','))
  console.log('      probes per band:  ' +
    an.plan.map(b => b.frequencies.length).join(',') + ` (${an.probeCount} total)`)
  console.log('      update rate: ' + (1 / an.hopSeconds).toFixed(2) + ' Hz')
  check('hop rate at least 30 Hz', 1 / an.hopSeconds >= 30)
}

// ---- a tone lands in its own band ------------------------------------------

group('tone → band')
{
  const an = Dsp.createAnalyzer()
  for (let k = 0; k < an.centres.length; k++) {
    const f = an.centres[k]
    an.reset()
    run(an, 2.5, sine(f, 0.4))
    const peak = argmax(an.bands)
    // The bottom bands are a quarter-tone apart — closer than the 15.6 Hz
    // analysis resolution — so neighbours there legitimately share a tone.
    const slack = f < 130 ? 1 : 0
    check(`${f.toFixed(0)} Hz peaks in band ${k}`,
      Math.abs(peak - k) <= slack,
      `peaked at ${peak} (${an.centres[peak].toFixed(0)} Hz)`)
  }
}

// ---- derived channels ------------------------------------------------------

group('derived channels')
{
  const cases = [
    { f: 80, want: 'bass' },
    { f: 530, want: 'mid' },
    { f: 2400, want: 'high' }
  ]
  for (const c of cases) {
    const an = Dsp.createAnalyzer()
    run(an, 2.5, sine(c.f, 0.4))
    const got = ['bass', 'mid', 'high']
      .reduce((a, b) => (an[b] > an[a] ? b : a))
    check(`${c.f} Hz drives ${c.want}`, got === c.want,
      `bass=${an.bass.toFixed(2)} mid=${an.mid.toFixed(2)} high=${an.high.toFixed(2)}`)
    check(`${c.f} Hz reaches a usable level`, an[c.want] > 0.5, an[c.want].toFixed(3))
  }
}

// ---- auto-gain -------------------------------------------------------------

group('auto-gain')
{
  const loud = run(Dsp.createAnalyzer(), 4, sine(530, 0.5))
  const quiet = run(Dsp.createAnalyzer(), 4, sine(530, 0.02))
  check('a -28 dB master reaches the same range as a hot one',
    Math.abs(loud.mid - quiet.mid) < 0.05,
    `loud=${loud.mid.toFixed(3)} quiet=${quiet.mid.toFixed(3)}`)

  const dither = run(Dsp.createAnalyzer(), 3, () => (Math.random() - 0.5) * 2 / 32768)
  check('dither-level noise stays dark', dither.energy < 0.05, dither.energy.toFixed(4))
  check('...and the gate is shut', dither.gate < 0.05, dither.gate.toFixed(4))
}

// ---- silence ---------------------------------------------------------------

group('silence')
{
  const an = run(Dsp.createAnalyzer(), 3, sine(250, 0.4))
  check('loud first', an.energy > 0.5, an.energy.toFixed(3))
  run(an, 2, silence)
  for (const ch of ['bass', 'mid', 'high', 'energy', 'beatPulse'])
    check(`${ch} decays to zero`, an[ch] < 0.01, an[ch].toFixed(4))
  check('every band decays to zero',
    Array.from(an.bands).every(v => v < 0.01),
    Math.max(...an.bands).toFixed(4))
}

// ---- capture loss ----------------------------------------------------------

group('capture loss')
{
  // A dead pipeline must fade the scene out, not freeze it mid-swell.
  const an = run(Dsp.createAnalyzer(), 3, sine(250, 0.4))
  check('loud first', an.energy > 0.5, an.energy.toFixed(3))
  const held = an.energy
  for (let f = 0; f < FPS; f++) an.advance(1 / FPS)
  check('holding the last hop would freeze it', Math.abs(an.energy - held) < 0.05,
    `${held.toFixed(3)} → ${an.energy.toFixed(3)}`)
  an.silence()
  for (let f = 0; f < 2 * FPS; f++) an.advance(1 / FPS)
  for (const ch of ['bass', 'mid', 'high', 'energy'])
    check(`${ch} fades after silence()`, an[ch] < 0.01, an[ch].toFixed(4))
}

// ---- beat detection --------------------------------------------------------

// A kick: 55 Hz body with a fast decay, over a steady mid-range pad so the
// detector has to find the transient rather than the only signal present.
function kickTrack(bpm, seconds) {
  const period = 60 / bpm
  return (t) => {
    const phase = t % period
    const body = Math.exp(-phase * 22) * Math.sin(2 * Math.PI * 55 * phase)
    const pad = 0.12 * Math.sin(2 * Math.PI * 440 * t)
    return 0.55 * body + pad
  }
}

group('beat detection')
{
  for (const bpm of [90, 120, 160]) {
    const an = Dsp.createAnalyzer()
    const seconds = 12
    const beatTimes = []
    let seen = 0
    run(an, seconds, kickTrack(bpm, seconds), (a, t) => {
      if (a.beats > seen) { seen = a.beats; beatTimes.push(t) }
    })
    const expected = Math.floor(seconds * bpm / 60)
    // The first ~1 s builds the flux history, so allow the opening kicks.
    check(`${bpm} BPM: found most kicks`,
      an.beats >= expected - 3 && an.beats <= expected + 1,
      `${an.beats} of ~${expected}`)

    const gaps = beatTimes.slice(1).map((t, i) => t - beatTimes[i])
    const median = gaps.sort((a, b) => a - b)[Math.floor(gaps.length / 2)]
    check(`${bpm} BPM: interval recovered`,
      Math.abs(median - 60 / bpm) < 0.05,
      `median gap ${median.toFixed(3)} s vs ${(60 / bpm).toFixed(3)}`)
  }

  const steady = Dsp.createAnalyzer()
  run(steady, 8, sine(55, 0.5))
  check('a sustained bass note is not a beat train', steady.beats <= 2, steady.beats)

  const quiet = Dsp.createAnalyzer()
  run(quiet, 8, silence)
  check('silence never beats', quiet.beats === 0, quiet.beats)

  const an = Dsp.createAnalyzer()
  let maxPulse = 0
  run(an, 6, kickTrack(120, 6), (a) => { maxPulse = Math.max(maxPulse, a.beatPulse) })
  check('beatPulse reaches full', maxPulse > 0.9, maxPulse.toFixed(3))
  run(an, 2, silence)
  check('beatPulse decays to zero', an.beatPulse < 0.01, an.beatPulse.toFixed(4))
}

// ---- photosensitivity guard ------------------------------------------------

group('photosensitivity guard')
{
  // Worst case on purpose: full scale slammed on and off at 8 Hz.
  const an = Dsp.createAnalyzer()
  const strobe = (t) => (Math.floor(t * 16) % 2 === 0 ? sine(250, 0.9)(t) : 0)
  const limit = an.options.maxSlew / FPS
  const prev = { bass: 0, mid: 0, high: 0, energy: 0 }
  let worst = 0
  run(an, 6, strobe, (a) => {
    for (const ch of ['bass', 'mid', 'high', 'energy']) {
      worst = Math.max(worst, Math.abs(a[ch] - prev[ch]))
      prev[ch] = a[ch]
    }
  })
  check('no channel swings faster than maxSlew', worst <= limit + 1e-9,
    `worst ${worst.toFixed(4)} per frame, limit ${limit.toFixed(4)}`)
  check('...which is at most 3 full transitions a second',
    an.options.maxSlew / 2 <= 3.001, an.options.maxSlew)
}

// ---- framing robustness ----------------------------------------------------

group('framing')
{
  // The capture pipeline's chunking must not change the result.
  function feedInChunks(sizes) {
    const an = Dsp.createAnalyzer()
    const sr = an.options.sampleRate
    const total = 3 * sr
    const all = new Int16Array(total)
    for (let i = 0; i < total; i++)
      all[i] = Math.round(sine(530, 0.4)(i / sr) * 32767)
    let at = 0, si = 0
    while (at < total) {
      const n = Math.min(sizes[si++ % sizes.length], total - at)
      an.feed(all.subarray(at, at + n), n)
      an.advance(n / sr)
      at += n
    }
    return an
  }
  const a = feedInChunks([256])
  const b = feedInChunks([1, 7, 133, 512, 3])
  check('ragged chunking matches aligned chunking',
    Math.abs(a.mid - b.mid) < 0.02,
    `${a.mid.toFixed(4)} vs ${b.mid.toFixed(4)}`)

  const c = Dsp.createAnalyzer()
  c.feed(new Int16Array(200), 200)
  check('no output before a full window', c.hops === 0, c.hops)

  const d = run(Dsp.createAnalyzer(), 2, sine(530, 0.4))
  d.reset()
  check('reset clears every channel',
    d.bass === 0 && d.mid === 0 && d.high === 0 && d.energy === 0 &&
    d.beatPulse === 0 && d.peak === 0 &&
    Array.from(d.bands).every(v => v === 0))

  // A frame the compositor never delivered must not teleport the envelopes.
  const e = run(Dsp.createAnalyzer(), 2, sine(530, 0.4))
  const before = e.mid
  e.advance(10)
  check('a stalled frame is clamped', Math.abs(e.mid - before) <= 0.25 * e.options.maxSlew + 1e-9,
    `${before.toFixed(3)} → ${e.mid.toFixed(3)}`)
}

// ---- cost ------------------------------------------------------------------

group('cost')
{
  const an = Dsp.createAnalyzer()
  const sr = an.options.sampleRate
  const seconds = 30
  const buf = new Int16Array(sr)
  for (let i = 0; i < sr; i++) buf[i] = Math.round(sine(530, 0.4)(i / sr) * 32767)
  const t0 = process.hrtime.bigint()
  for (let s = 0; s < seconds; s++) {
    an.feed(buf, sr)
    for (let f = 0; f < FPS; f++) an.advance(1 / FPS)
  }
  const ms = Number(process.hrtime.bigint() - t0) / 1e6
  const load = ms / (seconds * 1000)
  console.log(`      ${seconds}s of audio in ${ms.toFixed(1)} ms — ${(load * 100).toFixed(2)}% of one core`)
  check('under 2% of a core', load < 0.02, (load * 100).toFixed(2) + '%')
}

// ---- result ----------------------------------------------------------------

console.log()
if (failures) {
  console.error(`${failures} of ${checks} checks failed`)
  process.exit(1)
}
console.log(`${checks} checks passed`)
