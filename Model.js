.pragma library

// Pure timer logic for EasyTimer. No Qt, no I/O: every function takes plain
// values and returns plain values, so the math can be tested with any JS
// runtime. The QML surface owns persistence, notifications and sound.

var PHASES = ["focus", "break", "long"]
var STATUSES = ["idle", "running", "paused", "ready"]
var FORMATS = ["countdown", "countdown-label", "percent", "label", "icon"]
var TIME_FORMATS = ["auto", "always", "never"]

var LIMITS = {
  focusMinutes: { min: 1, max: 180 },
  breakMinutes: { min: 1, max: 60 },
  longBreakMinutes: { min: 1, max: 120 },
  roundsBeforeLongBreak: { min: 2, max: 12 },
  soundVolume: { min: 0, max: 100 }
}

var BOOL_KEYS = [
  "autoStartBreaks", "autoStartFocus", "sound", "notifications", "showIcon", "showLabel"
]

var STRING_KEYS = [
  "iconFocus", "iconBreak", "iconPaused", "label", "labelOnBreak",
  "focusColor", "breakColor", "doneColor"
]

function defaultSettings() {
  return {
    focusMinutes: 25,
    breakMinutes: 5,
    longBreakMinutes: 15,
    roundsBeforeLongBreak: 4,
    autoStartBreaks: true,
    autoStartFocus: false,
    sound: true,
    soundVolume: 70,
    notifications: true,
    showIcon: true,
    iconFocus: "󰔟",
    iconBreak: "󰅶",
    iconPaused: "󰏤",
    showLabel: false,
    label: "TIMER",
    labelOnBreak: "BREAK",
    barFormat: "countdown",
    timeFormat: "auto",
    focusColor: "",
    breakColor: "",
    doneColor: ""
  }
}

function clampSetting(key, value) {
  var limit = LIMITS[key]
  if (!limit) return value
  var n = parseInt(value, 10)
  if (isNaN(n)) n = defaultSettings()[key]
  return Math.max(limit.min, Math.min(limit.max, n))
}

function validColor(value) {
  return /^#(?:[0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(String(value || ""))
}

function normalizeColor(value) {
  return validColor(value) ? String(value) : ""
}

function normalizeSettings(raw) {
  var out = defaultSettings()
  if (!raw || typeof raw !== "object") return out

  var key
  for (key in LIMITS) {
    if (raw[key] !== undefined && raw[key] !== null) out[key] = clampSetting(key, raw[key])
  }
  for (var b = 0; b < BOOL_KEYS.length; b++) {
    var boolKey = BOOL_KEYS[b]
    if (raw[boolKey] !== undefined && raw[boolKey] !== null)
      out[boolKey] = raw[boolKey] === true || raw[boolKey] === "true"
  }
  for (var s = 0; s < STRING_KEYS.length; s++) {
    var stringKey = STRING_KEYS[s]
    if (raw[stringKey] === undefined || raw[stringKey] === null) continue
    var max = (stringKey.indexOf("icon") === 0) ? 8 : 24
    out[stringKey] = String(raw[stringKey]).slice(0, max)
  }
  out.focusColor = normalizeColor(raw.focusColor)
  out.breakColor = normalizeColor(raw.breakColor)
  out.doneColor = normalizeColor(raw.doneColor)
  if (FORMATS.indexOf(String(raw.barFormat)) >= 0) out.barFormat = String(raw.barFormat)
  if (TIME_FORMATS.indexOf(String(raw.timeFormat)) >= 0) out.timeFormat = String(raw.timeFormat)
  return out
}

// ---- Durations and state --------------------------------------------------

function phaseDurationMs(settings, phase) {
  var minutes
  if (phase === "break") minutes = settings.breakMinutes
  else if (phase === "long") minutes = settings.longBreakMinutes
  else minutes = settings.focusMinutes
  return minutes * 60 * 1000
}

function phaseMinutes(settings, phase) {
  return Math.round(phaseDurationMs(settings, phase) / 60000)
}

function initialState(settings) {
  var duration = phaseDurationMs(settings, "focus")
  return {
    phase: "focus",
    status: "idle",
    endAt: 0,
    remainingMs: duration,
    durationMs: duration,
    roundsDone: 0,
    updatedAt: 0
  }
}

function parseState(text, settings) {
  var fallback = initialState(settings)
  if (!text) return fallback
  try {
    var raw = JSON.parse(text)
    if (!raw || typeof raw !== "object") return fallback
    var state = {
      phase: PHASES.indexOf(raw.phase) >= 0 ? raw.phase : "focus",
      status: STATUSES.indexOf(raw.status) >= 0 ? raw.status : "idle",
      endAt: Number(raw.endAt) || 0,
      remainingMs: Math.max(0, Number(raw.remainingMs) || 0),
      durationMs: Math.max(0, Number(raw.durationMs) || 0),
      roundsDone: Math.max(0, parseInt(raw.roundsDone, 10) || 0),
      updatedAt: Number(raw.updatedAt) || 0
    }
    if (state.status === "running" && state.endAt <= 0) state.status = "idle"
    if (state.durationMs <= 0) state.durationMs = phaseDurationMs(settings, state.phase)
    if ((state.status === "idle" || state.status === "ready") && state.remainingMs <= 0)
      state.remainingMs = state.durationMs
    return state
  } catch (e) {
    return fallback
  }
}

function serializeState(state, now) {
  return JSON.stringify({
    phase: state.phase,
    status: state.status,
    endAt: state.endAt,
    remainingMs: state.remainingMs,
    durationMs: state.durationMs,
    roundsDone: state.roundsDone,
    updatedAt: now
  }, null, 2) + "\n"
}

