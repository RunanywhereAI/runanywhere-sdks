// Unit tests for streamWithMetrics — token AsyncIterable -> LLMStreamEvent stream
// with time-to-first-token / tokens-per-second metrics (src/stream.ts).
const { test } = require('node:test');
const assert = require('node:assert/strict');

const { streamWithMetrics } = require('../../dist/stream');

async function* fromArray(items) {
  for (const it of items) yield it;
}
// A deterministic clock that returns successive values from `vals`.
function clock(vals) {
  let i = 0;
  return () => vals[i++];
}
async function collect(iter) {
  const out = [];
  for await (const e of iter) out.push(e);
  return out;
}

test('emits one non-final event per token, then a final event with a result', async () => {
  // now() is called: start, first-token, end  -> 3 values for a 2-token source.
  const events = await collect(streamWithMetrics(fromArray(['a', 'bc']), clock([0, 10, 30])));
  assert.equal(events.length, 3);
  assert.deepEqual(events[0], { token: 'a', isFinal: false });
  assert.deepEqual(events[1], { token: 'bc', isFinal: false });
  assert.equal(events[2].isFinal, true);
  assert.equal(events[2].token, '');
});

test('the final result carries text, token count and timing metrics', async () => {
  const events = await collect(streamWithMetrics(fromArray(['a', 'bc']), clock([0, 10, 30])));
  assert.deepEqual(events[2].result, {
    text: 'abc',
    tokenCount: 2,
    timeToFirstTokenMs: 10, // first token at t=10, start at t=0
    tokensPerSecond: 100, // 2 tokens over (30-10)=20ms => 2 / 0.02s
    totalTimeMs: 30,
  });
});

test('an empty stream yields only a final event with zeroed metrics', async () => {
  // now() called: start, end -> 2 values (no token).
  const events = await collect(streamWithMetrics(fromArray([]), clock([5, 25])));
  assert.equal(events.length, 1);
  assert.equal(events[0].isFinal, true);
  assert.deepEqual(events[0].result, {
    text: '',
    tokenCount: 0,
    timeToFirstTokenMs: 0,
    tokensPerSecond: 0,
    totalTimeMs: 20,
  });
});

test('a single-token stream reports one token and a valid rate', async () => {
  const events = await collect(streamWithMetrics(fromArray(['hi']), clock([0, 5, 15])));
  assert.equal(events.length, 2);
  assert.equal(events[0].token, 'hi');
  const r = events[1].result;
  assert.equal(r.tokenCount, 1);
  assert.equal(r.text, 'hi');
  assert.equal(r.timeToFirstTokenMs, 5);
  assert.equal(r.tokensPerSecond, 100); // 1 token / (15-5)=10ms
});

test('defaults to a real clock when none is injected (metrics are finite)', async () => {
  const events = await collect(streamWithMetrics(fromArray(['x'])));
  const r = events[events.length - 1].result;
  assert.equal(r.tokenCount, 1);
  assert.ok(Number.isFinite(r.tokensPerSecond));
  assert.ok(r.totalTimeMs >= 0);
});
