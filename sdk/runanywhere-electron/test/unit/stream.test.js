const { test } = require('node:test');
const assert = require('node:assert/strict');

const { toAsyncIterable } = require('../../dist/stream');

// Helpers ------------------------------------------------------------------

// Schedule a macrotask tick so tokens can arrive AFTER the consumer is already
// awaiting inside next().
function tick() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function collect(iter) {
  const out = [];
  for await (const t of iter) out.push(t);
  return out;
}

// -------------------------------------------------------------------------

test('in-order delivery: pushes a,b,c then resolves', async () => {
  const iter = toAsyncIterable(async (onToken) => {
    onToken('a');
    onToken('b');
    onToken('c');
  });
  const got = await collect(iter);
  assert.deepEqual(got, ['a', 'b', 'c']);
});

test('buffering before consumption: synchronous pushes are all received in order', async () => {
  // start pushes several tokens synchronously and resolves on a later tick.
  const iter = toAsyncIterable((onToken) => {
    onToken('one');
    onToken('two');
    onToken('three');
    onToken('four');
    return tick();
  });
  const got = await collect(iter);
  assert.deepEqual(got, ['one', 'two', 'three', 'four']);
});

test('async/slow producer: tokens arrive after consumer is already waiting', async () => {
  const iter = toAsyncIterable(async (onToken) => {
    await tick();
    onToken('x');
    await tick();
    onToken('y');
    await tick();
    onToken('z');
    await tick();
  });
  const got = await collect(iter);
  assert.deepEqual(got, ['x', 'y', 'z']);
});

test('empty stream: resolves without pushing -> yields nothing', async () => {
  const iter = toAsyncIterable(async () => {
    // resolve on a later microtask, no tokens
    await Promise.resolve();
  });
  const got = await collect(iter);
  assert.deepEqual(got, []);
});

test('empty stream: next() returns { value: undefined, done: true }', async () => {
  const iter = toAsyncIterable(async () => {
    await tick();
  });
  const res = await iter.next();
  assert.deepEqual(res, { value: undefined, done: true });
});

test('rejection: buffered tokens delivered before the throw', async () => {
  const iter = toAsyncIterable((onToken) => {
    onToken('a');
    onToken('b');
    return Promise.reject(new Error('boom'));
  });

  // a and b are drained from the queue before err is examined.
  const r1 = await iter.next();
  assert.deepEqual(r1, { value: 'a', done: false });
  const r2 = await iter.next();
  assert.deepEqual(r2, { value: 'b', done: false });

  // then the next iteration throws with message 'boom'.
  await assert.rejects(() => iter.next(), (e) => {
    assert.ok(e instanceof Error);
    assert.equal(e.message, 'boom');
    return true;
  });
});

test('rejection: for-await collects buffered tokens then throws boom', async () => {
  const iter = toAsyncIterable(async (onToken) => {
    await tick();
    onToken('a');
    onToken('b');
    throw new Error('boom');
  });

  const got = [];
  await assert.rejects(async () => {
    for await (const t of iter) got.push(t);
  }, (e) => {
    assert.ok(e instanceof Error);
    assert.equal(e.message, 'boom');
    return true;
  });
  assert.deepEqual(got, ['a', 'b']);
});

test('immediate rejection with no tokens -> throws', async () => {
  const iter = toAsyncIterable(() => Promise.reject(new Error('nope')));
  await assert.rejects(() => iter.next(), (e) => {
    assert.equal(e.message, 'nope');
    return true;
  });
});

test('rejection can carry a non-Error value', async () => {
  const iter = toAsyncIterable(() => Promise.reject('string-error'));
  await assert.rejects(
    () => iter.next(),
    (thrown) => {
      assert.equal(thrown, 'string-error');
      return true;
    }
  );
});

test('rejection while consumer is already waiting in next()', async () => {
  const iter = toAsyncIterable(async (onToken) => {
    await tick();
    onToken('a');
    await tick();
    throw new Error('late-boom');
  });

  const first = await iter.next();
  assert.deepEqual(first, { value: 'a', done: false });

  await assert.rejects(() => iter.next(), (e) => {
    assert.equal(e.message, 'late-boom');
    return true;
  });
});

test('[Symbol.asyncIterator]() returns the iterator itself (self)', () => {
  const iter = toAsyncIterable(async () => {});
  const self = iter[Symbol.asyncIterator]();
  assert.equal(self, iter);
});

test('calling next() after normal completion returns { done: true }', async () => {
  const iter = toAsyncIterable(async (onToken) => {
    onToken('only');
  });

  const r1 = await iter.next();
  assert.deepEqual(r1, { value: 'only', done: false });

  const r2 = await iter.next();
  assert.deepEqual(r2, { value: undefined, done: true });

  // repeated next() calls after completion keep returning done: true
  const r3 = await iter.next();
  assert.deepEqual(r3, { value: undefined, done: true });
});

test('single token then resolve, delivered before done', async () => {
  const iter = toAsyncIterable(async (onToken) => {
    await tick();
    onToken('solo');
  });
  const got = await collect(iter);
  assert.deepEqual(got, ['solo']);
});

