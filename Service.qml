import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import "Lyrics.js" as Lyrics

// Omaraoke service: MPRIS tracking, lyrics fetch/cache, stash orchestration,
// stale-Stash recovery on startup. Loaded at shell startup, destroyed and
// re-created on every plugin rescan — all Session-critical state therefore
// lives in ~/.local/state/omaraoke/stash.json, not here.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginDir: {
    var u = Qt.resolvedUrl(".").toString()
    return u.replace(/^file:\/\//, "").replace(/\/$/, "")
  }
  readonly property string pluginId: manifest && manifest.id ? manifest.id : "igoroh.omaraoke"

  // ---- Configuration (inline fields on our plugins[] entry in shell.json) --

  readonly property var pluginConfig: {
    var cfg = shell && shell.shellConfig ? shell.shellConfig : null
    if (!cfg || !Array.isArray(cfg.plugins))
      return ({})
    for (var i = 0; i < cfg.plugins.length; i++)
      if (cfg.plugins[i] && cfg.plugins[i].id === root.pluginId)
        return cfg.plugins[i]
    return ({})
  }
  readonly property string monitorsMode: pluginConfig.monitors === "focused" ? "focused" : "all"
  readonly property string positionPreset: pluginConfig.position === "center" ? "center" : "lower"
  readonly property string motionPreset: pluginConfig.motion === "handoff" ? "handoff" : "drift"
  readonly property bool colorOrganEnabled: pluginConfig.colorOrgan !== false
  readonly property bool autoCloseOnStop: pluginConfig.autoCloseOnStop !== false
  readonly property bool hideBar: pluginConfig.hideBar === true
  readonly property bool pauseOnClose: pluginConfig.pauseOnClose !== false
  readonly property bool playOnOpen: pluginConfig.playOnOpen !== false

  // ---- Track identity (MPRIS, via omarchy.media's own selection) ----------

  readonly property var media: shell ? shell.firstPartyServiceFor("omarchy.media") : null
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: {
    if (media)
      return media.activePlayer
    for (var i = 0; i < players.length; i++)
      if (players[i].isPlaying)
        return players[i]
    return players.length > 0 ? players[0] : null
  }

  readonly property string trackArtist: player ? (player.trackArtist || "") : ""
  readonly property string trackTitle: player ? (player.trackTitle || "") : ""
  readonly property string trackAlbum: player ? (player.trackAlbum || "") : ""
  readonly property real trackLengthS: player && player.lengthSupported ? player.length : 0
  readonly property bool positionUsable: player ? player.positionSupported : false
  readonly property bool playing: player ? player.isPlaying : false
  readonly property string trackSignature: trackArtist + "\u0000" + trackTitle

  // ---- Session state ------------------------------------------------------

  property bool sessionActive: false
  property bool sawPlayback: false
  signal trackStarted()

  // none | loading | synced | static | nolyrics | instrumental
  property string lyricsState: "none"
  property var timeline: []          // LyricsTimeline: [{t: ms, text}]
  property string plainText: ""
  property string fetchSignature: ""

  function beginSession() {
    if (sessionActive)
      return
    console.log("omaraoke: session open")
    sessionActive = true
    sawPlayback = playing
    if (playOnOpen && player && !playing) {
      try {
        if (player.canPlay)
          player.play()
      } catch (e) {}
    }
    stashProc.running = true
    startTrack()
  }

  function endSession() {
    if (!sessionActive)
      return
    console.log("omaraoke: session close")
    if (pauseOnClose && player && playing) {
      try {
        if (player.canPause)
          player.pause()
        else
          player.stop()
      } catch (e) {}
    }
    sessionActive = false
    sawPlayback = false
    lyricsProc.running = false
    lyricsState = "none"
    timeline = []
    plainText = ""
    Quickshell.execDetached(["bash", pluginDir + "/bin/omaraoke-restore"])
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function")
      shell.hide(pluginId)
  }

  // ---- Sync Position ------------------------------------------------------
  // MPRIS position is pull-only: poke positionChanged ~1 Hz to re-query,
  // extrapolate between pulls, hard-resync on seek/state change/drift > 250 ms.

  property real anchorMs: 0
  property real anchorAt: 0

  function nowPositionMs() {
    var p = anchorMs + (playing ? Date.now() - anchorAt : 0)
    return p < 0 ? 0 : p
  }

  function resyncTo(measuredMs) {
    anchorMs = measuredMs
    anchorAt = Date.now()
  }

  function pullPosition(force) {
    if (!player)
      return
    try { player.positionChanged() } catch (e) {}
    var measured = player.position * 1000
    var drift = Math.abs(measured - (anchorMs + (playing ? Date.now() - anchorAt : 0)))
    if (force || drift > 250)
      resyncTo(measured)
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.sessionActive && root.player !== null && root.positionUsable
    onTriggered: root.pullPosition(false)
  }

  Connections {
    target: root.player
    ignoreUnknownSignals: true
    function onPositionChanged() {
      // fires on external seeks and our own pokes; drift-gated so it never loops
      var measured = root.player.position * 1000
      var drift = Math.abs(measured - (root.anchorMs + (root.playing ? Date.now() - root.anchorAt : 0)))
      if (drift > 250)
        root.resyncTo(measured)
    }
    function onPlaybackStateChanged() {
      root.pullPosition(true)
      root.evalAutoClose()
    }
  }

  onPlayingChanged: {
    if (sessionActive && playing)
      sawPlayback = true
    evalAutoClose()
  }

  onPlayerChanged: {
    if (sessionActive) {
      if (player)
        pullPosition(true)
      evalAutoClose()
    }
  }

  // Track skips transiently report Stopped and can drop the active player
  // while the media service re-ranks; auto-close only when the condition
  // holds for the whole grace period, never on the transient.
  function stopConditionNow() {
    if (!player)
      return sawPlayback
    return player.playbackState === MprisPlaybackState.Stopped
  }

  function evalAutoClose() {
    if (!sessionActive || !autoCloseOnStop) {
      stopGraceTimer.stop()
      return
    }
    if (stopConditionNow()) {
      if (!stopGraceTimer.running)
        stopGraceTimer.start()
    } else {
      stopGraceTimer.stop()
    }
  }

  Timer {
    id: stopGraceTimer
    interval: 2500
    onTriggered: {
      if (root.sessionActive && root.autoCloseOnStop && root.stopConditionNow())
        root.requestClose()
    }
  }

  onTrackSignatureChanged: {
    if (sessionActive)
      startTrack()
  }

  // ---- Lyrics pipeline ----------------------------------------------------

  function startTrack() {
    if (!sessionActive)
      return
    timeline = []
    plainText = ""
    if (!player || (trackTitle === "" && trackArtist === "")) {
      lyricsState = "none"
      return
    }
    lyricsState = "loading"
    trackStarted()
    pullPosition(true)
    fetchSignature = trackSignature
    lyricsProc.running = false
    lyricsProc.command = [
      "bash", pluginDir + "/bin/omaraoke-lyrics",
      trackArtist, trackTitle, trackAlbum, String(trackLengthS)
    ]
    lyricsProc.running = true
  }

  function applyLyrics(jsonText) {
    if (!sessionActive || fetchSignature !== trackSignature)
      return
    var rec
    try { rec = JSON.parse(jsonText) } catch (e) { rec = { miss: true } }
    if (rec.instrumental === true) {
      lyricsState = "instrumental"
      return
    }
    if (rec.miss === true) {
      lyricsState = "nolyrics"
      return
    }
    var synced = rec.syncedLyrics || ""
    if (synced !== "" && positionUsable) {
      var tl = Lyrics.parseLrc(synced)
      if (tl.length > 0) {
        timeline = tl
        lyricsState = "synced"
        return
      }
    }
    var plain = rec.plainLyrics || (synced !== "" ? Lyrics.stripLrc(synced) : "")
    if (plain !== "") {
      plainText = plain
      lyricsState = "static"
    } else {
      lyricsState = "nolyrics"
    }
  }

  Process {
    id: lyricsProc
    stdout: StdioCollector {
      onStreamFinished: root.applyLyrics(String(text || ""))
    }
  }

  Process {
    id: stashProc
    command: ["bash", root.pluginDir + "/bin/omaraoke-stash"]
      .concat(root.hideBar ? ["--hide-bar"] : [])
    stderr: StdioCollector {
      onStreamFinished: if (String(text || "") !== "") console.warn("omaraoke-stash:", text)
    }
  }

  // ---- Recovery: a leftover stash.json means a Session died with the shell.
  // The restore script is a no-op without one; flock serializes it against a
  // still-running restore from the previous service instance.

  Timer {
    interval: 1500
    running: true
    onTriggered: {
      if (!root.sessionActive) {
        console.log("omaraoke: startup recovery check")
        Quickshell.execDetached(["bash", root.pluginDir + "/bin/omaraoke-restore"])
      }
    }
  }

  Component.onDestruction: {
    if (sessionActive)
      console.log("omaraoke: service destroyed mid-session")
  }

  // Hyprland auto-shows a special workspace when focus falls back onto a
  // window inside it — e.g. the theme picker closing hands focus to the
  // stashed window that had it before the Session. Re-hide immediately.
  // This Hyprland is Lua-dispatch only (classic `hyprctl dispatch` syntax
  // fails), and the visibility check guards against toggling it back on.
  Connections {
    target: Hyprland
    enabled: root.sessionActive
    function onRawEvent(event) {
      if (event.name === "activespecial"
          && String(event.data).indexOf("special:karaoke") === 0) {
        console.log("omaraoke: stash workspace surfaced, re-hiding")
        Quickshell.execDetached(["bash", "-c",
          "hyprctl monitors -j | jq -e '.[] | select(.specialWorkspace.name==\"special:karaoke\")' >/dev/null" +
          " && hyprctl eval \"hl.dispatch(hl.dsp.workspace.toggle_special('karaoke'))\""])
      }
    }
  }
}
