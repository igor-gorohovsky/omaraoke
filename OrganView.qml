import QtQuick
import qs.Commons

// The Color Organ's visual layer: the Embers Scene, one per monitor, drawn
// under the karaoke content and over the wallpaper. With the organ switched
// off or the capture unavailable the Loader has no source at all — nothing is
// built, nothing is drawn, and the lyrics above are untouched.
Item {
  id: view

  property var service: null
  property bool active: false

  readonly property var organ: service ? service.organ : null
  readonly property bool live: active && organ !== null && organ.available

  // ---- Colour ---------------------------------------------------------------
  // Every hue in every Scene is the theme accent plus a few degrees. That is
  // what makes the organ read as part of the theme instead of as a rainbow,
  // and it follows a live theme switch with no extra code — Color is the
  // shell's singleton and re-emits on every switch.

  readonly property color accent: Color.accent
  // A fully desaturated accent has no hue to drift; it stays a neutral wash
  // rather than being given a colour the theme does not have. Which leaves
  // lightness to carry the whole Scene on those themes — so it is the one that
  // has to be right.
  readonly property real accentHue: accent.hslHue >= 0 ? accent.hslHue : 0
  readonly property real saturation: Math.min(0.85, accent.hslSaturation)

  // Which way is "away from the background". The Scrim decides its black/white
  // by the theme foreground's luminance (light text ⇒ the ground behind it is
  // dark), and the organ reads the same signal so the two never disagree about
  // which way the wallpaper leans.
  readonly property color foreground: Color.foreground
  readonly property real fgLuminance:
    0.2126 * foreground.r + 0.7152 * foreground.g + 0.0722 * foreground.b
  readonly property bool darkGround: fgLuminance >= 0.5

  // Lightness is clamped away from the ground, not merely floored. On a dark
  // theme that is a floor — a very dark accent must still glow. On a light one
  // the same floor was the bug: seven of the shipped themes have a near-white
  // background, and a mid-lightness mote on it is a smudge. There the window
  // moves below the ground instead, and the accent's hue and saturation are
  // untouched either way.
  readonly property real lightness: darkGround
    ? Math.max(0.55, Math.min(0.75, accent.hslLightness))
    : Math.max(0.24, Math.min(0.42, accent.hslLightness))

  // Slow hue drift, ±12° over 90 s. Stepped at 8 Hz rather than per frame
  // because a hue change re-renders each glow's gradient texture, while
  // everything else in a Scene is a shader uniform.
  property real hueClock: 0
  readonly property real hue: {
    var h = accentHue + 0.033 * Math.sin(2 * Math.PI * hueClock)
    return h - Math.floor(h)
  }

  Timer {
    interval: 125
    repeat: true
    running: view.live
    onTriggered: view.hueClock = (view.hueClock + 125 / 90000) % 1
  }

  // Positional clock for the Scenes' slow drift and sway: one turn per minute,
  // smooth, and shared so three curtains and a sway stay in one motion budget.
  property real phase: 0
  NumberAnimation on phase {
    running: view.live
    loops: Animation.Infinite
    from: 0
    to: 1
    duration: 60000
  }

  // ---- Stage ----------------------------------------------------------------

  Item {
    anchors.fill: parent
    opacity: view.live ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 420 } }

    Loader {
      id: sceneLoader
      anchors.fill: parent
      active: view.live
      source: "OrganEmbers.qml"
    }

    // The Scene interface. Binding tolerates a null target, so an empty
    // Loader costs nothing.
    Binding { target: sceneLoader.item; property: "organ"; value: view.organ }
    Binding { target: sceneLoader.item; property: "hue"; value: view.hue }
    Binding { target: sceneLoader.item; property: "saturation"; value: view.saturation }
    Binding { target: sceneLoader.item; property: "lightness"; value: view.lightness }
    Binding { target: sceneLoader.item; property: "darkGround"; value: view.darkGround }
    Binding { target: sceneLoader.item; property: "phase"; value: view.phase }
  }
}
