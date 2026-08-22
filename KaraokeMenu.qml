import QtQuick
import qs.Commons
import qs.Ui

// Omaraoke's bar menu: the keybinding-free way to run a Session, plus the few
// settings worth changing on the spot. Settings are read from and written to
// the widget's own bar.layout entry — one plugin, one entry, values inline on
// it — which is what Service.qml reads and what `omarchy bar set` edits.
Panel {
  id: root
  moduleName: "igoroh.omaraoke"

  // Injected by BarWidget.qml.
  property var anchorItem: null
  property var hostWidget: null
  // The bar tracks the widget mounted in its slot, not this nested menu, so
  // everything the bar identifies a popout by must be that widget.
  readonly property var barIdentity: hostWidget || root

  readonly property string pluginId: "igoroh.omaraoke"
  readonly property var shellRoot: bar ? bar.shell : null
  readonly property var service: shellRoot && typeof shellRoot.serviceFor === "function"
    ? shellRoot.serviceFor(root.pluginId)
    : null
  readonly property bool sessionActive: service ? service.sessionActive === true : false

  // `settings` is the bar-layout entry the bar injects, minus its id. Read it
  // in the binding rather than through setting(): the bar replaces the whole
  // object when the entry changes, and reading it here is what makes these
  // track that.
  readonly property string motionValue: {
    var value = settings ? settings.motion : undefined
    return value === "handoff" ? "handoff" : "drift"
  }
  readonly property string positionValue: {
    var value = settings ? settings.position : undefined
    return value === "center" ? "center" : "lower"
  }
  readonly property string stayAwakeValue: {
    var value = settings ? settings.stayAwake : undefined
    return value === false ? "off" : "on"
  }
  readonly property string colorOrganValue: {
    var value = settings ? settings.colorOrgan : undefined
    return value === false ? "off" : "on"
  }

  readonly property var motionOptions: [
    { value: "drift", label: "Drift" },
    { value: "handoff", label: "Hand-off" }
  ]
  readonly property var positionOptions: [
    { value: "lower", label: "Lower" },
    { value: "center", label: "Center" }
  ]
  readonly property var stayAwakeOptions: [
    { value: "on", label: "On" },
    { value: "off", label: "Off" }
  ]
  readonly property var colorOrganOptions: [
    { value: "on", label: "On" },
    { value: "off", label: "Off" }
  ]

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string fontFam: bar ? bar.fontFamily : Style.font.family

  // ---- Keyboard cursor: row 0 is the Session action, rows 1 to 4 are the
  //      two-option settings. Mouse hover moves the same cursor, so only one
  //      highlight is ever on screen.
  property bool cursorActive: false
  property int cursorRow: 0
  property int cursorCol: 0

  function columnsIn(row) {
    return row === 0 ? 1 : 2
  }

  function moveCursor(dx, dy) {
    if (!cursorActive) {
      cursorActive = true
      return
    }
    if (dy !== 0) {
      cursorRow = Math.max(0, Math.min(4, cursorRow + dy))
      cursorCol = Math.min(cursorCol, columnsIn(cursorRow) - 1)
    } else if (dx !== 0) {
      cursorCol = Math.max(0, Math.min(columnsIn(cursorRow) - 1, cursorCol + dx))
    }
  }

  function activateCursor() {
    if (!cursorActive)
      return
    if (cursorRow === 0)
      toggleSession()
    else if (cursorRow === 1)
      writeSetting("motion", motionOptions[cursorCol].value)
    else if (cursorRow === 2)
      writeSetting("position", positionOptions[cursorCol].value)
    else if (cursorRow === 3)
      writeSetting("stayAwake", stayAwakeOptions[cursorCol].value === "on")
    else
      writeSetting("colorOrgan", colorOrganOptions[cursorCol].value === "on")
  }

  function setCursor(row, col) {
    cursorActive = true
    cursorRow = row
    cursorCol = col
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorRow = 0
      cursorCol = 0
    }
  }

  // ---- Actions ------------------------------------------------------------

  // The same toggle the keybinding fires: the shell owns the overlay's
  // open/close, and Session state follows from it.
  function toggleSession() {
    if (shellRoot && typeof shellRoot.toggle === "function")
      shellRoot.toggle(root.pluginId)
    else if (bar)
      bar.run("omarchy-shell shell toggle " + root.pluginId)
    root.close()
  }

  // setBarWidget is the registry's own verb for a per-widget option — the one
  // behind `omarchy bar set` — so the menu writes settings exactly the way the
  // shell does: inline on the widget's layout entry, persisted through the
  // shell's config API, with the registry told about it afterwards.
  function writeSetting(key, value) {
    var registry = shellRoot ? shellRoot.pluginRegistry : null
    if (!registry || typeof registry.setBarWidget !== "function") {
      console.warn("omaraoke: no plugin registry, cannot save", key)
      return
    }
    var error = registry.setBarWidget(root.pluginId, key, value)
    if (error)
      console.warn("omaraoke: could not save", key + ":", error)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(260))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Session ----------
        Button {
          width: parent.width
          iconText: root.sessionActive ? "󰓛" : "󰐊"
          iconSize: Style.font.title
          text: root.sessionActive ? "Stop Karaoke" : "Start Karaoke"
          fontSize: Style.font.body
          foreground: root.fg
          fontFamily: root.fontFam
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          bordered: true
          hasCursor: root.cursorActive && root.cursorRow === 0
          onClicked: root.toggleSession()
          onHovered: function(h) { if (h) root.setCursor(0, 0) }
        }

        PanelSeparator {
          foreground: root.fg
        }

        // ---------- Motion ----------
        ChoiceRow {
          row: 1
          title: "MOTION"
          options: root.motionOptions
          current: root.motionValue
          onChosen: function(value) { root.writeSetting("motion", value) }
        }

        // ---------- Position ----------
        ChoiceRow {
          row: 2
          title: "POSITION"
          options: root.positionOptions
          current: root.positionValue
          onChosen: function(value) { root.writeSetting("position", value) }
        }

        // ---------- Stay Awake ----------
        // On: the Session flips the shell's own Stay Awake state (the topbar
        // 󰅶 glyph) for its duration, holding off screensaver and lock;
        // restored on close unless the user had it on already.
        ChoiceRow {
          row: 3
          title: "STAY AWAKE"
          options: root.stayAwakeOptions
          current: root.stayAwakeValue
          onChosen: function(value) { root.writeSetting("stayAwake", value === "on") }
        }

        // ---------- Effects ----------
        // Off: the reactive layer is never built and the capture pipeline
        // never starts, leaving just the lyrics over the wallpaper.
        ChoiceRow {
          row: 4
          title: "EFFECTS"
          options: root.colorOrganOptions
          current: root.colorOrganValue
          onChosen: function(value) { root.writeSetting("colorOrgan", value === "on") }
        }
      }
    }
  }

  component ChoiceRow: Column {
    id: choice

    property int row: 0
    property string title: ""
    property var options: []
    // Cells per line; options beyond it wrap. The keyboard cursor still walks
    // the options as one flat row — left/right crosses the visual break.
    property int columns: options.length
    property string current: ""

    signal chosen(string value)

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(8)

    PanelSectionHeader {
      text: choice.title
      foreground: root.fg
      fontFamily: root.fontFam
    }

    Grid {
      id: optionRow
      width: parent.width
      columns: Math.max(1, choice.columns)
      columnSpacing: Style.space(6)
      rowSpacing: Style.space(6)

      readonly property real cellWidth: columns > 0
        ? (width - columnSpacing * (columns - 1)) / columns
        : 0

      Repeater {
        model: choice.options

        Button {
          required property var modelData
          required property int index
          width: optionRow.cellWidth
          text: modelData.label
          fontSize: Style.font.bodySmall
          foreground: root.fg
          fontFamily: root.fontFam
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          bordered: true
          active: choice.current === modelData.value
          hasCursor: root.cursorActive && root.cursorRow === choice.row && root.cursorCol === index
          onClicked: choice.chosen(modelData.value)
          onHovered: function(h) { if (h) root.setCursor(choice.row, index) }
        }
      }
    }
  }
}
