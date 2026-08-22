import QtQuick

// Aurora: three tall curtains drifting across each other at incommensurate
// rates, so the pattern never visibly repeats. Bass sets how far up they
// reach, the mid band their brightness; hues sit within a few degrees of the
// theme accent, which is what keeps three overlapping washes reading as one
// colour rather than as a rainbow.
Item {
  id: scene

  property var organ: null
  property real hue: 0
  property real saturation: 0.6
  property real lightness: 0.6
  property real phase: 0

  readonly property real level: organ ? organ.bass : 0
  readonly property real glow: organ ? organ.mid : 0
  readonly property real lift: organ ? organ.energy : 0

  Repeater {
    model: 3

    OrganGlow {
      required property int index

      // Speeds share no small common multiple, and each curtain starts a third
      // of a cycle apart, so they cross rather than travel as a block.
      readonly property real speed: 1.0 + index * 0.37
      readonly property real travel: Math.sin(2 * Math.PI * (scene.phase * speed + index / 3))
      readonly property real depth: 0.75 + 0.25 * Math.cos(2 * Math.PI * (scene.phase * speed * 0.6 + index / 3))

      // Qt.hsla clamps rather than wraps, so the offset is folded back into
      // 0..1 here — an accent near red would otherwise pin a curtain to it.
      readonly property real curtainHue: {
        var h = scene.hue + (index - 1) * 0.028
        return h - Math.floor(h)
      }

      tint: Qt.hsla(curtainHue, scene.saturation,
                    Math.min(0.8, scene.lightness + index * 0.04), 1)
      opacity: (0.11 + 0.40 * scene.glow) * depth
      // Narrow enough to read as three separate curtains where they part, and
      // wide enough to merge into one wash where they cross.
      width: scene.width * 0.34
      height: scene.height * (1.05 + 0.50 * scene.level)
      x: scene.width * 0.5 - width / 2 + travel * scene.width * 0.42
      y: scene.height - height * 0.52
      coreAlpha: 0.78
      midAlpha: 0.24
    }
  }

  // A single wide floor under the curtains, so their feet meet the bottom edge
  // instead of hovering.
  OrganGlow {
    tint: Qt.hsla(scene.hue, scene.saturation, scene.lightness, 1)
    opacity: 0.08 + 0.26 * scene.lift
    width: scene.width * 2.2
    height: scene.height * 0.40
    x: (scene.width - width) / 2
    y: scene.height - height / 2
    coreAlpha: 0.52
    midAlpha: 0.15
  }
}
