import QtQuick
import QtQuick.Particles

// Embers: sparse motes lifting off the bottom edge. High-frequency energy sets
// the emission rate and each beat throws a handful extra, so the scene is
// carried by count and motion rather than by brightness — a beat changes how
// many embers there are, never how bright the screen is.
Item {
  id: scene

  property var organ: null
  property real hue: 0
  property real saturation: 0.6
  property real lightness: 0.6
  property real phase: 0

  readonly property real sparkle: organ ? organ.high : 0
  readonly property real level: organ ? organ.bass : 0
  readonly property color emberColor: Qt.hsla(hue, saturation, Math.min(0.8, lightness + 0.12), 1)

  // The ember sprite. ImageParticle draws nothing without a source — Qt 6 no
  // longer ships the built-in glow dot ImageParticle's docs still describe —
  // and committing a PNG for it would put the one binary blob in the repo
  // right where the rule says there should be none (ADR-0009). An inline SVG
  // data URI is the same texture as readable text: white, so ImageParticle's
  // own `color` tints it to the theme. `%23` is the escape for the `#` of the
  // gradient reference, which a data URI would otherwise read as a fragment.
  readonly property string sprite: "data:image/svg+xml;utf8,"
    + '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">'
    + '<radialGradient id="g">'
    + '<stop offset="0" stop-color="white" stop-opacity="1"/>'
    + '<stop offset="0.35" stop-color="white" stop-opacity="0.55"/>'
    + '<stop offset="1" stop-color="white" stop-opacity="0"/>'
    + '</radialGradient>'
    + '<circle cx="32" cy="32" r="32" fill="url(%23g)"/></svg>'

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

  // The system and its painter must both cover the area particles move
  // through: a zero-sized ParticlePainter paints nothing at all.
  ParticleSystem {
    id: system
    anchors.fill: parent
    running: scene.visible

    ImageParticle {
      anchors.fill: parent
      source: scene.sprite
      color: scene.emberColor
      colorVariation: 0.10
      alpha: 0.70
      alphaVariation: 0.20
      entryEffect: ImageParticle.Fade
    }

    Emitter {
      id: emitter
      width: parent.width * 0.9
      height: 4
      x: parent.width * 0.05
      y: parent.height - 4

      // Rate, not brightness. The cap is what keeps a bright mix from turning
      // the Scene into a wall of dots.
      emitRate: 4 + 40 * scene.sparkle
      lifeSpan: 6000
      lifeSpanVariation: 1800
      size: Math.max(6, scene.height * 0.016)
      sizeVariation: Math.max(3, scene.height * 0.008)
      endSize: 0

      // Fast enough that an ember visibly travels — at these speeds one
      // crosses roughly two thirds of the screen within its life.
      velocity: PointDirection {
        y: -scene.height * 0.14
        yVariation: scene.height * 0.07
        xVariation: scene.width * 0.020
      }
      acceleration: PointDirection { y: -scene.height * 0.010 }
    }
  }

  // Beats arrive as a signal rather than as a threshold on beatPulse: the
  // analyzer already decided, and re-deciding here would drift from it.
  Connections {
    target: scene.organ
    ignoreUnknownSignals: true
    function onBeat() {
      if (scene.visible)
        emitter.burst(10 + Math.round(14 * scene.level))
    }
  }
}
