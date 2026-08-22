import QtQuick
import Qt5Compat.GraphicalEffects

// A soft elliptical glow, sized and placed by whoever uses it.
//
// The gradient stops carry only the tint, never the brightness: a stop change
// re-renders the effect's gradient texture, while `opacity`, the radii and the
// position are plain shader uniforms. So hue may move at the drift clock's
// leisurely rate and everything else may move every frame, for free.
Item {
  id: glow

  property color tint: "white"
  property real coreAlpha: 0.55   // stop at the centre
  property real midAlpha: 0.16    // stop at 45% out; sets how soft the falloff is

  RadialGradient {
    anchors.fill: parent
    horizontalRadius: width / 2
    verticalRadius: height / 2
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(glow.tint.r, glow.tint.g, glow.tint.b, glow.coreAlpha) }
      GradientStop { position: 0.45; color: Qt.rgba(glow.tint.r, glow.tint.g, glow.tint.b, glow.midAlpha) }
      GradientStop { position: 1.0; color: Qt.rgba(glow.tint.r, glow.tint.g, glow.tint.b, 0) }
    }
  }
}