test('interleaved async pushes preserve arrival order', async () => {
  const iter = toAsyncIterable(async (onToken) => {
    onToken('1'); // buffered before first next() likely runs
    await tick();
    onToken('2');
    onToken('3'); // two in one tick
    await tick();
    onToken('4');
  });
  const got = await collect(iter);
  assert.deepEqual(got, ['1', '2', '3', '4']);
});

test('empty-string tokens are yielded (not skipped)', async () => {
  const iter = toAsyncIterable(async (onToken) => {
    onToken('');
    onToken('a');
    onToken('');
  });
  const got = await collect(iter);
  assert.deepEqual(got, ['', 'a', '']);
});

test('after rejection, further next() calls keep throwing the same error', async () => {
  // err is checked every loop and never cleared, so once a stream errors it
  // stays errored for subsequent next() calls too.
  const iter = toAsyncIterable(() => Promise.reject(new Error('sticky')));

  await assert.rejects(() => iter.next(), (e) => {
    assert.equal(e.message, 'sticky');
    return true;
  });
  await assert.rejects(() => iter.next(), (e) => {
    assert.equal(e.message, 'sticky');
    return true;
  });
});

test('queue is drained BEFORE the error even after err+done are already set', async () => {
  // next() checks queue.length before err, so a token that is buffered while the
  // stream also rejects must still be yielded before the throw is observed.
  const iter = toAsyncIterable((onToken) => {
    onToken('a');
    return Promise.reject(new Error('boom'));
  });

  // Let the .then rejection handler run so err AND done are set before we pull.
  await tick();

  const r1 = await iter.next();
  assert.deepEqual(r1, { value: 'a', done: false });

  await assert.rejects(() => iter.next(), (e) => {
    assert.equal(e.message, 'boom');
    return true;
  });
});

test('token pushed AFTER the promise resolves (done already true) is still yielded', async () => {
  // The onToken callback pushes unconditionally; since queue is checked before
  // done, a late token still surfaces before the iterator reports completion.
  let cb;
  const iter = toAsyncIterable((onToken) => {
    cb = onToken;
    return Promise.resolve();
  });

  // Let the completion handler run: done is now true.
  await tick();

  cb('late');

  const r1 = await iter.next();
  assert.deepEqual(r1, { value: 'late', done: false });

  const r2 = await iter.next();
  assert.deepEqual(r2, { value: undefined, done: true });
});

test('tokens pass through with no coercion (non-string values preserved by identity)', async () => {
  // The adapter never validates or converts tokens; whatever is passed to
  // onToken is what the consumer receives (same reference for objects).
  const obj = { k: 1 };
  const iter = toAsyncIterable((onToken) => {
    onToken(5);
    onToken(null);
    onToken(obj);
    return Promise.resolve();
  });
  const got = await collect(iter);
  assert.equal(got.length, 3);
  assert.equal(got[0], 5);
  assert.equal(got[1], null);
  assert.equal(got[2], obj); // same reference, not a copy
});

test('start is invoked exactly once, synchronously, during construction', () => {
  let calls = 0;
  let sawCallback = false;
  const iter = toAsyncIterable((onToken) => {
    calls += 1;
    sawCallback = typeof onToken === 'function';
    return Promise.resolve();
  });
  // start() must have already run by the time toAsyncIterable returns.
  assert.equal(calls, 1);
  assert.equal(sawCallback, true);
  assert.equal(typeof iter.next, 'function');
});

test('a start() that throws synchronously propagates out of toAsyncIterable', () => {
  // start is called directly (not wrapped in try/catch), so a synchronous throw
  // escapes the factory itself rather than surfacing via next().
  assert.throws(
    () => toAsyncIterable(() => {
      throw new Error('sync-throw');
    }),
    (e) => {
      assert.ok(e instanceof Error);
      assert.equal(e.message, 'sync-throw');
      return true;
    }
  );
});

test('separate calls produce independent iterators with no shared state', async () => {
  const a = toAsyncIterable((onToken) => {
    onToken('A1');
    onToken('A2');
    return tick();
  });
  const b = toAsyncIterable((onToken) => {
    onToken('B1');
    return tick();
  });

  // Interleave consumption to prove queues/done flags are not shared.
  const a1 = await a.next();
  const b1 = await b.next();
  assert.deepEqual(a1, { value: 'A1', done: false });
  assert.deepEqual(b1, { value: 'B1', done: false });

  const restA = await collect(a);
  const restB = await collect(b);
  assert.deepEqual(restA, ['A2']);
  assert.deepEqual(restB, []);
});

test('a resolved but never-consumed stream does not throw (no unhandled rejection)', async () => {
  // Constructing without draining should be safe for a resolving stream.
  toAsyncIterable(async (onToken) => {
    onToken('ignored');
  });
  // Give the completion promise a chance to settle; absence of a crash is the
  // assertion. If an unhandled rejection were produced, the test process fails.
  await tick();
  assert.ok(true);
});
