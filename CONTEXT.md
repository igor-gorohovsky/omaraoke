# Omaraoke

Karaoke overlay plugin for the Omarchy shell: clears the desktop, shows synced
lyrics for the system-playing track, reacts to the audio.

## Language

**Session**:
The period between summoning the overlay and closing it (keybinding again, or
auto-close on playback Stopped). Everything stashed at open is restored at close.
_Avoid_: karaoke mode, fullscreen mode

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
re-evaluated on theme change (never by audio); only its geometry/glow may
animate.
_Avoid_: background box, shade

**Color Organ**:
The audio-reactive layer: cava band levels driving a background wash and the
current line's Scrim pulse. Never modulates text color.
_Avoid_: visualizer, spectrum

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
