// Unit tests for the RPC protocol constants shared between the renderer/main and
// the utility host.
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { STREAMING_METHODS } from '../../dist/process/rpc';
import { BACKEND_STREAMING_METHODS, rpcMethodFor } from '../../dist/api/backend';

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

test('the streaming set is the three pre-v3 methods plus every v3 streaming op', () => {
  const expected = new Set([
    'generate',
    'generateVlm',
    'downloadModel',
    ...[...BACKEND_STREAMING_METHODS].map(rpcMethodFor),
  ]);
  assert.deepEqual(new Set(STREAMING_METHODS), expected);
});
