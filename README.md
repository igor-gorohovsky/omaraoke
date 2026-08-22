# 🎤 Omaraoke

**Your desktop is now a karaoke stage.**

One click in the topbar sweeps every window off the screen, clears down to
your wallpaper, and lights up time-synced lyrics for whatever's playing. Click
again — your desktop snaps back exactly as you left it. No windows harmed.

Works with any player on your system (anything that speaks MPRIS), in any
Omarchy theme, over any wallpaper.

<img width="3840" height="2160" alt="image" src="https://github.com/user-attachments/assets/d46fe981-86df-4cb0-b234-30948ad9f07c" />


https://github.com/user-attachments/assets/231895c6-82a3-4618-ba09-a783588ee2aa

*(54 s, with sound — unmute for the full effect.)*

## 📥 Install

```sh
omarchy plugin add https://github.com/igor-gorohovsky/omaraoke.git --enable
```

## 🎶 Sing

**Play a song, click the music icon in your topbar, hit Start Karaoke, sing.**
Open the menu again and hit Stop Karaoke when you're done — everything comes
back.

### 🎛️ The topbar menu

Installing with `--enable` — or `omarchy plugin enable igoroh.omaraoke` later —
drops the icon into the right-hand section of the bar. Move it with
`omarchy bar move igoroh.omaraoke --section center`.

