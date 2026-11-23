# EasyTimer

A simple, fully customizable countdown timer widget for the [Omarchy](https://omarchy.org/) shell (Quickshell bar). Set a length, start it, pause it, reset it. No modes, no phases, no rounds.

The bar shows a live countdown (or percent / label / icon). Click the widget for a panel with Start/Pause, Reset, ±1 minute buttons and a settings editor.

## Features

- One duration, editable from 1 minute to 24 hours (1440 min)
- Quick ±1 minute buttons in the panel; scroll on the bar widget also changes the length
- Bar display: countdown, label + time, percent, label only, or icon only
- Custom glyph, label and hex colors (blank colors follow the live theme)
- End chime with volume, desktop notification toggle
- Persists across shell restarts and shares one clock across all monitors
- IPC for keybindings, menus and scripts
- All panel strings ship as a flat JSON catalog (`i18n/en.json`) and follow the shell's selected language

## Install

```bash
omarchy plugin add https://github.com/menearmenear/easytimer.git --enable
omarchy bar move menearmenear.easytimer --section centerEnd --index 0
```

The widget id is `menearmenear.easytimer`. It lands in `centerEnd` — the right-hand side of the bar's center cluster, beside the clock.

Update with `omarchy plugin update menearmenear.easytimer`; remove with `omarchy plugin remove menearmenear.easytimer`.

Version 2 dropped focus/break modes and rounds. Old state files are read without issue; old `shell.json` keys that no longer exist are ignored.

## Controls

| Where | Input | Action |
|---|---|---|
| Bar widget | left click | open / close the panel |
| Bar widget | right click | start / pause |
| Bar widget | middle click | reset |
| Bar widget | scroll | change the timer length by ±1 min |
| Panel | `p` / `Space` / `Enter` | start / pause |
| Panel | `r` | reset |
| Panel | `,` or `.` | toggle settings |
| Panel | `Esc` | close |
| Anywhere | see keybinding below | toggle the panel |

Optional keybinding in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + T", "EasyTimer", "omarchy-shell menearmenear.easytimer toggle")
```

Optional Omarchy menu trigger in `~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"trigger.easytimer": {"icon":"󰔟","label":"EasyTimer","aliases":["timer","easytimer"]},
"trigger.easytimer.open": {"icon":"󰔟","label":"Open panel","action":"omarchy-shell menearmenear.easytimer open"},
"trigger.easytimer.startpause": {"icon":"󰐊","label":"Start / Pause","action":"omarchy-shell menearmenear.easytimer startPause"},
"trigger.easytimer.reset": {"icon":"󰜉","label":"Reset","action":"omarchy-shell menearmenear.easytimer reset"},
"trigger.easytimer.10min": {"icon":"󰔟","label":"Set 10 minutes","action":"omarchy-shell menearmenear.easytimer minutes 10"}
```

## Settings

Settings live in the widget's entry in `~/.config/omarchy/shell.json` and are written through `updateEntryInline` when you use the panel. You can also edit them directly:

```bash
omarchy bar set menearmenear.easytimer minutes 90
omarchy bar set menearmenear.easytimer barFormat countdown-label
omarchy bar get menearmenear.easytimer minutes
```

| Key | Default | Meaning |
|---|---|---|
| `minutes` | 25 | Timer length, 1–1440 (24 h) |
| `sound` | true | Chime when the timer ends |
| `soundVolume` | 70 | Chime volume, 0–100 |
| `notifications` | true | Desktop notification when the timer ends |
| `showIcon` | true | Show a glyph in the bar |
| `glyph` / `glyphPaused` | `󰔟` / `󰏤` | Nerd Font glyphs |
| `showLabel` | false | Show a custom word next to the timer |
| `label` | `TIMER` | Custom word |
| `barFormat` | `countdown` | `countdown`, `countdown-label`, `percent`, `label`, `icon` |
| `timeFormat` | `auto` | `auto`, `always`, `never` (show hours) |
| `color` / `doneColor` | `""` | Hex overrides, blank follows the theme |

Changing the length resets the timer to the new duration.

## IPC

```bash
omarchy-shell menearmenear.easytimer open|close|toggle
omarchy-shell menearmenear.easytimer start|pause|startPause|reset
omarchy-shell menearmenear.easytimer minutes 10
omarchy-shell menearmenear.easytimer settingsToggle
omarchy-shell menearmenear.easytimer status   # state + settings as JSON
```

## Files

| File | Purpose |
|---|---|
| `manifest.json` | Plugin manifest, defaults and settings schema |
| `Panel.qml` | Bar button, popup, IPC, state file, notification and chime |
| `Model.js` | Pure timer logic (no Qt): state transitions and formatting |
| `i18n/en.json` | Flat translation catalog |
| `tests/model.test.mjs` | Node tests for the pure logic |

State lives in `~/.local/state/omarchy/easytimer.json`.

## Development

```bash
node --test tests/model.test.mjs
omarchy plugin validate .
omarchy restart shell   # after changing QML
```

Shell log: `qs log /run/user/$(id -u)/quickshell/by-pid/<pid>/log.qslog -t 200`.

## License

MIT — see [LICENSE](LICENSE).
