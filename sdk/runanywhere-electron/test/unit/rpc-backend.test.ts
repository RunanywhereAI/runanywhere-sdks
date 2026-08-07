import assert from 'node:assert/strict';
import test from 'node:test';

import { RpcBackend, type RpcSend } from '../../src/rpc/backend.js';

interface Sent {
  method: string;
  args: unknown[];
  onChunk?: (c: unknown) => void;
}

function fakeSend(ret: unknown = new Uint8Array()): { send: RpcSend; sent: Sent[] } {
  const sent: Sent[] = [];
  const send: RpcSend = async (method, args, onChunk) => {
    sent.push({ method, args, onChunk });
    return ret;
  };
  return { send, sent };
}

test('unary op forwards under a v3. name and returns the reply', async () => {
  const { send, sent } = fakeSend(new Uint8Array([7]));
  const be = new RpcBackend(send);
  const out = await be.llmGenerate(new Uint8Array([1]));
  assert.equal(sent[0].method, 'v3.llmGenerate');
  assert.deepEqual(sent[0].args, [new Uint8Array([1])]);
  assert.deepEqual(out, new Uint8Array([7]));
});

test('streaming op passes the sink as the chunk callback', async () => {
  const { send, sent } = fakeSend();
  const be = new RpcBackend(send);
  const sink = () => {};
  await be.llmGenerateStream(new Uint8Array([2]), sink);
  assert.equal(sent[0].method, 'v3.llmGenerateStream');
  assert.equal(sent[0].onChunk, sink);
});

test('session ops forward the session id and payload', async () => {
  const { send, sent } = fakeSend();
  const be = new RpcBackend(send);
  await be.ragIngest('rag_3', new Uint8Array([4]));
  assert.equal(sent[0].method, 'v3.ragIngest');
  assert.deepEqual(sent[0].args, ['rag_3', new Uint8Array([4])]);
});

test('scalar ops round-trip their value', async () => {
  const { send } = fakeSend('test-1.0');
  const be = new RpcBackend(send);
  assert.equal(await be.version(), 'test-1.0');
});
