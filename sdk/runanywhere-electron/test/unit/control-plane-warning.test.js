// Unit tests for the `initialize({ apiKey, baseUrl })` runtime warning
// (src/control-plane-warning.ts) — PR #605 review issue 11. Split out of
// `RunAnywhere.ts` so this test does not need a built native addon.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const { warnIfControlPlaneOptionsIgnored } = require('../../dist/control-plane-warning');

function captureWarnings(fn) {
  const calls = [];
  const original = console.warn;
  console.warn = (...args) => calls.push(args);
  try {
    fn();
  } finally {
    console.warn = original;
  }
  return calls;
}

test('warns when apiKey is passed', () => {
  const calls = captureWarnings(() => warnIfControlPlaneOptionsIgnored({ apiKey: 'sk-test' }));
  assert.equal(calls.length, 1);
  assert.match(calls[0][0], /apiKey\/baseUrl are accepted/);
  assert.match(calls[0][0], /no control-plane client/);
});

test('warns when baseUrl is passed', () => {
  const calls = captureWarnings(() =>
    warnIfControlPlaneOptionsIgnored({ baseUrl: 'https://example.com' })
  );
  assert.equal(calls.length, 1);
});

test('warns once when both apiKey and baseUrl are passed', () => {
  const calls = captureWarnings(() =>
    warnIfControlPlaneOptionsIgnored({ apiKey: 'sk-test', baseUrl: 'https://example.com' })
  );
  assert.equal(calls.length, 1);
});

test('does not warn when neither apiKey nor baseUrl is passed', () => {
  const calls = captureWarnings(() => warnIfControlPlaneOptionsIgnored({}));
  assert.equal(calls.length, 0);
});
