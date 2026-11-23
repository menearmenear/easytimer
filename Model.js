.pragma library

// Pure timer logic for EasyTimer. No Qt, no I/O: every function takes plain
// values and returns plain values, so the math can be tested with any JS
// runtime. The QML surface owns persistence, notifications and sound.

var STATUSES = ["idle", "running", "paused", "done"]
var FORMATS = ["countdown", "countdown-label", "percent", "label", "icon"]
var TIME_FORMATS = ["auto", "always", "never"]

var LIMITS = {
  minutes: { min: 1, max: 1440 },
  soundVolume: { min: 0, max: 100 }
}

var BOOL_KEYS = ["sound", "notifications", "showIcon", "showLabel"]
var STRING_KEYS = ["glyph", "glyphPaused", "label", "color", "doneColor"]

function defaultSettings() {
  return {
    minutes: 25,
    sound: true,
    soundVolume: 70,
    notifications: true,
    showIcon: true,
    glyph: "󰔟",
    glyphPaused: "󰏤",
    showLabel: false,
    label: "TIMER",
    barFormat: "countdown",
    timeFormat: "auto",
    color: "",
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
    var max = stringKey.indexOf("glyph") === 0 ? 8 : 24
    out[stringKey] = String(raw[stringKey]).slice(0, max)
  }
  out.color = normalizeColor(raw.color)
  out.doneColor = normalizeColor(raw.doneColor)
  if (FORMATS.indexOf(String(raw.barFormat)) >= 0) out.barFormat = String(raw.barFormat)
  if (TIME_FORMATS.indexOf(String(raw.timeFormat)) >= 0) out.timeFormat = String(raw.timeFormat)
  return out
}

// ---- State ----------------------------------------------------------------

function durationMs(settings) {
  return settings.minutes * 60 * 1000
}

function initialState(settings) {
  var total = durationMs(settings)
  return {
    status: "idle",
    endAt: 0,
    remainingMs: total,
    durationMs: total,
    updatedAt: 0
  }
}

// Tolerates state files written by older, mode-based versions of EasyTimer:
// phase/rounds fields are simply ignored, the timing fields are reused.
function parseState(text, settings) {
  var fallback = initialState(settings)
  if (!text) return fallback
  try {
    var raw = JSON.parse(text)
    if (!raw || typeof raw !== "object") return fallback
    var rawStatus = String(raw.status || "")
    var status = STATUSES.indexOf(rawStatus) >= 0 ? rawStatus : "idle"
    if (rawStatus === "ready") status = "done"
    var total = Math.max(0, Number(raw.durationMs) || 0)
    if (total <= 0) total = durationMs(settings)
    var state = {
      status: status,
      endAt: Number(raw.endAt) || 0,
      remainingMs: Math.max(0, Number(raw.remainingMs) || 0),
      durationMs: total,
      updatedAt: Number(raw.updatedAt) || 0
    }
    if (state.status === "running" && state.endAt <= 0) state.status = "idle"
    if (state.status === "idle") state.remainingMs = state.durationMs
    if (state.status === "done") state.remainingMs = 0
    return state
  } catch (e) {
    return fallback
  }
}

function serializeState(state, now) {
  return JSON.stringify({
    status: state.status,
    endAt: state.endAt,
    remainingMs: state.remainingMs,
    durationMs: state.durationMs,
    updatedAt: now
  }, null, 2) + "\n"
}

function remainingMs(state, settings, now) {
  if (state.status === "running") return Math.max(0, state.endAt - now)
  if (state.status === "idle") return state.durationMs
  if (state.status === "done") return 0
  return Math.max(0, state.remainingMs)
}

function isExpired(state, now) {
  return state.status === "running" && state.endAt <= now
}

function progress(state, settings, now) {
  var total = state.durationMs > 0 ? state.durationMs : durationMs(settings)
  if (total <= 0) return 0
  return Math.max(0, Math.min(1, 1 - remainingMs(state, settings, now) / total))
}

function clone(state) {
  return {
    status: state.status,
    endAt: state.endAt,
    remainingMs: state.remainingMs,
    durationMs: state.durationMs,
    updatedAt: state.updatedAt
  }
}

// ---- Transitions ----------------------------------------------------------

function start(state, settings, now) {
  var next = clone(state)
  if (next.status === "running") return next
  var remaining = remainingMs(next, settings, now)
  if (remaining <= 0) remaining = durationMs(settings)
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

function finish(state, settings) {
  var next = clone(state)
  next.status = "done"
  next.endAt = 0
  next.remainingMs = 0
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

function glyph(state, settings) {
  return state.status === "paused" ? settings.glyphPaused : settings.glyph
}

function barText(state, settings, now) {
  var icon = settings.showIcon ? glyph(state, settings) + " " : ""
  if (settings.barFormat === "icon") return glyph(state, settings)
  if (settings.barFormat === "label") return icon + settings.label
  if (settings.barFormat === "percent")
    return icon + Math.round((1 - progress(state, settings, now)) * 100) + "%"
  var time = formatTime(remainingMs(state, settings, now), settings.timeFormat)
  if (settings.barFormat === "countdown-label") return icon + settings.label + " " + time
  return icon + time
}
