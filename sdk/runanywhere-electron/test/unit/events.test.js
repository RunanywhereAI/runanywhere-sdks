// Unit tests for the EventBus (src/events.ts).
const { test } = require('node:test');
const assert = require('node:assert/strict');

const { EventBus } = require('../../dist/events');

test('on() delivers emitted events and returns an unsubscribe', () => {
  const bus = new EventBus();
  const seen = [];
  const off = bus.on((e) => seen.push(e));
  bus.emit({ type: 'initialized' });
  bus.emit({ type: 'servicesReady' });
  assert.deepEqual(seen, [{ type: 'initialized' }, { type: 'servicesReady' }]);
  assert.equal(typeof off, 'function');
  off();
  bus.emit({ type: 'shutdown' });
  assert.equal(seen.length, 2, 'no delivery after unsubscribe');
});

test('all listeners receive each event', () => {
  const bus = new EventBus();
  let a = 0, b = 0;
  bus.on(() => (a += 1));
  bus.on(() => (b += 1));
  bus.emit({ type: 'initialized' });
  assert.equal(a, 1);
  assert.equal(b, 1);
  assert.equal(bus.listenerCount, 2);
});

test('once() delivers exactly one event then unsubscribes', () => {
  const bus = new EventBus();
  const seen = [];
  bus.once((e) => seen.push(e));
  bus.emit({ type: 'initialized' });
  bus.emit({ type: 'servicesReady' });
  assert.deepEqual(seen, [{ type: 'initialized' }]);
  assert.equal(bus.listenerCount, 0);
});

test('off() removes a specific listener', () => {
  const bus = new EventBus();
  let n = 0;
  const l = () => (n += 1);
  bus.on(l);
  bus.off(l);
  bus.emit({ type: 'initialized' });
  assert.equal(n, 0);
});

test('a throwing listener does not break the others or the emit', () => {
  const bus = new EventBus();
  const seen = [];
  bus.on(() => { throw new Error('bad listener'); });
  bus.on((e) => seen.push(e));
  assert.doesNotThrow(() => bus.emit({ type: 'initialized' }));
  assert.deepEqual(seen, [{ type: 'initialized' }]);
});

test('unsubscribing during emit is safe (snapshot semantics)', () => {
  const bus = new EventBus();
  const seen = [];
  const off = bus.on(() => { off(); }); // removes itself mid-emit
  bus.on((e) => seen.push(e));
  bus.emit({ type: 'initialized' });
  assert.deepEqual(seen, [{ type: 'initialized' }]);
  assert.equal(bus.listenerCount, 1);
});

test('removeAll() clears every listener', () => {
  const bus = new EventBus();
  bus.on(() => {});
  bus.on(() => {});
  assert.equal(bus.listenerCount, 2);
  bus.removeAll();
  assert.equal(bus.listenerCount, 0);
});

test('emit with no listeners is a no-op', () => {
  const bus = new EventBus();
  assert.doesNotThrow(() => bus.emit({ type: 'shutdown' }));
});

test('carries typed payloads (modelLoaded / generation)', () => {
  const bus = new EventBus();
  const seen = [];
  bus.on((e) => seen.push(e));
  bus.emit({ type: 'modelLoaded', modality: 'llm', id: 'qwen2.5-0.5b' });
  bus.emit({ type: 'generation', result: { text: 'hi', tokenCount: 1, timeToFirstTokenMs: 5, tokensPerSecond: 10, totalTimeMs: 100 } });
  assert.equal(seen[0].modality, 'llm');
  assert.equal(seen[0].id, 'qwen2.5-0.5b');
  assert.equal(seen[1].result.tokenCount, 1);
});
