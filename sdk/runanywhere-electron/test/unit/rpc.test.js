// Unit tests for the RPC protocol constants shared between the renderer/main and
// the utility host.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const { STREAMING_METHODS } = require('../../dist/process/rpc');

test('STREAMING_METHODS is a Set', () => {
  assert.ok(STREAMING_METHODS instanceof Set);
});

test('the streaming methods are the callback-per-event methods', () => {
  assert.ok(STREAMING_METHODS.has('generate'), 'generate streams tokens');
  assert.ok(STREAMING_METHODS.has('generateVlm'), 'generateVlm streams tokens');
  assert.ok(STREAMING_METHODS.has('downloadModel'), 'downloadModel streams progress');
});

test('unary methods are NOT marked streaming', () => {
  for (const m of ['embed', 'transcribe', 'synthesize', 'loadModel', 'version', 'initialize', 'shutdown']) {
    assert.ok(!STREAMING_METHODS.has(m), `${m} should not be a streaming method`);
  }
});

test('the streaming set has exactly three members', () => {
  assert.equal(STREAMING_METHODS.size, 3);
});
