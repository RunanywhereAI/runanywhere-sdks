import assert from 'node:assert/strict';
import test from 'node:test';

import { AsyncQueue, bridgeStream, collect, streamOf } from '../../src/stream.js';

test('bridgeStream is lazy: producer does not run until first next()', async () => {
  let started = false;
  const s = bridgeStream<number>((sink) => {
    started = true;
    sink.push(1);
    sink.end();
  });
  assert.equal(started, false);
  const out = await collect(s);
  assert.equal(started, true);
  assert.deepEqual(out, [1]);
});

test('bridgeStream propagates failure as the next() rejection', async () => {
  const s = bridgeStream<number>((sink) => {
    sink.push(1);
    sink.fail(new Error('boom'));
  });
  const it = s[Symbol.asyncIterator]();
  assert.deepEqual(await it.next(), { value: 1, done: false });
  await assert.rejects(() => it.next(), /boom/);
});

test('breaking the loop calls onCancel', async () => {
  let cancelled = false;
  const s = bridgeStream<number>(
    (sink) => {
      sink.push(1);
      sink.push(2);
    },
    () => {
      cancelled = true;
    }
  );
  for await (const v of s) {
    if (v === 1) break;
  }
  assert.equal(cancelled, true);
});

test('streamOf yields every value then ends', async () => {
  assert.deepEqual(await collect(streamOf(['a', 'b', 'c'])), ['a', 'b', 'c']);
});

test('AsyncQueue buffers pushes made before the consumer reads', async () => {
  const q = new AsyncQueue<number>();
  q.push(1);
  q.push(2);
  q.complete();
  assert.deepEqual(await collect(q), [1, 2]);
});

test('AsyncQueue delivers a late push to a waiting consumer', async () => {
  const q = new AsyncQueue<number>();
  const read = collect(q);
  queueMicrotask(() => {
    q.push(7);
    q.complete();
  });
  assert.deepEqual(await read, [7]);
});
