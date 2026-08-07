import assert from 'node:assert/strict';
import test from 'node:test';

import { rpcMethodFor } from '../../src/backend.js';
import { ALLOWED_RPC_METHODS, dispatch, ToolExecBridge } from '../../src/rpc/dispatch.js';
import type { BackendMap } from '../../src/rpc/dispatch.js';

// Collects posted messages; dispatch posts asynchronously, so tests await a tick.
function makePort() {
  const posted: unknown[] = [];
  return { posted, postMessage: (m: unknown) => posted.push(m) };
}
const tick = () => new Promise((r) => setImmediate(r));

test('rejects a method not on the allowlist', async () => {
  const port = makePort();
  dispatch(port, { id: 1, method: 'v3.nope', args: [] }, { backend: {} as BackendMap });
  await tick();
  assert.deepEqual(port.posted, [{ id: 1, ok: false, error: "unknown RPC method: 'v3.nope'" }]);
});

test('unary op forwards args and posts the result', async () => {
  const port = makePort();
  const backend = {
    llmGenerate: async (b: Uint8Array) => new Uint8Array([b[0] + 1]),
  } as unknown as BackendMap;
  dispatch(port, { id: 2, method: rpcMethodFor('llmGenerate'), args: [new Uint8Array([9])] }, { backend });
  await tick();
  assert.deepEqual(port.posted, [{ id: 2, ok: true, result: new Uint8Array([10]) }]);
});

test('streaming op posts chunks then done', async () => {
  const port = makePort();
  const backend = {
    llmGenerateStream: async (_b: Uint8Array, sink: (c: Uint8Array) => void) => {
      sink(new Uint8Array([1]));
      sink(new Uint8Array([2]));
    },
  } as unknown as BackendMap;
  dispatch(port, { id: 3, method: rpcMethodFor('llmGenerateStream'), args: [new Uint8Array()] }, { backend });
  await tick();
  assert.deepEqual(port.posted, [
    { id: 3, chunk: new Uint8Array([1]) },
    { id: 3, chunk: new Uint8Array([2]) },
    { id: 3, done: true },
  ]);
});

test('a rejected op posts a structured error', async () => {
  const port = makePort();
  const backend = {
    llmGenerate: async () => {
      throw Object.assign(new Error('boom'), { code: 130, cAbiCode: -130 });
    },
  } as unknown as BackendMap;
  dispatch(port, { id: 4, method: rpcMethodFor('llmGenerate'), args: [new Uint8Array()] }, { backend });
  await tick();
  assert.equal((port.posted[0] as { ok: boolean }).ok, false);
  const err = (port.posted[0] as { error: { message: string; code: number } }).error;
  assert.equal(err.message, 'boom');
  assert.equal(err.code, 130);
});

test('toolRunLoop round-trips the executor through the bridge', async () => {
  const port = makePort();
  const toolBridge = new ToolExecBridge(port);
  const backend = {
    // commons drives the loop; ask the renderer to run one tool, then finish.
    toolRunLoop: async (req: Uint8Array, onExecute: (b: Uint8Array) => Promise<Uint8Array>) => {
      const toolResult = await onExecute(new Uint8Array([req[0]]));
      return new Uint8Array([toolResult[0] + 100]);
    },
  } as unknown as BackendMap;
  dispatch(
    port,
    { id: 7, method: rpcMethodFor('toolRunLoop'), args: [new Uint8Array([5])] },
    { backend, toolBridge }
  );
  await tick();
  const exec = port.posted[0] as { id: number; toolExec: Uint8Array; execId: number };
  assert.equal(exec.id, 7);
  assert.deepEqual(exec.toolExec, new Uint8Array([5]));

  // The renderer runs the tool and replies; the loop then completes.
  toolBridge.resolveReply({ id: 7, execId: exec.execId, toolResult: new Uint8Array([9]) });
  await tick();
  assert.deepEqual(port.posted[1], { id: 7, ok: true, result: new Uint8Array([109]) });
});

test('a tool-calling loop that ends fails any executor still waiting', async () => {
  const port = makePort();
  const toolBridge = new ToolExecBridge(port);
  const backend = {
    toolRunLoop: async () => new Uint8Array([1]),
  } as unknown as BackendMap;
  // An executor left pending, then cleared, must reject rather than hang.
  const pending = Promise.resolve(toolBridge.executorFor(42)(new Uint8Array([0])));
  toolBridge.clear(42);
  await assert.rejects(pending, /tool-calling loop ended/);
  void backend;
});

test('the allowlist is exactly the v3 backend operations', () => {
  assert.ok(ALLOWED_RPC_METHODS.has(rpcMethodFor('llmGenerate')));
  assert.ok(ALLOWED_RPC_METHODS.has(rpcMethodFor('ragOpen')));
  assert.ok(!ALLOWED_RPC_METHODS.has('llmGenerate')); // must be v3.-namespaced
});
