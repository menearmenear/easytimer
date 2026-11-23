# EasyTimer

A fully customizable countdown / focus timer widget for the [Omarchy](https://omarchy.org/) shell (Quickshell bar). It shows a live countdown in the top bar and opens a mouse- and keyboard-driven panel with start, pause, reset, skip and a full settings editor.

## Features

- Countdown in the bar: time, label + time, percent, label only, or icon only
- Focus / short break / long break cycle with a configurable number of rounds
- Editable durations (1–180 min focus, 1–60 min short break, 1–120 min long break)
- Configurable glyphs, labels and colors — blank colors follow the live theme
- Auto-start breaks and/or focus rounds
- Desktop notification and chime on phase end, with adjustable chime volume
- Persists across shell restarts and shares one clock across all monitors
- IPC for keybindings, menus and scripts
- All panel strings ship as a flat JSON catalog (`i18n/en.json`) and follow the shell's selected language

## Install

```bash
omarchy plugin add https://github.com/menearmenear/easytimer.git --enable
omarchy bar move menearmenear.easytimer --section centerEnd --index 0
```

The widget id is `menearmenear.easytimer`. `defaultSection` is `centerEnd`, which is the right-hand side of the bar's center cluster (beside the clock). Move it with `omarchy bar move` if you prefer another spot.

Update with `omarchy plugin update menearmenear.easytimer`; remove with `omarchy plugin remove menearmenear.easytimer`.

## Controls

| Where | Input | Action |
|---|---|---|
| Bar widget | left click | open / close the panel |
| Bar widget | right click | start / pause |
| Bar widget | middle click | reset |
| Bar widget | scroll | change the current phase's length by ±1 min |
| Panel | `p` / `Space` / `Enter` | start / pause |
| Panel | `r` | reset |
| Panel | `s` | skip to the next phase |
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
```

## Settings

Settings live in the widget's entry in `~/.config/omarchy/shell.json` and are written through `updateEntryInline` when you use the panel. You can also edit them directly:

```bash
omarchy bar set menearmenear.easytimer focusMinutes 30
omarchy bar set menearmenear.easytimer barFormat countdown-label
omarchy bar get menearmenear.easytimer focusMinutes
```

| Key | Default | Meaning |
|---|---|---|
| `focusMinutes` | 25 | Focus length, 1–180 |
| `breakMinutes` | 5 | Short break length, 1–60 |
| `longBreakMinutes` | 15 | Long break length, 1–120 |
| `roundsBeforeLongBreak` | 4 | Focus rounds before a long break, 2–12 |
| `autoStartBreaks` | true | Start breaks automatically |
| `autoStartFocus` | false | Start the next focus round automatically |
| `sound` | true | Chime when a phase ends |
| `soundVolume` | 70 | Chime volume, 0–100 |
| `notifications` | true | Desktop notification when a phase ends |
| `showIcon` | true | Show a glyph in the bar |
| `iconFocus` / `iconBreak` / `iconPaused` | `󰔟` / `󰅶` / `󰏤` | Nerd Font glyphs per state |
| `showLabel` | false | Show a custom word next to the timer |
| `label` / `labelOnBreak` | `TIMER` / `BREAK` | Custom words |
| `barFormat` | `countdown` | `countdown`, `countdown-label`, `percent`, `label`, `icon` |
| `timeFormat` | `auto` | `auto`, `always`, `never` (show hours) |
| `focusColor` / `breakColor` / `doneColor` | `""` | Hex overrides, blank follows the theme |

## IPC

```bash
omarchy-shell menearmenear.easytimer open|close|toggle
omarchy-shell menearmenear.easytimer start|pause|startPause|reset|skip
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
