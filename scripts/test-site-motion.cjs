// Exercise the production preview lifecycle without a browser or dependencies.
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const vm = require("node:vm");
const assert = require("node:assert/strict");
const { test } = require("node:test");

const source = readFileSync(join(__dirname, "../site/script.js"), "utf8");
const start = source.indexOf("// Brief previews run once in view.");
const end = source.indexOf("const layoutDemo =");
assert.ok(start >= 0 && end > start, "Production preview helper must be present");

class Events {
  listeners = new Map();
  addEventListener(type, listener) {
    if (!this.listeners.has(type)) this.listeners.set(type, new Set());
    this.listeners.get(type).add(listener);
  }
  removeEventListener(type, listener) {
    this.listeners.get(type)?.delete(listener);
  }
  emit(type) {
    for (const listener of [...(this.listeners.get(type) || [])]) listener();
  }
  count() {
    return [...this.listeners.values()].reduce((sum, set) => sum + set.size, 0);
  }
}

function fixture({ hidden = false, reduced = false, fallback = false } = {}) {
  const document = Object.assign(new Events(), { hidden });
  const preference = Object.assign(new Events(), { matches: reduced });
  const window = Object.assign(new Events(), { matchMedia: () => preference });
  let observer;
  let frames = new Map();
  let frameId = 0;
  let rect = { top: 100, bottom: 300, height: 200 };
  const element = { getBoundingClientRect: () => rect };
  const context = vm.createContext({
    window, document, innerHeight: 800,
    requestAnimationFrame(callback) {
      frames.set(++frameId, callback);
      return frameId;
    },
    cancelAnimationFrame(id) { frames.delete(id); },
    IntersectionObserver: fallback ? undefined : class {
      constructor(callback) { this.callback = callback; observer = this; }
      observe() {}
      disconnect() { this.disconnected = true; }
    },
  });
  vm.runInContext(source.slice(start, end) + "\nglobalThis.preview = onceInView;", context);
  const runs = [];
  const cancel = context.preview(element, (finish) => {
    const run = { finish, stops: 0 };
    runs.push(run);
    return () => run.stops++;
  });
  const flush = () => {
    const pending = frames;
    frames = new Map();
    for (const callback of pending.values()) callback();
  };
  return {
    document, window, preference, runs, cancel, flush,
    visible(ratio = 1) {
      if (fallback) {
        rect = ratio ? { top: 100, bottom: 300, height: 200 }
          : { top: 900, bottom: 1100, height: 200 };
        window.emit("scroll");
        flush();
      } else observer.callback([{ intersectionRatio: ratio, isIntersecting: ratio > 0 }]);
    },
    hide(hidden) { document.hidden = hidden; document.emit("visibilitychange"); flush(); },
    motion(reduced) { preference.matches = reduced; preference.emit("change"); flush(); },
    disconnected: () => fallback ? !window.count() : !!observer.disconnected,
  };
}

for (const fallback of [false, true]) {
  const name = fallback ? "scroll fallback" : "IntersectionObserver";
  test(`${name}: a page loaded in the background starts its preview on return`, () => {
    const f = fixture({ hidden: true, fallback });
    f.visible();
    assert.equal(f.runs.length, 0);
    f.hide(false);
    assert.equal(f.runs.length, 1);
  });
  test(`${name}: interrupted previews retry, completed previews stay finished`, () => {
    const f = fixture({ fallback });
    f.visible();
    f.hide(true);
    assert.equal(f.runs[0].stops, 1);
    f.hide(false);
    assert.equal(f.runs.length, 2);
    f.runs[1].finish();
    f.hide(true);
    f.hide(false);
    f.visible(0);
    f.visible();
    assert.equal(f.runs.length, 2);
    assert.ok(f.disconnected());
    assert.equal(f.document.count() + f.preference.count() + f.window.count(), 0);
  });
  test(`${name}: offscreen interruption retries on re-entry`, () => {
    const f = fixture({ fallback });
    f.visible();
    f.visible(0);
    assert.equal(f.runs[0].stops, 1);
    f.visible();
    assert.equal(f.runs.length, 2);
  });
  test(`${name}: reduced motion blocks playback, disabling it retries in view`, () => {
    const f = fixture({ reduced: true, fallback });
    f.visible();
    assert.equal(f.runs.length, 0);
    f.motion(false);
    assert.equal(f.runs.length, 1);
    f.motion(true);
    assert.equal(f.runs[0].stops, 1);
  });
  test(`${name}: manual takeover permanently cancels automatic playback`, () => {
    const f = fixture({ fallback });
    f.visible();
    f.cancel();
    f.hide(true);
    f.hide(false);
    f.visible(0);
    f.visible();
    assert.equal(f.runs.length, 1);
    assert.equal(f.runs[0].stops, 1);
    assert.ok(f.disconnected());
  });
  test(`${name}: blur pauses and focus resumes without needing another scroll`, () => {
    const f = fixture({ fallback });
    f.visible();
    f.window.emit("blur");
    assert.equal(f.runs[0].stops, 1);
    f.window.emit("focus");
    f.flush();
    assert.equal(f.runs.length, 2);
  });
}
