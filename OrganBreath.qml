import QtQuick

// Breath (the default Scene): one huge soft glow rising from the bottom edge.
// Bass drives its brightness and how far up the screen it reaches; a wider,
// dimmer companion behind it keeps the swell from looking like a lamp.
//
// Every value here is a binding on a channel the organ rewrites each frame,
// which is the per-frame update. A Behavior on any of them would restart at
// t=0 every frame and freeze it — the same trap the Line Stack's motion
// documents.
Item {
  id: scene

  property var organ: null
  property real hue: 0
  property real saturation: 0.6
  property real lightness: 0.6
  property real phase: 0          // 0..1 positional clock, one turn per minute

  readonly property real level: organ ? organ.bass : 0
  readonly property real lift: organ ? organ.energy : 0
  readonly property real pulse: organ ? organ.beatPulse : 0

  // Sway keeps a long held note from being a static shape. Position only:
  // brightness comes from the slew-limited channels and nothing else.
  readonly property real sway: Math.sin(2 * Math.PI * phase) * width * 0.07

  OrganGlow {
    tint: Qt.hsla(scene.hue, scene.saturation, scene.lightness, 1)
    opacity: 0.10 + 0.32 * scene.lift
    width: scene.width * 2.4
    height: scene.height * (1.05 + 0.35 * scene.lift)
    x: (scene.width - width) / 2 - scene.sway * 0.6
    y: scene.height - height / 2
    coreAlpha: 0.50
    midAlpha: 0.20
  }

  OrganGlow {
    // The beat only widens the reach; it never touches opacity, so a
    // percussive track cannot flash the screen.
    tint: Qt.hsla(scene.hue, scene.saturation, Math.min(0.78, scene.lightness + 0.1), 1)
    opacity: 0.12 + 0.50 * scene.level
    width: scene.width * (1.45 + 0.22 * scene.level)
    height: scene.height * (0.62 + 0.50 * scene.level + 0.07 * scene.pulse)
    x: (scene.width - width) / 2 + scene.sway
    y: scene.height - height / 2
    coreAlpha: 0.80
    midAlpha: 0.24
  }
}
