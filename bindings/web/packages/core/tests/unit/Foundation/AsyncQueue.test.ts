/**
 * AsyncQueue.test.ts
 *
 * `fail()` has to reach the consumer whether or not it is parked. A streaming
 * consumer is parked on `next()` almost all the time (it drains tokens faster
 * than inference produces them), so a failure that only surfaces on a later
 * `next()` is a failure the caller never sees.
 */

import { describe, it, expect } from 'vitest';

import { AsyncQueue } from '../../../src/Foundation/AsyncQueue.js';

describe('AsyncQueue.fail', () => {
  it('rejects a consumer that is already parked on next()', async () => {
    const queue = new AsyncQueue<string>();
    const iterator = queue[Symbol.asyncIterator]();

    // Park first, then fail — the order a mid-stream inference error takes.
    const parked = iterator.next();
    queue.fail(new Error('inference exploded'));

    await expect(parked).rejects.toThrow('inference exploded');
  });

  it('rejects a consumer that arrives after the failure', async () => {
    const queue = new AsyncQueue<string>();
    queue.fail(new Error('inference exploded'));

    const iterator = queue[Symbol.asyncIterator]();
    await expect(iterator.next()).rejects.toThrow('inference exploded');
  });

  it('drains buffered values before reporting the failure', async () => {
    const queue = new AsyncQueue<string>();
    queue.push('a');
    queue.fail(new Error('inference exploded'));

    const iterator = queue[Symbol.asyncIterator]();
    await expect(iterator.next()).resolves.toEqual({ value: 'a', done: false });
    await expect(iterator.next()).rejects.toThrow('inference exploded');
  });

  it('still ends normally on complete()', async () => {
    const queue = new AsyncQueue<string>();
    const iterator = queue[Symbol.asyncIterator]();

    const parked = iterator.next();
    queue.complete();

    await expect(parked).resolves.toEqual({ value: undefined, done: true });
  });
});
