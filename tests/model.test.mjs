import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

// Model.js is a QML .pragma library, so strip that line before evaluating it
// in plain Node.
const source = readFileSync(new URL("../Model.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*/, "");
const model = {};
new Function("exports", `${source}\nObject.assign(exports, {
  defaultSettings, normalizeSettings, clampSetting, initialState, parseState, serializeState,
  remainingMs, start, pause, togglePause, finish, advance, skip, isExpired,
  formatTime, barText, glyph, roundsDots, notification, phaseDurationMs
});`)(model);

const settings = (patch = {}) => model.normalizeSettings(patch);

test("settings are normalized and clamped", () => {
  const s = settings({ focusMinutes: 999, breakMinutes: 0, soundVolume: -5, barFormat: "bogus", focusColor: "red" });
  assert.equal(s.focusMinutes, 180);
  assert.equal(s.breakMinutes, 1);
  assert.equal(s.soundVolume, 0);
  assert.equal(s.barFormat, "countdown");
  assert.equal(s.focusColor, "");
  assert.equal(settings({ focusColor: "#a6adc8" }).focusColor, "#a6adc8");
});

test("start, pause and resume keep the remaining time", () => {
  const s = settings({ focusMinutes: 1 });
  const started = model.start(model.initialState(s), s, 1000);
  assert.equal(started.status, "running");
  assert.equal(started.endAt, 61000);
  const paused = model.pause(started, 11000);
  assert.equal(paused.status, "paused");
  assert.equal(model.remainingMs(paused, s, 99999), 50000);
  const resumed = model.start(paused, s, 120000);
  assert.equal(resumed.endAt, 170000);
});

test("expiry advances focus to a short break", () => {
  const s = settings({ focusMinutes: 1, breakMinutes: 2, autoStartBreaks: false });
  const started = model.start(model.initialState(s), s, 0);
  assert.equal(model.isExpired(started, 60001), true);
  const next = model.finish(started, s, 60001);
  assert.equal(next.phase, "break");
  assert.equal(next.status, "ready");
  assert.equal(next.roundsDone, 1);
  assert.equal(model.remainingMs(next, s, 60001), 120000);
});

test("long break arrives after the configured number of rounds", () => {
  const s = settings({ roundsBeforeLongBreak: 3, autoStartBreaks: true, autoStartFocus: true });
  let state = model.initialState(s);
  for (let i = 0; i < 3; i++) {
    state = model.start(state, s, 0);
    state = model.finish(state, s, state.endAt); // focus -> break / long
    if (state.phase === "break") {
      state = model.start(state, s, 0);
      state = model.finish(state, s, state.endAt); // break -> focus
    }
  }
  assert.equal(state.phase, "long");
  assert.equal(state.roundsDone, 3);
  state = model.start(state, s, 0);
  state = model.finish(state, s, state.endAt);
  assert.equal(state.phase, "focus");
  assert.equal(state.roundsDone, 0);
});

test("skipping a fresh focus round does not count it", () => {
  const s = settings({ focusMinutes: 25, autoStartBreaks: false });
  const started = model.start(model.initialState(s), s, 0);
  const skipped = model.skip(started, s, 1000);
  assert.equal(skipped.roundsDone, 0);
  assert.equal(skipped.phase, "break");
});

test("time formatting and bar formats", () => {
  const s = settings({ showIcon: true, iconFocus: "T", label: "TIMER" });
  const state = model.initialState(s);
  assert.equal(model.formatTime(61000, "auto"), "01:01");
  assert.equal(model.formatTime(3661000, "auto"), "1:01:01");
  assert.equal(model.formatTime(3661000, "never"), "01:01");
  assert.equal(model.barText(state, settings({ barFormat: "countdown", showIcon: false }), 0), "25:00");
  assert.equal(model.barText(state, settings({ barFormat: "countdown-label", showIcon: false }), 0), "TIMER 25:00");
  assert.equal(model.barText(state, settings({ barFormat: "percent", showIcon: false }), 0), "100%");
  assert.equal(model.barText(state, settings({ barFormat: "icon", iconFocus: "T" }), 0), "T");
});

test("state survives serialization and rounds dots are bounded", () => {
  const s = settings({ roundsBeforeLongBreak: 4 });
  const state = model.start(model.initialState(s), s, 12345);
  const restored = model.parseState(model.serializeState(state, 12345), s);
  assert.deepEqual(restored, { ...state, updatedAt: 12345 });
  assert.equal(model.roundsDots(state, s).length, 4);
  assert.equal(model.notification("focus", model.finish(state, s, state.endAt), s).kind, "focusDone");
});
