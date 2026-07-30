const { test } = require('node:test');
const assert = require('node:assert/strict');

const { splitThinking, stripThinking, stripAllThinking, isThinking } = require('../../dist/thinking');

test('splitThinking: <think> block is separated from the answer', () => {
  const { response, thinking } = splitThinking('<think>let me count</think>The answer is 4.');
  assert.equal(thinking, 'let me count');
  assert.equal(response, 'The answer is 4.');
});

test('splitThinking: <thinking> alias works and content is trimmed', () => {
  const { response, thinking } = splitThinking('<thinking>\n  weighing options\n</thinking>\n\nParis.');
  assert.equal(thinking, 'weighing options');
  assert.equal(response, 'Paris.');
});

test('splitThinking: text with no thinking passes through as the response', () => {
  const { response, thinking } = splitThinking('Just a plain answer.');
  assert.equal(response, 'Just a plain answer.');
  assert.equal(thinking, '');
});

test('splitThinking: an unclosed <think> makes the rest thinking', () => {
  const { response, thinking } = splitThinking('Sure.<think>still reasoning and never closed');
  assert.equal(response, 'Sure.');
  assert.equal(thinking, 'still reasoning and never closed');
});

test('splitThinking: text before and after the block is joined with a newline (commons parity)', () => {
  const { response } = splitThinking('A<think>x</think>B');
  assert.equal(response, 'A\nB');
});

test('splitThinking: empty / nullish input is safe', () => {
  assert.deepEqual(splitThinking(''), { response: '', thinking: '' });
  assert.deepEqual(splitThinking(undefined), { response: '', thinking: '' });
});

test('splitThinking handles adversarial repetitive input without backtracking (ReDoS)', () => {
  // Would blow up a lazy-match + backreference regex; the indexOf scan is O(n).
  const s = '<think>' + '<think>a'.repeat(100000);
  const start = Date.now();
  const { thinking } = splitThinking(s);
  assert.ok(Date.now() - start < 1000, 'must not backtrack');
  assert.ok(thinking.startsWith('<think>a'), 'unclosed block is treated as thinking');
});

test('stripThinking returns only the answer', () => {
  assert.equal(stripThinking('<think>hmm</think>Done.'), 'Done.');
  assert.equal(stripThinking('No tags here.'), 'No tags here.');
});

test('isThinking is true mid-stream (open, not yet closed) and false once closed', () => {
  assert.equal(isThinking('<think>reasoning so far'), true);
  assert.equal(isThinking('<think>reasoning</think>answer'), false);
  assert.equal(isThinking('plain streaming text'), false);
});

test('stripAllThinking removes every block, not just the first', () => {
  assert.equal(
    stripAllThinking('<think>a</think>One<thinking>b</thinking>Two<think>c</think>'),
    'OneTwo'
  );
});

test('stripAllThinking drops an unterminated trailing block', () => {
  assert.equal(stripAllThinking('Answer<think>still going'), 'Answer');
  assert.equal(stripAllThinking('<think>only thinking'), '');
});

test('stripAllThinking leaves text with no reasoning untouched', () => {
  assert.equal(stripAllThinking('just an answer'), 'just an answer');
  assert.equal(stripAllThinking(''), '');
});

test('stripAllThinking is linear on adversarial input (no ReDoS)', () => {
  // CodeQL js/polynomial-redos: a regex with a backreference backtracks
  // polynomially on many repeated '<think>' openers. Model output is untrusted.
  const evil = '<think>'.repeat(60000);
  const started = process.hrtime.bigint();
  stripAllThinking(evil);
  const ms = Number(process.hrtime.bigint() - started) / 1e6;
  assert.ok(ms < 2000, `stripAllThinking took ${ms.toFixed(0)}ms on 60k repeats`);
});

test('stripAllThinking is linear on many COMPLETE blocks, not just unterminated ones', () => {
  // The earlier perf test only used unterminated openers, which exit after one
  // scan — so it passed while the real loop was quadratic (2.9s at n=32000).
  // Repeated closed blocks are the case that actually exercises the loop.
  const time = (n) => {
    const s = '<think>x</think>'.repeat(n);
    const started = process.hrtime.bigint();
    const out = stripAllThinking(s);
    assert.equal(out, '');
    return Number(process.hrtime.bigint() - started) / 1e6;
  };
  time(4000); // warm up, so JIT compilation is not charged to the first sample
  const small = Math.max(time(8000), 0.5);
  const large = time(32000);

  // Linear would be ~4x for 4x the input; quadratic ~16x. Allow generous slack
  // for a noisy CI box but still fail decisively on a quadratic regression.
  assert.ok(large / small < 8, `4x the input cost ${(large / small).toFixed(1)}x the time (${small.toFixed(1)}ms -> ${large.toFixed(1)}ms) — looks quadratic`);
  assert.ok(large < 500, `32k blocks took ${large.toFixed(0)}ms`);
});

test('a tag-like prefix that is not a real tag is left alone', () => {
  // nextOpen scans for the shared '<think' prefix, so it must reject near-misses.
  assert.equal(stripAllThinking('a <thinker> b'), 'a <thinker> b');
  assert.equal(stripAllThinking('<thinkers>x</thinkers>'), '<thinkers>x</thinkers>');
  assert.equal(stripAllThinking('<think>t</think>a <thinker> b'), 'a <thinker> b');
});
