import QtQuick

// Embers: sparse motes lifting off the bottom edge. High-frequency energy sets
// the spawn rate and each beat throws a handful extra, so the scene is carried
// by count and motion rather than by brightness — a beat changes how many
// embers there are, never how bright the screen is.
//
// The pool is fixed and recycled — a Scene that allocates per particle would
// hand the shell a garbage collection somewhere in the middle of a song, and
// the pool size is also the hard cap that keeps a bright mix from turning the
// Scene into a wall of dots. Positions and fades are written straight onto the
// items each frame: a Behavior would restart at t=0 on every change.
Item {
  id: scene

  property var organ: null
  property real hue: 0
  property real saturation: 0.6
  property real lightness: 0.6
  property bool darkGround: true
  property real phase: 0

  readonly property real sparkle: organ ? organ.high : 0
  readonly property real level: organ ? organ.bass : 0
  readonly property real beat: organ ? organ.beatPulse : 0

  // A mote sits a notch further from the ground than its own bed does, so it
  // reads as the hot part of the glow it rises out of. Away from, not up:
  // on a light theme "hotter" is darker, and adding the notch there would walk
  // the mote back toward the wallpaper it has to stand out against.
  readonly property real emberLightness: darkGround
    ? Math.min(0.8, lightness + 0.12)
    : Math.max(0.18, lightness - 0.12)
  readonly property color emberColor: Qt.hsla(hue, saturation, emberLightness, 1)

  readonly property int poolSize: 36
  readonly property real baseRate: 1.5   // motes per second at silence
  readonly property real peakRate: 20    // added at full highs
  readonly property int burstCount: 5    // extra motes on a beat
  readonly property real beatSize: 0.45  // extra diameter at the top of a beat

  // Cubed, so the swell goes out fast and comes back faster. beatPulse's own
  // 300 ms release leaves it sitting near the top between hits — a plateau,
  // which on a mote a few pixels across reads as a throb rather than a beat —
  // and cubing turns that into a ~100 ms time constant: full size within a
  // frame or two of the hit, back to normal inside 300 ms, so there is a gap
  // before the next one at any tempo this side of 200 BPM.
  readonly property real pop: 1 + beatSize * beat * beat * beat
  // Mote diameters are tuned against a 1080p frame; taller screens scale up so
  // an ember is never a subpixel fleck on 4K.
  readonly property real sizeScale: Math.max(1, height / 1080)

  property var pool: []
  property real spawnDebt: 0

  Component.onCompleted: {
    var p = []
    for (var i = 0; i < poolSize; i++)
      p.push({ alive: false, x: 0, y: 0, vy: 0, wob: 0, wobRate: 0, size: 0, life: 0, maxLife: 1 })
    pool = p
  }

  function ignite(p) {
    p.alive = true
    p.x = Math.random()
    p.y = -0.02 - Math.random() * 0.04
    p.vy = 0.05 + Math.random() * 0.09        // screen heights per second
    p.wob = Math.random() * 6.283
    p.wobRate = 0.5 + Math.random() * 0.9
    p.size = (3 + Math.random() * 5) * sizeScale
    p.life = 0
    p.maxLife = 3.5 + Math.random() * 3.5
  }

  function igniteSome(n) {
    for (var i = 0; i < pool.length && n > 0; i++) {
      if (!pool[i].alive) {
        ignite(pool[i])
        n--
      }
    }
  }

  function step(dt) {
    if (!(dt > 0) || dt > 0.25)
      dt = 1 / 60

    // Read once: it is the same for every mote this frame.
    var pop = scene.pop

    // Rate, not brightness: highs decide how many motes exist.
    spawnDebt += dt * (baseRate + peakRate * sparkle)
    if (spawnDebt >= 1) {
      var n = Math.floor(spawnDebt)
      spawnDebt -= n
      igniteSome(n)
    }

    for (var i = 0; i < pool.length; i++) {
      var p = pool[i]
      var item = rep.itemAt(i)
      if (!item)
        continue
      if (!p.alive) {
        item.visible = false
        continue
      }
      p.life += dt
      if (p.life >= p.maxLife) {
        p.alive = false
        item.visible = false
        continue
      }
      p.y += p.vy * dt
      p.wob += p.wobRate * dt
      // Fades in over the first half-second and out across the last 40% of its
      // life, so a mote never appears or vanishes as a hard dot but does spend
      // most of that life at full alpha. Ramping out across the whole life
      // instead — while also multiplying by the ramp in — left the average mote
      // on screen at about 40% of its colour, which over an arbitrary wallpaper
      // is dust. This is a constant per mote, not an audio channel: the Scene
      // is still carried by how many embers there are, never by how bright.
      var age = p.life / p.maxLife
      var fade = Math.min(1, p.life / 0.5) * (age <= 0.6 ? 1 : (1 - age) / 0.4)
      // Swollen about the mote's own centre — anchoring it by an edge would
      // make every beat shove the field sideways and upward as well as pulse
      // it. Size, not brightness: the beat changes how big and how many the
      // embers are, never how bright the screen gets.
      var s = p.size * pop
      var cx = p.x * scene.width + Math.sin(p.wob) * scene.width * 0.018 + p.size / 2
      var cy = scene.height * (1 - p.y) - p.size / 2
      item.width = s
      item.height = s
      item.x = cx - s / 2
      item.y = cy - s / 2
      item.opacity = fade
      item.visible = true
    }
  }

  // The bed the motes rise out of, so the bottom edge is a source rather than
  // a line they happen to cross.
  OrganGlow {
    tint: Qt.hsla(scene.hue, scene.saturation, scene.lightness, 1)
    opacity: 0.09 + 0.28 * scene.level
    width: scene.width * 1.8
    height: scene.height * 0.62
    x: (scene.width - width) / 2
    y: scene.height - height / 2
    coreAlpha: 0.58
    midAlpha: 0.17
  }

  Repeater {
    id: rep
    model: scene.poolSize

    Rectangle {
      visible: false
      radius: width / 2
      color: scene.emberColor
    }
  }

  FrameAnimation {
    running: scene.visible
    onTriggered: scene.step(frameTime)
  }

  // Beats arrive as a signal rather than as a threshold on beatPulse: the
  // analyzer already decided, and re-deciding here would drift from it.
  Connections {
    target: scene.organ
    ignoreUnknownSignals: true
    function onBeat() {
      if (scene.visible)
        scene.igniteSome(scene.burstCount)
    }
  }
}