| Row | What it does |
|---|---|
| **Start Karaoke** / **Stop Karaoke** | Opens or closes the session, exactly as the keybinding does. |
| **Motion** | `Drift` or `Hand-off` — see [Motion](#-pick-your-motion). |
| **Position** | Lyrics `Lower` or `Center`. |

Arrow keys (or `hjkl`) move, `Enter` picks, `Esc` closes. Nothing here needs a
key bound or a config file opened — the menu is the whole no-keybinding path.

> **Coming from 0.1?** Omaraoke is a bar widget now, so it lives in the bar
> layout rather than the plugin list. Re-enable it once to move it across:
> `omarchy plugin disable igoroh.omaraoke && omarchy plugin enable igoroh.omaraoke`.

### ⌨️ Or bind a key

Plugins can't ship keybindings, so add one line to
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + K", "Karaoke", "omarchy-shell shell toggle igoroh.omaraoke")
```

Hit it to start, hit it again to stop.

### 🔎 Or the Omarchy menu

Add one row to `~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"karaoke": {"icon":"󰝚","label":"Karaoke","action":"omarchy-shell shell toggle igoroh.omaraoke"},
```

It lands on the root menu and is searchable — and `omarchy menu summon karaoke`
toggles straight away without drawing the menu, so that works as a keybinding
target too.

---

## ⚙️ Configure

One plugin, one entry: Omaraoke's widget sits in the bar layout in
`~/.config/omarchy/shell.json`, and every setting lives inline on that entry.

```json
{
  "bar": {
    "layout": {
      "right": [
        { "id": "igoroh.omaraoke", "position": "center", "motion": "handoff" }
      ]
    }
  }
}
```

Set one without opening the file:

```sh
omarchy bar set igoroh.omaraoke position center
```

`position` and `motion` are in the topbar menu too; the rest are set here.

| Key               | Default    | Meaning |
|-------------------|------------|---------|
| `monitors`        | `"all"`    | Mirror the overlay on every screen, or `"focused"` only. |
| `position`        | `"lower"`  | Lyrics placement: `"lower"` or `"center"`. |
| `motion`          | `"drift"`  | How the lines move — see [Motion](#-pick-your-motion). |
| `colorOrgan`      | `true`     | Master switch for the Color Organ (P2). |
| `autoCloseOnStop` | `true`     | Close the session when playback stops (never on pause). |
| `hideBar`         | `false`    | Hide the bar during a session; it returns on close. |
| `pauseOnClose`    | `true`     | Pause the music when the session closes. |
| `playOnOpen`      | `true`     | Resume the music when the session opens. |

## 🌊 Pick your motion

**`drift`** (default) never holds still: the lines crawl upward continuously,
each one growing from the moment it appears until it sits centred, then
shrinking away. It slows through the middle of a line and sweeps across the
change-over, so the current line is still obvious at a glance. Long lines
crawl slowly, short ones move quickly.

**`handoff`** keeps the current line parked at full size, with a small creep
across the line, and does the growing and shrinking in one sweep just before
the next line starts. Steadier to read; less alive.

## 💡 Good to know

- The bar stays up during a session so you can skip tracks from its media
  widget — the overlay never captures mouse or keyboard. Set `hideBar` if you
  want it gone too.
- Synced lyrics need a player that reports playback position over MPRIS;
  otherwise you get the full lyrics as a static view.
- Tracks without a match show a `No lyrics found` card; the session stays
  open. Misses are retried after a day.
- Windows opened during a session land under the overlay and appear when it
  closes — deliberate.
- Want the audio-reactive **Color Organ** (once it ships)? `pacman -S cava`.
  Without it, lyrics work fine and the reactive layer is silently absent.

## 📦 Requirements & dependencies

Nothing to install on a stock Omarchy box — every required piece is already
there.

| Dependency | Used for | |
|---|---|---|
| Omarchy shell (Quickshell/QML) | hosts the service and the overlay | required |
| Hyprland + `hyprctl` | stashing and restoring windows | required |
| `bash`, `jq`, `curl`, `sed`, `coreutils`, `util-linux` (`flock`) | the scripts in `bin/` | required |
| A player that speaks MPRIS | track identity and playback position | required |
| [`cava`](https://github.com/karlstav/cava) | the audio-reactive Color Organ (not drawn yet) | optional |
| [LRCLIB](https://lrclib.net) | lyric lookup over HTTPS — open, keyless, no account | external service |

The only thing that leaves your machine is the artist / title / album /
duration of the current track, sent to LRCLIB to find its lyrics.

## 🔒 What it touches

Omaraoke writes exactly one thing to your configuration: the settings you
change from its topbar menu, `motion` and `position`, saved inline on its own
bar-layout entry in `~/.config/omarchy/shell.json`. It goes through the same
shell API `omarchy bar set` uses and touches nothing else in that file. The
keybinding and the Omarchy menu row above are yours to add and yours to
remove, and every other setting is *read* from your entry and never written
back. At runtime it creates only its own files:

- `~/.cache/omaraoke/` — the lyric cache.
- `~/.local/state/omaraoke/stash.json` — the window restore map, deleted when
  the session closes.
- `~/.local/state/omarchy/toggles/bar-off` — only if you opt in with
  `hideBar: true`, and it is removed again on close unless you were already
  hiding the bar yourself.

## 🔧 Under the hood

Lyrics come from [LRCLIB](https://lrclib.net) — open, keyless — and are cached
in `~/.cache/omaraoke/`. Windows are stashed to a `special:karaoke` workspace
during a session and restored on exit.

## 🛟 Rescue

If the shell dies mid-session your windows are on `special:karaoke` and a
restore map is in `~/.local/state/omaraoke/stash.json`. The shell restores
them automatically on next start; if it won't start, run:

```sh
~/.config/omarchy/plugins/igoroh.omaraoke/bin/omaraoke-restore
```

It needs only `hyprctl` and `jq`.

## 🗺️ Not done yet

- **Color organ** — an audio-reactive layer driven by `cava` band levels: a
  background wash and a pulse on the current line's scrim. The config key and
  the optional dependency are already in place; nothing is drawn yet.
- **Word-by-word following** — highlighting within the line as it is sung,
  rather than a line at a time. Needs per-word timings, which LRCLIB does not
  carry, so it means local transcription and alignment.
- **Sync improvements and fixes** — position is pulled from MPRIS at ~1 Hz and
  extrapolated between polls, which drifts on some players and after seeks.

## Managing the plugin

Update to pull new commits:

```sh
omarchy plugin update igoroh.omaraoke
```

Uninstall:

```sh
omarchy plugin remove igoroh.omaraoke
```

That takes the plugin away completely. To clean up after it, drop the
keybinding line from `~/.config/hypr/bindings.lua` (and the menu row from
`~/.config/omarchy/extensions/omarchy-menu.jsonc`) if you added them, remove
any `igoroh.omaraoke` entry left under `bar.layout` in
`~/.config/omarchy/shell.json`, and delete
`~/.cache/omaraoke/` and `~/.local/state/omaraoke/`.

## 📄 License

MIT — see [LICENSE](LICENSE). Lyrics are fetched from LRCLIB and belong to
their respective rights holders; Omaraoke ships none.
