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

  OrganGlow {
    tint: Qt.hsla(scene.hue, scene.saturation, scene.lightness, 1)
    opacity: 0.07 + 0.24 * scene.level
    width: scene.width * 1.8
    height: scene.height * 0.62
    x: (scene.width - width) / 2
    y: scene.height - height / 2
    coreAlpha: 0.40
    midAlpha: 0.12
  }

  ParticleSystem {
    id: system
    running: scene.visible
    paused: !scene.visible
  }

  // ImageParticle's built-in glow dot: it ships inside the Particles module,
  // so the scene needs no image of its own in the repo.
  ImageParticle {
    system: system
    color: scene.emberColor
    colorVariation: 0.10
    alpha: 0.0
    entryEffect: ImageParticle.Fade
  }

  Emitter {
    id: emitter
    system: system
    width: scene.width * 0.9
    height: 4
    x: scene.width * 0.05
    y: scene.height - 4

    // Rate, not brightness. The cap is what keeps a bright mix from turning
    // the scene into a wall of dots.
    emitRate: 3 + 34 * scene.sparkle
    lifeSpan: 5600
    lifeSpanVariation: 1800
    size: Math.max(3, scene.height * 0.006)
    sizeVariation: Math.max(2, scene.height * 0.004)
    endSize: 0

    velocity: PointDirection {
      y: -scene.height * 0.055
      yVariation: scene.height * 0.035
      xVariation: scene.width * 0.012
    }
    acceleration: PointDirection { y: -scene.height * 0.008 }
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
