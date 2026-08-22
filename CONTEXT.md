# Omaraoke

Karaoke overlay plugin for the Omarchy shell: clears the desktop, shows synced
lyrics for the system-playing track, reacts to the audio.

## Language

**Session**:
The period between summoning the overlay and closing it (Bar Menu or keybinding
again, or auto-close on playback Stopped). Everything stashed at open is
restored at close.
_Avoid_: karaoke mode, fullscreen mode

**Bar Menu**:
The popup behind Omaraoke's bar icon: a row that starts or stops the Session,
and the Motion, Position and Stay Awake choices. The keybinding-free way in, and the only
place the plugin writes configuration — inline on its own `bar.layout` entry
in `shell.json`, through the registry's `setBarWidget`. That entry is the
plugin's single entry: enablement, placement and every setting live on it.
_Avoid_: settings panel, tray menu, popup

**Stash**:
The set of windows moved to the `special:karaoke` workspace for a Session,
together with the persisted `address → workspace` restore map. Independent of
the user's show-desktop stash.
_Avoid_: minimized windows, hidden windows

**Line Stack**:
The three-line lyrics display: previous, current, next line, each on its own
Scrim, moving upward with playback.
_Avoid_: lyrics view, subtitle box

**Drift**:
One of the two Line Stack motion models (`motion: "drift"`, the default): a
constant upward crawl of one line height per lyric line. Size, weight and
opacity follow each line's distance from the centre, so every line grows from
the moment it appears until it is centred and shrinks until it is gone. There
is no line-change animation because nothing about the look depends on the line
index. The travel is shaped to linger near the centre and sweep through the
change-over, and size is sharpened relative to opacity, so the current line
still reads as current without the motion ever stopping.
_Avoid_: scroll, line change animation, transition

**Hand-off**:
The other Line Stack motion model (`motion: "handoff"`): the current line holds
the centre, the stack creeps ~25% of a line height across the line, and one
0→1 fraction over the last ~600 ms carries the rest of the travel while trading
size, weight and opacity between the outgoing and incoming lines.
_Avoid_: line change animation, transition

**Scrim**:
The rounded translucent backdrop behind a lyric line. Black or white, opposed
to the theme foreground's luminance so text contrast is guaranteed;
re-evaluated on theme change (never by audio); only its geometry and glow may
animate — see Scrim Pulse.
_Avoid_: background box, shade

**Color Organ**:
The audio-reactive layer as a whole: the capture pipeline, the signal layer
derived from it, the Scene it drives, and the Scrim pulse. Never modulates
text color, and never the Scrim's black/white choice.
_Avoid_: visualizer, spectrum

**Signal Layer**:
Everything between the captured samples and a Scene: the Goertzel bank, the
auto-gain, the per-band envelopes, the derived Signal Channels and the beat
detector. Lives in `Dsp.js` with no QML dependency, so it is testable under
node. One instance per shell, shared by every monitor.
_Avoid_: analyzer, FFT, DSP layer

**Signal Channel**:
One of the five 0–1 values a Scene consumes: `bass`, `mid`, `high`, `energy`
and `beatPulse`. The first four are slew-limited and are the only ones a Scene
may map to brightness; `beatPulse` rises faster and drives geometry only.
_Avoid_: band, level, value

**Scene**:
One consumer of the Signal Channels — one whole look for the reactive layer.
Exactly one is drawn at a time, per monitor, chosen by the `organStyle` key or
by a hash of the track when that is `"shuffle"`. Named ones: Breath (the
default), Spectrum, Embers, Aurora.
_Avoid_: effect, mode, style, visualization

**Scrim Pulse**:
The always-on part of the Color Organ: the current line's plate swelling ~2%
and picking up a glow with the mid/high envelope, whatever Scene is running.
_Avoid_: beat effect, bounce

**Title Card**:
The ~2 s `Artist — Title` display shown at Session open and on each track
change, before the Line Stack appears.

**No-Lyrics Card**:
The `Artist — Title` + `No lyrics found` display when no Track Match exists.
The Session stays open behind it.

**Track Match**:
The LRCLIB entry resolved for the current MPRIS track via the matching ladder
(get → get-without-album → search with ±3 s duration tolerance).

**Cleaned Title**:
The MPRIS title after stripping decorations (`(Official Video)`, `[HD]`,
`feat.` clauses) and splitting `Artist – Title` when the reported artist is a
channel name.

**Sync Position**:
The playback position the display trusts: MPRIS position pulled ~1 Hz,
extrapolated with a monotonic clock, hard-resynced on Seeked/state
change/drift > 250 ms.

**Static Mode**:
The fallback display when no timestamps are usable (plain lyrics only, or the
player reports `positionSupported: false`): full lyrics, scrollable, no sync.

**Escape Hatch**:
`bin/omaraoke-restore` — the standalone script that restores a leftover Stash
when the shell itself cannot.
