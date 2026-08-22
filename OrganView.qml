import QtQuick
import qs.Commons
import "Dsp.js" as Dsp

// The Color Organ's visual layer: one Scene per monitor, drawn under the
// karaoke content and over the wallpaper. With the organ switched off or the
// capture unavailable the Loader has no source at all — nothing is built,
// nothing is drawn, and the lyrics above are untouched.
Item {
  id: view

  property var service: null
  property bool active: false

  readonly property var organ: service ? service.organ : null
  readonly property bool live: active && organ !== null && organ.available

  // ---- Scene selection ------------------------------------------------------

  // The Scenes that exist. `organStyle` names one; "shuffle" — the default,
  // and the fallback for anything unrecognised — picks per track from a hash
  // of artist|title, so a song always gets the same Scene, on every monitor
  // and across restarts, with nothing stored.
  readonly property var sceneNames: ["breath", "spectrum", "embers", "aurora"]
  readonly property string styleKey: service ? service.organStyle : "shuffle"
  readonly property string sceneName: {
    if (sceneNames.indexOf(styleKey) >= 0)
      return styleKey
    var key = Dsp.sceneHash(service ? service.trackArtist : "",
                            service ? service.trackTitle : "")
    return sceneNames[key % sceneNames.length]
  }

  // A swap happens on a track change, behind the Title Card. Fade rather than
  // cut: a full-screen glow vanishing between two frames reads as a fault.
  property string shownScene: ""
  property bool swapping: false

  Component.onCompleted: shownScene = sceneName
  onSceneNameChanged: {
    if (!live || shownScene === "") {
      shownScene = sceneName
      return
    }
    swapping = true
    swapTimer.restart()
  }

  Timer {
    id: swapTimer
    interval: 420
    onTriggered: {
      view.shownScene = view.sceneName
      view.swapping = false
    }
  }

  // ---- Colour ---------------------------------------------------------------
  // Every hue in every Scene is the theme accent plus a few degrees. That is
  // what makes the organ read as part of the theme instead of as a rainbow,
  // and it follows a live theme switch with no extra code — Color is the
  // shell's singleton and re-emits on every switch.

  readonly property color accent: Color.accent
  // A fully desaturated accent has no hue to drift; it stays a neutral wash
  // rather than being given a colour the theme does not have.
  readonly property real accentHue: accent.hslHue >= 0 ? accent.hslHue : 0
  readonly property real saturation: Math.min(0.85, accent.hslSaturation)
  // Lightness is floored, not taken: a very dark accent must still glow.
  readonly property real lightness: Math.max(0.55, Math.min(0.75, accent.hslLightness))

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
    opacity: view.live && !view.swapping ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 420 } }

    Loader {
      anchors.fill: parent
      active: view.live && view.shownScene !== ""
      sourceComponent: {
        switch (view.shownScene) {
        case "spectrum": return spectrumScene
        case "embers": return embersScene
        case "aurora": return auroraScene
        default: return breathScene
        }
      }
    }
  }

  Component {
    id: breathScene
    OrganBreath {
      organ: view.organ; hue: view.hue; saturation: view.saturation
      lightness: view.lightness; phase: view.phase
    }
  }
  Component {
    id: spectrumScene
    OrganSpectrum {
      organ: view.organ; hue: view.hue; saturation: view.saturation
      lightness: view.lightness; phase: view.phase
    }
  }
  Component {
    id: embersScene
    OrganEmbers {
      organ: view.organ; hue: view.hue; saturation: view.saturation
      lightness: view.lightness; phase: view.phase
    }
  }
  Component {
    id: auroraScene
    OrganAurora {
      organ: view.organ; hue: view.hue; saturation: view.saturation
      lightness: view.lightness; phase: view.phase
    }
  }
}
