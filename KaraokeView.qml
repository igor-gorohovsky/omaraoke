import QtQuick
import qs.Commons

// Per-monitor karaoke content: Title Card, Line Stack, Static Mode, and the
// no-lyrics / instrumental / nothing-playing cards. Purely presentational —
// all pipeline state comes from the injected service.
Item {
  id: view

  property var service: null
  property bool active: false

  readonly property string lyricsState: service ? service.lyricsState : "none"
  readonly property var timeline: service ? service.timeline : []
  readonly property string positionPreset: service ? service.positionPreset : "center"
  readonly property string motionPreset: service ? service.motionPreset : "drift"
  readonly property string trackArtist: service ? service.trackArtist : ""
  readonly property string trackTitle: service ? service.trackTitle : ""
  readonly property string trackLabel: trackArtist !== "" && trackTitle !== ""
    ? trackArtist + " — " + trackTitle
    : (trackTitle !== "" ? trackTitle : trackArtist)

  // ---- Scrim: shade opposed to the theme foreground, never by audio -------
  // Contrast with the text is guaranteed by construction; the Scrim's own
  // opacity separates it from any wallpaper behind it.

  readonly property color textColor: Color.foreground
  readonly property color dimTextColor: Util.alpha(Color.foreground, 0.55)
  readonly property real fgLuminance:
    0.2126 * textColor.r + 0.7152 * textColor.g + 0.0722 * textColor.b
  readonly property bool darkScrim: fgLuminance >= 0.5
  readonly property color scrimColor: darkScrim ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(1, 1, 1, 0.65)

  // ---- Sync-driven state --------------------------------------------------

  property real posMs: 0
  property int currentIndex: -1

  function tick() {
    if (!service)
      return
    posMs = service.nowPositionMs()
    var tl = timeline
    var i = currentIndex
    if (i >= tl.length)
      i = tl.length - 1
    while (i + 1 < tl.length && tl[i + 1].t <= posMs)
      i++
    while (i >= 0 && tl[i].t > posMs)
      i--
    if (i !== currentIndex)
      currentIndex = i
  }

  onTimelineChanged: {
    currentIndex = -1
    if (active && lyricsState === "synced")
      tick()
  }

  // ---- Title Card timing --------------------------------------------------

  property bool showTitleCard: false

  Connections {
    target: view.service
    ignoreUnknownSignals: true
    function onTrackStarted() {
      view.showTitleCard = true
      titleCardTimer.restart()
    }
  }

  Timer {
    id: titleCardTimer
    interval: 2000
    onTriggered: view.showTitleCard = false
  }

  readonly property string mode: {
    if (lyricsState === "none")
      return "card"
    if (showTitleCard || lyricsState === "loading")
      return "title"
    if (lyricsState === "synced")
      return "stack"
    if (lyricsState === "static")
      return "static"
    return "card"   // nolyrics | instrumental
  }
  readonly property string cardSubtitle: {
    if (lyricsState === "none")
      return "Nothing playing"
    if (lyricsState === "instrumental")
      return "Instrumental"
    return "No lyrics found"
  }

  // ---- Cards --------------------------------------------------------------

  component CardBox: Rectangle {
    property alias primary: primaryText.text
    property alias secondary: secondaryText.text
    color: view.scrimColor
    radius: Style.cornerRadius * 2
    width: content.width + Style.space(48)
    height: content.height + Style.space(32)
    anchors.centerIn: parent
    Column {
      id: content
      anchors.centerIn: parent
      spacing: Style.spacing.md
      Text {
        id: primaryText
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(implicitWidth, view.width * 0.8)
        wrapMode: Text.Wrap
        // Everything shown here arrives from LRCLIB or MPRIS, i.e. from
        // outside. AutoText would sniff such a payload as rich text and let
        // markup in it (an <img src>, say) pull a remote resource. Plain.
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        color: view.textColor
        font.family: Style.font.family
        font.pixelSize: Style.font.displayLarge
        font.bold: true
      }
      Text {
        id: secondaryText
        anchors.horizontalCenter: parent.horizontalCenter
        visible: text !== ""
        textFormat: Text.PlainText
        color: view.dimTextColor
        font.family: Style.font.family
        font.pixelSize: Style.font.title
      }
    }
  }

  Item {
    anchors.fill: parent
    opacity: view.mode === "title" ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 400 } }
    CardBox {
      primary: view.trackLabel !== "" ? view.trackLabel : "Omaraoke"
      secondary: ""
    }
  }

  Item {
    anchors.fill: parent
    opacity: view.mode === "card" ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 400 } }
    CardBox {
      primary: view.trackLabel !== "" ? view.trackLabel : "Omaraoke"
      secondary: view.cardSubtitle
    }
  }

  // ---- Line Stack ---------------------------------------------------------

  Item {
    id: stack
    anchors.fill: parent
    opacity: view.mode === "stack" ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 400 } }

    readonly property real slotH: Math.round(height * 0.11)
    readonly property real centerY: view.positionPreset === "lower" ? height * 0.72 : height * 0.5

    // Lines are laid out at the centre line's size and scaled down as they move
    // away from it: growth is a transform, so it costs no text relayout and
    // never renders an upscaled glyph.
    readonly property int lineSize: Math.max(1, Math.round(slotH * 0.38))
    readonly property real farScale: 0.27 / 0.38

    // Two motion models, chosen by the `motion` config key. They differ only in
    // *when* a line changes size, and both feed the same three outputs below —
    // shownOffset, and each slot's prominence and opacity.
    readonly property bool drifting: view.motionPreset !== "handoff"

    // Distance from the centre, in slots, at which a Drift line has faded out
    // completely. 1.5 keeps exactly three lines lit: the centred one covers
    // ±0.5, and its two neighbours run from there to the edge.
    readonly property real reach: 1.5

    // How much of a Drift line's travel is pushed out to its edges, so it
    // lingers near the centre and sweeps through the change-over. 0 is a flat
    // crawl (every line the same size as its neighbour half the time — you
    // cannot tell which one is being sung); approaching 1 stalls dead at the
    // centre. 0.7 spends half of every line inside ±0.14 slots while never
    // dropping below 0.3× the average speed.
    readonly property real dwell: 0.7

    // Size, weight and colour ride a sharpened falloff so the centre line reads
    // as the current one at a glance; opacity keeps the gentle one so the line
    // ahead stays legible.
    readonly property real sharpness: 1.6

    // How long before the next line's timestamp a Hand-off starts.
    readonly property int leadMs: 600

    // Motion, computed imperatively each frame. A Behavior cannot work anywhere
    // in here: a per-frame binding change would restart its animation at t=0
    // every frame, freezing the value entirely.
    property real shownOffset: 0

    // Which line — fractionally — is sitting on the centre line right now.
    // Drift slots derive their whole look from their distance to this, so size,
    // weight and opacity are functions of position alone: already correct at
    // the moment the line index changes (nothing snaps) and never equal on two
    // consecutive frames (nothing parks).
    readonly property real centreIndex: slotH > 0 ? shownOffset / slotH : 0

    // Fraction of a Hand-off from the current line to the next: 0 while the
    // current line holds the centre, reaching 1 exactly as the next line takes
    // over, so the index change cancels the shift of every line's slot. Always
    // 0 under Drift, which has no line-change event to speak of.
    property real morph: 0

    // Raised cosine: 1 on the centre line, 0 at `reach`, flat at both ends so
    // the swell has no seam where a line enters, peaks, or leaves.
    function bell(d) {
      return 0.5 * (1 + Math.cos(Math.PI * Math.min(1, Math.abs(d) / reach)))
    }

    FrameAnimation {
      running: view.active && view.lyricsState === "synced"
      onTriggered: stack.tickMotion()
    }

    // Velocity shaping for Drift: slow through the middle of a line, quick
    // across the change-over, and never stationary. Exact at both ends
    // (0 → 0, 1 → 1) with matching slopes there, so consecutive lines join
    // without a visible kick.
    function dwellEase(t) {
      var x = Math.min(1, Math.max(0, t))
      return x + dwell * Math.sin(2 * Math.PI * x) / (2 * Math.PI)
    }

    // Drift: one slot per line. A line enters from the bottom, crosses the
    // centre around its own midpoint, and is leaving the top as the line after
    // it arrives. Long lines drift slowly, short ones quickly.
    function driftAt() {
      var tl = view.timeline
      if (tl.length === 0)
        return 0
      var i = view.currentIndex
      var start, end
      var cap = 1
      if (i < 0) {
        // Pre-roll: line 0 rises into place over the last 5 s before it starts.
        end = tl[0].t
        start = end - 5000
      } else if (i + 1 < tl.length) {
        start = tl[i].t
        end = tl[i + 1].t
      } else {
        // Nothing follows the last line, so it rises to the centre and holds.
        start = tl[i].t
        end = start + 5000
        cap = 0.5
      }
      var m = end > start ? dwellEase((view.posMs - start) / (end - start)) : cap
      return (i + Math.min(cap, m) - 0.5) * slotH
    }

    function morphAt() {
      var tl = view.timeline
      var i = view.currentIndex
      if (i + 1 >= tl.length)
        return 0
      var end = tl[i + 1].t
      var start = i >= 0 ? tl[i].t : end - 5000
      var lead = Math.min(leadMs, Math.max(1, (end - start) * 0.5))
      return Math.min(1, Math.max(0, (view.posMs - (end - lead)) / lead))
    }

    // Hand-off: in-line creep capped at 25% of a slot, folded away as the
    // hand-off carries the remaining travel — the sum stays monotonic.
    function handoffAt(m) {
      var tl = view.timeline
      var i = view.currentIndex
      var creep = 0
      if (i >= 0 && i < tl.length) {
        var start = tl[i].t
        var end = i + 1 < tl.length ? tl[i + 1].t : start + 5000
        if (end > start)
          creep = Math.min(1, Math.max(0, (view.posMs - start) / (end - start))) * 0.25 * slotH
      }
      return i * slotH + creep * (1 - m) + m * slotH
    }

    function tickMotion() {
      view.tick()
      if (drifting) {
        morph = 0
        shownOffset = driftAt()
      } else {
        morph = morphAt()
        shownOffset = handoffAt(morph)
      }
    }

    onDriftingChanged: if (visible) tickMotion()

    onVisibleChanged: {
      if (visible)
        tickMotion()
    }

    Item {
      id: scroller
      width: parent.width
      y: stack.centerY - stack.shownOffset

      Repeater {
        model: view.timeline

        Item {
          id: slot
          required property int index
          required property var modelData

          // Signed distance from the centre line, in slots. Under Drift this is
          // the one input the whole look needs, and it moves every frame.
          readonly property real dist: index - stack.centreIndex
          readonly property int rel: index - view.currentIndex

          // 1 while this line owns the centre, 0 while it is far out. Drives
          // size, weight and colour — everything that says "this is the line
          // being sung". Under Hand-off only the outgoing and incoming pair
          // move, and they trade exactly, so the centre is never half-empty.
          readonly property real prominence: stack.drifting
            ? Math.pow(stack.bell(dist), stack.sharpness)
            : (rel === 0 ? 1 - stack.morph : (rel === 1 ? stack.morph : 0))

          visible: (stack.drifting ? Math.abs(dist) < stack.reach : rel >= -1 && rel <= 2)
            && modelData.text !== ""
          // Legibility, kept separate from prominence so the line ahead can stay
          // readable while being unmistakably not the current one. Under
          // Hand-off the previous line fades out across the same morph that
          // fades the one after next in — the stack scrolls a whole slot, so
          // something has to leave the top as something enters the bottom. That
          // is also what keeps the pair continuous at the index change: the
          // outgoing line is already at zero when the line behind it inherits
          // the slot, so only three lines are ever lit at rest.
          opacity: stack.drifting ? stack.bell(dist)
            : (rel === -1 ? 0.65 * (1 - stack.morph)
              : (rel === 2 ? 0.65 * stack.morph : 0.65 + 0.35 * prominence))
          width: scroller.width
          height: stack.slotH
          y: index * stack.slotH - height / 2

          Item {
            anchors.centerIn: parent
            width: plate.width
            height: plate.height
            transformOrigin: Item.Center
            scale: stack.farScale + (1 - stack.farScale) * slot.prominence

            Rectangle {
              id: plate
              width: lineText.width + Style.space(36)
              height: lineText.height + Style.space(20)
              radius: Style.cornerRadius * 2
              color: view.scrimColor
            }

            Text {
              id: lineText
              anchors.centerIn: plate
              width: Math.min(implicitWidth, stack.width * 0.85)
              wrapMode: Text.Wrap
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: slot.modelData.text
              color: Util.alpha(Color.foreground, 0.55 + 0.45 * slot.prominence)
              font.family: Style.font.family
              font.pixelSize: stack.lineSize
              // Interpolated so variable fonts thicken smoothly; a family with
              // only Regular and Bold degrades to a flip at the midpoint.
              font.weight: Math.round(Font.Normal + (Font.Bold - Font.Normal) * slot.prominence)
            }
          }
        }
      }
    }
  }

  // ---- Static Mode --------------------------------------------------------

  Rectangle {
    anchors.centerIn: parent
    width: Math.min(view.width * 0.7, staticText.implicitWidth + Style.space(64))
    height: Math.min(view.height * 0.75, staticText.implicitHeight + Style.space(48))
    radius: Style.cornerRadius * 2
    color: view.scrimColor
    opacity: view.mode === "static" ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 400 } }

    Flickable {
      anchors.fill: parent
      anchors.margins: Style.space(24)
      contentWidth: width
      contentHeight: staticText.height
      clip: true

      Text {
        id: staticText
        width: parent.width
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: view.service ? view.service.plainText : ""
        color: view.textColor
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        lineHeight: 1.35
      }
    }
  }
}