function remainingMs(state, settings, now) {
  if (state.status === "running") return Math.max(0, state.endAt - now)
  if (state.status === "idle" || state.status === "ready") return state.durationMs
  return Math.max(0, state.remainingMs)
}

function isExpired(state, now) {
  return state.status === "running" && state.endAt <= now
}

function progress(state, settings, now) {
  var total = state.durationMs > 0 ? state.durationMs : phaseDurationMs(settings, state.phase)
  if (total <= 0) return 0
  return Math.max(0, Math.min(1, 1 - remainingMs(state, settings, now) / total))
}

function clone(state) {
  return {
    phase: state.phase,
    status: state.status,
    endAt: state.endAt,
    remainingMs: state.remainingMs,
    durationMs: state.durationMs,
    roundsDone: state.roundsDone,
    updatedAt: state.updatedAt
  }
}

// ---- Transitions ----------------------------------------------------------

function start(state, settings, now) {
  var next = clone(state)
  if (next.status === "running") return next
  var remaining = remainingMs(next, settings, now)
  if (remaining <= 0) remaining = phaseDurationMs(settings, next.phase)
  next.status = "running"
  next.endAt = now + remaining
  next.remainingMs = remaining
  next.durationMs = remaining
  return next
}

function pause(state, now) {
  var next = clone(state)
  if (next.status !== "running") return next
  next.remainingMs = Math.max(0, next.endAt - now)
  next.status = "paused"
  next.endAt = 0
  return next
}

function togglePause(state, settings, now) {
  return state.status === "running" ? pause(state, now) : start(state, settings, now)
}

function reset(state, settings) {
  return initialState(settings)
}

// Move to the phase after the current one. A focus round counts toward the
// long break; finishing a long break starts a fresh cycle.
function advance(state, settings) {
  var next = clone(state)
  var rounds = next.roundsDone
  var phase
  if (next.phase === "focus") {
    rounds += 1
    phase = rounds >= settings.roundsBeforeLongBreak ? "long" : "break"
  } else {
    if (next.phase === "long") rounds = 0
    phase = "focus"
  }
  next.phase = phase
  next.roundsDone = rounds
  next.status = "idle"
  next.endAt = 0
  next.remainingMs = phaseDurationMs(settings, phase)
  next.durationMs = next.remainingMs
  return next
}

function wantsAutoStart(state, settings) {
  return state.phase === "focus" ? settings.autoStartFocus : settings.autoStartBreaks
}

function finish(state, settings, now) {
  var next = advance(state, settings)
  if (wantsAutoStart(next, settings)) return start(next, settings, now)
  next.status = "ready"
  return next
}

function skip(state, settings, now) {
  var elapsedRatio = 1 - remainingMs(state, settings, now) / phaseDurationMs(settings, state.phase)
  var next
  if (state.phase === "focus" && elapsedRatio < 0.1) {
    // Abandoned almost immediately: switch to a break but do not count it.
    next = clone(state)
    next.phase = state.roundsDone + 1 >= settings.roundsBeforeLongBreak ? "long" : "break"
    next.status = "idle"
    next.endAt = 0
    next.remainingMs = phaseDurationMs(settings, next.phase)
    next.durationMs = next.remainingMs
  } else {
    next = advance(state, settings)
  }
  if (state.status === "running") return start(next, settings, now)
  if (wantsAutoStart(next, settings)) return start(next, settings, now)
  next.status = "ready"
  return next
}

// ---- Presentation ---------------------------------------------------------

function pad(n) {
  return n < 10 ? "0" + n : String(n)
}

function formatTime(ms, timeFormat) {
  var total = Math.ceil(Math.max(0, ms) / 1000)
  var h = Math.floor(total / 3600)
  var m = Math.floor((total % 3600) / 60)
  var s = total % 60
  var showHours = timeFormat === "always" || (timeFormat === "auto" && h > 0)
  return (showHours ? h + ":" : "") + pad(m) + ":" + pad(s)
}

function phaseKey(phase) {
  if (phase === "break") return "break"
  if (phase === "long") return "longBreak"
  return "focus"
}

function labelFor(state, settings) {
  return state.phase === "focus" ? settings.label : settings.labelOnBreak
}

function glyph(state, settings) {
  if (state.status === "paused") return settings.iconPaused
  if (state.phase !== "focus") return settings.iconBreak
  return settings.iconFocus
}

function barText(state, settings, now) {
  var icon = settings.showIcon ? glyph(state, settings) + " " : ""
  if (settings.barFormat === "icon") return glyph(state, settings)
  var label = labelFor(state, settings)
  if (settings.barFormat === "label") return icon + label
  if (settings.barFormat === "percent")
    return icon + Math.round((1 - progress(state, settings, now)) * 100) + "%"
  var time = formatTime(remainingMs(state, settings, now), settings.timeFormat)
  if (settings.barFormat === "countdown-label") return icon + label + " " + time
  return icon + time
}

function roundsDots(state, settings) {
  var dots = []
  for (var i = 0; i < settings.roundsBeforeLongBreak; i++) {
    dots.push({
      done: i < state.roundsDone,
      current: i === state.roundsDone && state.phase === "focus" && state.status !== "idle"
    })
  }
  return dots
}

// Data for the end-of-phase notification; the QML layer fills in translated
// strings from the plugin's i18n catalog.
function notification(previousPhase, nextState, settings) {
  return {
    kind: previousPhase === "focus" ? "focusDone" : "breakDone",
    nextPhase: phaseKey(nextState.phase),
    minutes: phaseMinutes(settings, nextState.phase),
    auto: wantsAutoStart(nextState, settings),
    glyph: glyph(nextState, settings)
  }
}
