'use strict';
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { runInNewContext } = require('node:vm');
const { test } = require('node:test');

// Exercise the actual QML JavaScript handlers without requiring a desktop.
const panel = readFileSync(join(__dirname, '..', 'Panel.qml'), 'utf8');
function handler(name) {
  const start = panel.indexOf(`  function ${name}(`);
  assert.notEqual(start, -1, `Missing ${name} handler`);
  const body = panel.indexOf('{', start);
  let depth = 1;
  let end = body + 1;
  while (depth && end < panel.length) {
    if (panel[end] === '{') depth++;
    if (panel[end] === '}') depth--;
    end++;
  }
  assert.equal(depth, 0, `Unclosed ${name} handler`);
  return panel.slice(start, end);
}
function context(bar) {
  const root = {
    bar, settingsOpen: true, advancedOpen: true, opened: true,
    controller: { hide() { root.opened = false; } },
  };
  const ctx = { root };
  runInNewContext(`'use strict';\n${handler('setCenterHoverRevealSuppressed')}\n${handler('close')}`, ctx);
  return ctx;
}

test('close reaches controller.hide with the read-only third-party bar API', () => {
  let suppressed = true;
  const bar = {
    get centerHoverRevealSuppressed() { return suppressed; },
    setCenterHoverRevealSuppressed(value) { suppressed = value; },
  };
  const ctx = context(bar);
  ctx.close();
  assert.equal(suppressed, false);
  assert.equal(ctx.root.opened, false);
  assert.equal(ctx.root.settingsOpen, false);
  assert.equal(ctx.root.advancedOpen, false);
});

test('suppression can be enabled using the third-party setter', () => {
  let suppressed = false;
  const ctx = context({
    get centerHoverRevealSuppressed() { return suppressed; },
    setCenterHoverRevealSuppressed(value) { suppressed = value; },
  });
  ctx.setCenterHoverRevealSuppressed(true);
  assert.equal(suppressed, true);
});

test('close still supports the legacy writable bar property', () => {
  const bar = { centerHoverRevealSuppressed: true };
  const ctx = context(bar);
  ctx.close();
  assert.equal(bar.centerHoverRevealSuppressed, false);
  assert.equal(ctx.root.opened, false);
});

test('close works without a bar', () => {
  const ctx = context(null);
  ctx.close();
  assert.equal(ctx.root.opened, false);
});
