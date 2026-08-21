# Omaraoke

Karaoke overlay for the [Omarchy](https://omarchy.org) shell: one keybinding
clears the screen down to the wallpaper and shows time-synced lyrics for
whatever the system is playing. Press it again and the desktop comes back
exactly as it was.

Lyrics come from [LRCLIB](https://lrclib.net) (open, keyless) and are cached
in `~/.cache/omaraoke/`. Windows are stashed to a `special:karaoke`
workspace and restored on exit. The bar stays up (set `hideBar` to hide it
too), and the overlay never captures mouse or keyboard — you can still
fast-forward from the bar's media widget mid-session.

## Install

```sh
git clone <this repo> ~/.config/omarchy/plugins/igoroh.omaraoke
omarchy plugin enable igoroh.omaraoke
```

Then add a keybinding to `~/.config/hypr/bindings.lua` (plugins cannot ship
keybindings — one manual line, matching Omarchy's installer philosophy):

```lua
o.bind("SUPER + SHIFT + K", "Karaoke", "omarchy-shell shell toggle igoroh.omaraoke")
```

Optional dependency: `pacman -S cava` for the audio-reactive Color Organ
(coming in P2). Without it the lyrics work; the reactive layer is silently
absent.

## Configuration

Settings live inline on the plugin's entry in `~/.config/omarchy/shell.json`:

```json
{ "id": "igoroh.omaraoke", "position": "center", "offsetMs": 0 }
```

| Key               | Default    | Meaning |
|-------------------|------------|---------|
| `monitors`        | `"all"`    | Mirror the overlay on every screen, or `"focused"` only. |
| `position`        | `"lower"`  | Lyrics placement: `"lower"` or `"center"`. |
| `motion`          | `"drift"`  | How the lines move — see below. |
| `offsetMs`        | `0`        | Manual sync nudge (positive = lyrics later). |
| `colorOrgan`      | `true`     | Master switch for the Color Organ (P2). |
| `autoCloseOnStop` | `true`     | Close the session when playback stops (never on pause). |
| `hideBar`         | `false`    | Hide the bar during a session; it returns on close. |
| `pauseOnClose`    | `true`     | Pause the music when the session closes. |
| `playOnOpen`      | `true`     | Resume the music when the session opens. |

### Motion

`"drift"` (default) never holds still: the lines crawl upward continuously,
each one growing from the moment it appears until it sits centred, then
shrinking away. It slows through the middle of a line and sweeps across the
change-over, so the current line is still obvious at a glance. Long lines
crawl slowly, short ones move quickly.

`"handoff"` keeps the current line parked at full size, with a small creep
across the line, and does the growing and shrinking in one sweep just before
the next line starts. Steadier to read; less alive.

## Behaviour notes

- Synced lyrics need a player that reports playback position over MPRIS;
  otherwise you get the full lyrics as a static view.
- Tracks without a match show a `No lyrics found` card; the session stays
  open. Misses are retried after a day.
- Windows opened during a session land under the overlay and appear when it
  closes — deliberate.

## Escape hatch

If the shell dies mid-session your windows are on `special:karaoke` and a
restore map is in `~/.local/state/omaraoke/stash.json`. The shell restores
them automatically on next start; if it won't start, run:

```sh
~/.config/omarchy/plugins/igoroh.omaraoke/bin/omaraoke-restore
```

It needs only `hyprctl` and `jq`.

## Not done yet

- **Color organ** — an audio-reactive layer driven by `cava` band levels: a
  background wash and a pulse on the current line's scrim. The config key and
  the optional dependency are already in place; nothing is drawn yet.
- **Word-by-word following** — highlighting within the line as it is sung,
  rather than a line at a time. Needs per-word timings, which LRCLIB does not
  carry, so it means local transcription and alignment.
- **Sync improvements and fixes** — position is pulled from MPRIS at ~1 Hz and
  extrapolated between polls, which drifts on some players and after seeks.
  `offsetMs` is the manual escape hatch in the meantime.
