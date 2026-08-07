import assert from 'node:assert/strict';
import test from 'node:test';

import { NativeBackend } from '../../src/native/backend.js';
import type { NativeAddon, ProtoBytes, ProtoSink } from '../../src/native/addon-api.js';

interface Call {
  name: string;
  args: unknown[];
}

function fakeAddon(overrides: Partial<NativeAddon> = {}): { addon: NativeAddon; calls: Call[] } {
  const calls: Call[] = [];
  const record =
    (name: string, ret: unknown = new Uint8Array()) =>
    (...args: unknown[]) => {
      calls.push({ name, args });
      return ret;
    };
  const base = {
    version: 'test-1.0',
    hasControlPlane: true,
    ragCreateSession: async () => 42,
    ragIngest: record('ragIngest', new Uint8Array([1])),
    ragDestroySession: record('ragDestroySession'),
    sttStreamStart: () => {
      calls.push({ name: 'sttStreamStart', args: [] });
      return 7;
    },
    sttStreamFeed: record('sttStreamFeed'),
    sttStreamSubscribe: async () => undefined,
    llmGenerate: async (r: ProtoBytes) => {
      calls.push({ name: 'llmGenerate', args: [r] });
      return new Uint8Array([9, 9]);
    },
    shutdown: record('shutdown'),
  } as unknown as NativeAddon;
  return { addon: Object.assign(base, overrides), calls };
}

test('ragOpen maps an integer handle to a string id, and closes it', async () => {
  const { addon, calls } = fakeAddon();
  const be = new NativeBackend(addon);
  const id = await be.ragOpen(new Uint8Array());
  assert.equal(id, 'rag_1');
  await be.ragIngest(id, new Uint8Array([5]));
  assert.deepEqual(calls.find((c) => c.name === 'ragIngest')?.args, [42, new Uint8Array([5])]);
  await be.ragClose(id);
  assert.ok(calls.some((c) => c.name === 'ragDestroySession' && c.args[0] === 42));
});

test('a closed RAG session is rejected with invalid-state', async () => {
  const { addon } = fakeAddon();
  const be = new NativeBackend(addon);
  const id = await be.ragOpen(new Uint8Array());
  await be.ragClose(id);
  await assert.rejects(() => be.ragIngest(id, new Uint8Array()), /RAG session rag_1 is closed/);
});

test('STT stream: start maps a handle, feed forwards it, events unmap on end', async () => {
  const { addon, calls } = fakeAddon();
  const be = new NativeBackend(addon);
  const id = await be.sttStreamStart(new Uint8Array());
  assert.equal(id, 'stt_1');
  await be.sttStreamFeed(id, new Uint8Array([3]));
  assert.deepEqual(calls.find((c) => c.name === 'sttStreamFeed')?.args, [7, new Uint8Array([3])]);
  const noop: ProtoSink = () => {};
  await be.sttStreamEvents(id, noop);
  await assert.rejects(() => be.sttStreamFeed(id, new Uint8Array()), /STT stream stt_1 is closed/);
});

test('inference calls pass proto bytes straight through', async () => {
  const { addon } = fakeAddon();
  const be = new NativeBackend(addon);
  const out = await be.llmGenerate(new Uint8Array([1, 2, 3]));
  assert.deepEqual(out, new Uint8Array([9, 9]));
});

test('shutdown clears the session maps', async () => {
  const { addon } = fakeAddon();
  const be = new NativeBackend(addon);
  const id = await be.ragOpen(new Uint8Array());
  await be.shutdown();
  await assert.rejects(() => be.ragStats(id), /is closed/);
});
