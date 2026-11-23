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
  remainingMs, start, pause, togglePause, finish, reset, isExpired,
  formatTime, barText, glyph, durationMs
});`)(model);

const settings = (patch = {}) => model.normalizeSettings(patch);

test("settings are normalized and clamped to 24 hours", () => {
  const s = settings({ minutes: 2000, soundVolume: -5, barFormat: "bogus", color: "red" });
  assert.equal(s.minutes, 1440);
  assert.equal(s.soundVolume, 0);
  assert.equal(s.barFormat, "countdown");
  assert.equal(s.color, "");
  assert.equal(settings({ minutes: 999 }).minutes, 999);
  assert.equal(settings({ color: "#a6adc8" }).color, "#a6adc8");
  assert.equal(model.durationMs(settings({ minutes: 1440 })), 86400000);
});

test("start, pause and resume keep the remaining time", () => {
  const s = settings({ minutes: 1 });
  const started = model.start(model.initialState(s), s, 1000);
  assert.equal(started.status, "running");
  assert.equal(started.endAt, 61000);
  const paused = model.pause(started, 11000);
  assert.equal(paused.status, "paused");
  assert.equal(model.remainingMs(paused, s, 99999), 50000);
  const resumed = model.start(paused, s, 120000);
  assert.equal(resumed.endAt, 170000);
});

test("expiry marks the timer done and start restarts it", () => {
  const s = settings({ minutes: 1 });
  const started = model.start(model.initialState(s), s, 0);
  assert.equal(model.isExpired(started, 60001), true);
  const done = model.finish(started, s);
  assert.equal(done.status, "done");
  assert.equal(model.remainingMs(done, s, 60001), 0);
  const again = model.start(done, s, 60001);
  assert.equal(again.status, "running");
  assert.equal(model.remainingMs(again, s, 60001), 60000);
});

test("old mode-based state files are still readable", () => {
  const s = settings({ minutes: 25 });
  const old = JSON.stringify({
    phase: "focus", status: "ready", endAt: 0,
    remainingMs: 1500000, durationMs: 1500000, roundsDone: 2
  });
  const state = model.parseState(old, s);
  assert.equal(state.status, "done");
  assert.equal(state.remainingMs, 0);
  assert.equal(state.durationMs, 1500000);
});

test("time formatting and bar formats", () => {
  const base = settings({ glyph: "T", label: "TIMER" });
  assert.equal(model.formatTime(61000, "auto"), "01:01");
  assert.equal(model.formatTime(3661000, "auto"), "1:01:01");
  assert.equal(model.formatTime(3661000, "never"), "01:01");
  const state = model.initialState(base);
  assert.equal(model.barText(state, settings({ barFormat: "countdown", showIcon: false }), 0), "25:00");
  assert.equal(model.barText(state, settings({ barFormat: "countdown-label", showIcon: false }), 0), "TIMER 25:00");
  assert.equal(model.barText(state, settings({ barFormat: "percent", showIcon: false }), 0), "100%");
  assert.equal(model.barText(state, settings({ barFormat: "icon", glyph: "T" }), 0), "T");
  assert.equal(model.glyph(model.pause(model.start(state, base, 0), 1), settings({ glyphPaused: "P" })), "P");
});

test("state survives serialization", () => {
  const s = settings({ minutes: 30 });
  const state = model.start(model.initialState(s), s, 12345);
  const restored = model.parseState(model.serializeState(state, 12345), s);
  assert.deepEqual(restored, { ...state, updatedAt: 12345 });
});
