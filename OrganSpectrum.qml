import QtQuick

// Spectrum: thin mirrored bars along the bottom edge — bass at the centre,
// the top band at each outer edge. Restrained on purpose: this is a floor the
// lyrics stand on, not a media player skin, so it is capped at a sixth of the
// screen and never draws peak caps or a grid.
//
// The bank's own bands are shown directly. That is the point of owning the
// DSP: the count and the layout are ours to choose rather than a visualiser's
// terminal-shaped defaults.
Item {
  id: scene

  property var organ: null
  property real hue: 0
  property real saturation: 0.6
  property real lightness: 0.6
  property real phase: 0

  readonly property int bandCount: organ ? organ.bandCount : 0
  readonly property real slotW: bandCount > 0 ? width / (bandCount * 2) : 0
  readonly property real maxBar: height * 0.16
  readonly property color barColor: Qt.hsla(hue, saturation, lightness, 1)

  // A low wash under the bars so they belong to the screen rather than sitting
  // on it. Bass only, so it breathes with the track and not with each bar.
  OrganGlow {
    tint: scene.barColor
    opacity: 0.06 + 0.20 * (scene.organ ? scene.organ.bass : 0)
    width: scene.width * 1.6
    height: scene.height * 0.55
    x: (scene.width - width) / 2
    y: scene.height - height / 2
    coreAlpha: 0.36
    midAlpha: 0.10
  }

  Repeater {
    id: bars
    model: scene.bandCount * 2

    Item {
      required property int index
      // Mirrored about the centre: the outermost slot is the top band, and the
      // two bass bands meet in the middle.
      readonly property int band: index < scene.bandCount
        ? scene.bandCount - 1 - index
        : index - scene.bandCount
      property real level: 0

      x: index * scene.slotW
      width: scene.slotW
      height: scene.height

      Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(1, scene.slotW * 0.30)
        radius: width / 2
        // A floor height keeps the row readable as a row while the track is
        // quiet, instead of dissolving into disconnected stubs.
        height: scene.maxBar * (0.03 + 0.97 * parent.level)
        color: scene.barColor
        opacity: 0.20 + 0.55 * parent.level
      }
    }
  }

  // Levels come from a Float64Array the analyzer mutates in place — it emits
  // no change signal, so the row is written here rather than bound.
  FrameAnimation {
    running: scene.visible && scene.organ !== null && scene.organ.available
    onTriggered: {
      var levels = scene.organ.levels
      for (var i = 0; i < bars.count; i++) {
        var slot = bars.itemAt(i)
        if (slot)
          slot.level = levels[slot.band]
      }
    }
  }
}
