import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Omaraoke overlay: one fullscreen Overlay-layer surface per monitor
// (respecting the `monitors` config), transparent down to the wallpaper.
// The shell toggles us via open()/close() and reads `opened`; our own
// service instance is injected as `service`.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false

  function open(payloadJson) {
    console.log("omaraoke: overlay open")
    root.opened = true
    if (root.service)
      root.service.beginSession()
  }

  function close() {
    console.log("omaraoke: overlay close")
    root.opened = false
    if (root.service)
      root.service.endSession()
  }

  readonly property string monitorsMode: service ? service.monitorsMode : "all"
  readonly property string focusedMonitor: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      visible: root.opened
        && (root.monitorsMode !== "focused" || modelData.name === root.focusedMonitor)
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "omaraoke"
      WlrLayershell.layer: WlrLayer.Overlay
      // The Session never captures input: no keyboard focus, and an empty
      // input mask lets clicks fall through to the bar beneath (seek/skip
      // on its media widget). P2.5 narrows the mask to the Line Stack for
      // drag/resize instead of removing it.
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      // The Color Organ sits under the karaoke content and over the
      // wallpaper. It draws nothing at all when disabled or unavailable.
      OrganView {
        anchors.fill: parent
        service: root.service
        active: panel.visible
      }

      KaraokeView {
        anchors.fill: parent
        service: root.service
        active: panel.visible
      }
    }
  }
}
