import assert from 'node:assert/strict';
import test from 'node:test';

import {
  BACKEND_METHODS,
  BACKEND_STREAMING_METHODS,
  rpcMethodFor,
  type RaBackend,
} from '../../src/backend.js';

// Compile-time exhaustiveness: every RaBackend method must appear in
// BACKEND_METHODS. If one is missing, `Missing` is that method's name and this
// assignment fails to compile with the name in the error. (The reverse — no
// stray entries — is enforced by the `satisfies` clause in backend.ts.)
type Missing = Exclude<keyof RaBackend, (typeof BACKEND_METHODS)[number]>;
const _noMissingMethods: [Missing] extends [never] ? true : Missing = true;
void _noMissingMethods;

test('BACKEND_METHODS has no duplicates', () => {
  assert.equal(new Set(BACKEND_METHODS).size, BACKEND_METHODS.length);
});

test('every streaming method is a known backend method', () => {
  for (const m of BACKEND_STREAMING_METHODS) {
    assert.ok((BACKEND_METHODS as readonly string[]).includes(m), `${m} not in BACKEND_METHODS`);
  }
});

test('rpcMethodFor namespaces under v3.', () => {
  assert.equal(rpcMethodFor('llmGenerate'), 'v3.llmGenerate');
  assert.equal(rpcMethodFor('version'), 'v3.version');
});
