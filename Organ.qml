import QtQuick
import Quickshell.Io
import "Dsp.js" as Dsp

// Color Organ signal service: one capture pipeline for the whole shell,
// feeding one analyzer, read by every monitor's scene. Owned by Service.qml
// and exposed as `service.organ`.
//
// Everything below the parser is in Dsp.js, which has no QML dependency and is
// tested standalone (tests/dsp.js). This file is only responsible for keeping
// the pipeline alive and for turning its output into properties a scene can
// bind to.
Item {
  id: root

  property string pluginDir: ""
  // Set by Service: a Session is open and `colorOrgan` is not switched off.
  // Deliberately not named `enabled` — that is QQuickItem's, and shadowing it
  // would also gate input handling for everything beneath.
  property bool wanted: false

  readonly property bool running: wanted && pluginDir !== ""

  // False until the pipeline has actually delivered a hop, and again once we
  // stop trying. Scenes key their whole existence off this, so a machine
  // without a working capture shows no organ at all rather than a dead one.
  property bool available: false

  // ---- The signal API every scene consumes ---------------------------------
  // All 0..1. Written once per frame, so a plain binding on any of them is
  // already a per-frame update — but a Behavior on one would restart at t=0
  // every frame and freeze the value (same reason as the Line Stack's motion).
  //
  // bass/mid/high/energy are slew-limited in Dsp.js and are the only channels
  // a scene may map to brightness. beatPulse rises faster than that limit
  // allows, so it drives geometry — radius, scale, particle bursts — never the
  // brightness of a large area.

  property real bass: 0
  property real mid: 0
  property real high: 0
  property real energy: 0
  property real beatPulse: 0

  // Per-band levels, low to high. A stable Float64Array mutated in place: it
  // emits no change signal, so a spectrum reads it from its own FrameAnimation
  // rather than binding to it.
  readonly property var levels: analyzer.bands
  readonly property int bandCount: analyzer.options.bandCount

  signal beat()

  // ---- Capture -------------------------------------------------------------

  property var analyzer: Dsp.createAnalyzer()
  property int hopSize: analyzer.options.hopSize
  property var samples: new Int16Array(analyzer.options.hopSize)

  property real lastDataAt: 0
  property int failures: 0
  property int seenBeats: 0

  // Restart backoff, doubling to a ceiling. Reset by the first hop that
  // arrives, so a pipeline that dies once an hour never accumulates delay.
  readonly property int backoffMs: Math.min(8000, 500 * Math.pow(2, Math.min(4, failures)))

  onRunningChanged: {
    if (running) {
      failures = 0
      available = false
      capture.running = true
    } else {
      retry.stop()
      capture.running = false
      analyzer.reset()
      available = false
      bass = mid = high = energy = beatPulse = 0
      seenBeats = 0
    }
  }

  Process {
    id: capture
    command: ["bash", root.pluginDir + "/bin/omaraoke-capture",
              String(root.analyzer.options.sampleRate), String(root.hopSize)]
    stdout: SplitParser {
      onRead: function (line) { root.consume(line) }
    }
    onExited: function (exitCode) {
      if (!root.running)
        return
      // 127 is the script's "pw-record is not installed" exit. Nothing about
      // that will change while the shell runs, so stop rather than spin.
      if (exitCode === 127) {
        console.warn("omaraoke: no pw-record; color organ disabled")
        root.available = false
        return
      }
      root.failures++
      retry.interval = root.backoffMs
      retry.restart()
    }
  }

  Timer {
    id: retry
    onTriggered: if (root.running && !capture.running) capture.running = true
  }

  // A sink monitor emits silence as zeros, so the stream never legitimately
  // pauses: a gap means the pipeline is wedged (the default sink vanished
  // rather than merely changed, say). Restarting is the only recovery.
  Timer {
    interval: 2000
    repeat: true
    running: root.running && root.available
    onTriggered: {
      if (Date.now() - root.lastDataAt > 2000) {
        console.warn("omaraoke: capture stalled, restarting")
        capture.running = false
      }
    }
  }

  // One od line is exactly one hop. Parsed into a pre-allocated buffer: this
  // runs 31 times a second for the length of a Session.
  function consume(line) {
    var parts = String(line).trim().split(/\s+/)
    var n = Math.min(parts.length, samples.length)
    if (n === 0)
      return
    for (var i = 0; i < n; i++)
      samples[i] = Number(parts[i]) | 0
    analyzer.feed(samples, n)
    lastDataAt = Date.now()
    if (!available) {
      available = true
      failures = 0
    }
  }

  // ---- Frame loop ----------------------------------------------------------
  // Envelopes and derived channels advance here rather than per hop, so every
  // output is continuous at the display's rate even though the bank only looks
  // at the audio 31 times a second.

  FrameAnimation {
    running: root.running && root.available
    onTriggered: {
      var a = root.analyzer
      // Between a pipeline dying and its restart delivering the first hop, the
      // bank has nothing new to say. Without this the envelopes would converge
      // on the last hop and hold there, freezing the Scene mid-swell.
      if (Date.now() - root.lastDataAt > 300)
        a.silence()
      a.advance(frameTime)
      root.bass = a.bass
      root.mid = a.mid
      root.high = a.high
      root.energy = a.energy
      root.beatPulse = a.beatPulse
      if (a.beats !== root.seenBeats) {
        root.seenBeats = a.beats
        root.beat()
      }
    }
  }
}
