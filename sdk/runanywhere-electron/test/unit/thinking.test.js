const { test } = require('node:test');
const assert = require('node:assert/strict');

const { splitThinking, stripThinking, isThinking } = require('../../dist/thinking');

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

test('splitThinking: text before and after the block is stitched into the response', () => {
  const { response } = splitThinking('A<think>x</think>B');
  assert.equal(response, 'AB');
});

test('splitThinking: empty / nullish input is safe', () => {
  assert.deepEqual(splitThinking(''), { response: '', thinking: '' });
  assert.deepEqual(splitThinking(undefined), { response: '', thinking: '' });
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
