import QtQuick
import qs.Ui

// Omaraoke's bar item: a music glyph that opens the karaoke menu. The icon
// stays in the bar for as long as the plugin is enabled — it dims when no
// MPRIS player is around, but it never disappears, because the menu is also
// where the Session's settings live. Clicking it only opens the menu; the
// Session itself is started and stopped from the first menu row.
BarWidget {
  id: root
  moduleName: "igoroh.omaraoke"

  readonly property string pluginId: "igoroh.omaraoke"
  readonly property var shellRoot: bar ? bar.shell : null
  // serviceFor() reads shell._services, which the shell replaces wholesale
  // when a service is created or dropped, so this binding tracks the live
  // Service instance rather than latching onto whatever existed at load.
  readonly property var service: shellRoot && typeof shellRoot.serviceFor === "function"
    ? shellRoot.serviceFor(root.pluginId)
    : null
  readonly property bool sessionActive: service ? service.sessionActive === true : false
  readonly property bool playerAvailable: service ? service.player !== null : false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function injectMenu() {
    var target = menuLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function toggleMenu() {
    if (menuLoader.item && menuLoader.item.toggle) menuLoader.item.toggle()
  }

  // Tab order between bar panels is built by Bar.panelNavigationSlots, which
  // only counts a slot whose root carries open(), close() and opened. Miss any
  // one and the menu drops out of the walk entirely: tabbing never reaches it,
  // and switchPanelFrom cannot find our own index to tab away from it either.
  // close() doubles as what KeyboardPanel dismisses through and what the
  // popout coordinator falls back to when a switch hook is missing.
  function open() {
    if (menuLoader.item && menuLoader.item.open) menuLoader.item.open()
  }

  function close() {
    if (menuLoader.item && menuLoader.item.close) menuLoader.item.close()
  }

  // The bar's popout coordinator tracks the widget in its slot, not the
  // nested menu, so the switch-away hooks have to be readable from here.
  readonly property bool opened: menuLoader.item ? menuLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: menuLoader.item
    ? menuLoader.item.popoutSwitchClosing === true
    : false

  function closeForPopoutSwitch() {
    if (menuLoader.item) menuLoader.item.closeForPopoutSwitch()
  }

  onBarChanged: injectMenu()
  onSettingsChanged: injectMenu()

  Loader {
    id: menuLoader
    active: true
    source: Qt.resolvedUrl("KaraokeMenu.qml")
    visible: false
    onLoaded: {
      root.injectMenu()
      Qt.callLater(root.injectMenu)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰝚"
    tooltipText: "Omaraoke"
    active: root.sessionActive
    dimmed: !root.playerAvailable && !root.sessionActive
    onPressed: function(b) { root.toggleMenu() }
  }
}
