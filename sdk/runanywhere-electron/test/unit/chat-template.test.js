// Chat-template formatting. This is the difference between a model that
// remembers the conversation and one that greets you on every turn: llama.cpp
// wraps an UNRECOGNISED prompt as a single user message, collapsing the whole
// transcript into one turn.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const { formatChat, hasTurnMarkup } = require('../../dist/chat-template');

const CONVO = [
  { role: 'system', content: 'You are concise.' },
  { role: 'user', content: 'Hi' },
  { role: 'assistant', content: 'Hello! How can I help?' },
  { role: 'user', content: 'My name is Aman' },
  { role: 'assistant', content: 'Nice to meet you, Aman.' },
  { role: 'user', content: 'whats my name ??' },
];

// --- ChatML (Qwen, LFM2.5, Phi) ---------------------------------------------

test('chatml renders every turn separately and opens the assistant turn', () => {
  const p = formatChat(CONVO, 'chatml');
  // 1 system + 3 user + 2 assistant = 6 rendered turns, plus the opening
  // assistant marker the model completes from.
  assert.equal((p.match(/<\|im_start\|>/g) || []).length, 7);
  assert.match(p, /<\|im_start\|>system\nYou are concise\.<\|im_end\|>/);
  assert.match(p, /<\|im_start\|>user\nMy name is Aman<\|im_end\|>/);
  assert.match(p, /<\|im_start\|>assistant\nHello! How can I help\?<\|im_end\|>/);
  assert.ok(p.endsWith('<|im_start|>assistant\n'), 'must end ready for the reply');
});

test('the earlier turns SURVIVE — this is the bug that looked like memory loss', () => {
  const p = formatChat(CONVO, 'chatml');
  assert.match(p, /My name is Aman/, 'the name the user gave must be in the prompt');
  assert.match(p, /whats my name \?\?/);
  // The old hand-rolled format put everything in one blob; assert we are not
  // emitting that shape any more.
  assert.doesNotMatch(p, /^You are concise\.\n\nUser: /);
});

test('chatml is what llama.cpp passes through verbatim', () => {
  assert.equal(hasTurnMarkup(formatChat(CONVO, 'chatml')), true);
});

// --- Llama 3 -----------------------------------------------------------------

test('llama3 uses header ids and eot markers', () => {
  const p = formatChat(CONVO, 'llama3');
  assert.ok(p.startsWith('<|begin_of_text|>'));
  assert.match(p, /<\|start_header_id\|>system<\|end_header_id\|>\n\nYou are concise\.<\|eot_id\|>/);
  assert.match(p, /<\|start_header_id\|>user<\|end_header_id\|>\n\nMy name is Aman<\|eot_id\|>/);
  assert.ok(p.endsWith('<|start_header_id|>assistant<|end_header_id|>\n\n'));
  assert.equal(hasTurnMarkup(p), true);
});

// --- Gemma -------------------------------------------------------------------

test('gemma uses turn markers, maps assistant->model, and folds system into the first user turn', () => {
  const p = formatChat(CONVO, 'gemma');
  assert.match(p, /<start_of_turn>user\nYou are concise\.\n\nHi<end_of_turn>/, 'no system role in Gemma');
  assert.match(p, /<start_of_turn>model\nHello! How can I help\?<end_of_turn>/);
  assert.ok(p.endsWith('<start_of_turn>model\n'));
  assert.doesNotMatch(p, /<start_of_turn>(system|assistant)\b/);
});

test('gemma folds the system prompt exactly once', () => {
  const p = formatChat(CONVO, 'gemma');
  assert.equal((p.match(/You are concise\./g) || []).length, 1);
});

// --- Mistral -----------------------------------------------------------------

test('mistral wraps user turns in [INST] and closes assistant turns', () => {
  const p = formatChat(CONVO, 'mistral');
  assert.match(p, /\[INST\] You are concise\.\n\nHi \[\/INST\]/);
  assert.match(p, /\[INST\] My name is Aman \[\/INST\]/);
  assert.match(p, /Hello! How can I help\?<\/s>/);
  assert.equal(hasTurnMarkup(p), true);
});

// --- reasoning + hygiene -----------------------------------------------------

test('stale <think> blocks are stripped from replayed assistant turns', () => {
  const p = formatChat([
    { role: 'user', content: 'Hi' },
    { role: 'assistant', content: '<think>\nlong deliberation\n</think>\n\nHello!' },
    { role: 'user', content: 'again' },
  ], 'chatml');
  assert.doesNotMatch(p, /<think>/, 'reasoning must not be replayed as context');
  assert.doesNotMatch(p, /long deliberation/);
  assert.match(p, /<\|im_start\|>assistant\nHello!<\|im_end\|>/);
});

test('an unterminated <think> is also stripped', () => {
  const p = formatChat([
    { role: 'user', content: 'Hi' },
    { role: 'assistant', content: 'Sure.<think>still thinking' },
  ], 'chatml');
  assert.doesNotMatch(p, /still thinking/);
  assert.match(p, /Sure\./);
});

test('empty turns are dropped so a blank streaming placeholder cannot poison the prompt', () => {
  const p = formatChat([
    { role: 'user', content: 'Hi' },
    { role: 'assistant', content: '   ' },
    { role: 'user', content: 'there' },
  ], 'chatml');
  assert.equal((p.match(/<\|im_start\|>/g) || []).length, 3, 'two user turns + the open assistant turn');
});

test('no system turn is fine for every template', () => {
  const turns = [{ role: 'user', content: 'Hi' }];
  for (const t of ['chatml', 'llama3', 'gemma', 'mistral']) {
    const p = formatChat(turns, t);
    assert.match(p, /Hi/, `${t} must include the user text`);
  }
});

test('an empty conversation still produces a valid opening for the assistant', () => {
  assert.equal(formatChat([], 'chatml'), '<|im_start|>assistant\n');
  assert.ok(formatChat([], 'gemma').endsWith('<start_of_turn>model\n'));
});

test('the default template is chatml', () => {
  assert.equal(formatChat(CONVO), formatChat(CONVO, 'chatml'));
});

test('hasTurnMarkup is false for a plain transcript (the shape that caused the bug)', () => {
  assert.equal(hasTurnMarkup('You are concise.\n\nUser: Hi\nAssistant:'), false);
});

// --- thinking suppression ----------------------------------------------------

test('suppressThinking pre-closes the reasoning block so the answer fits the budget', () => {
  // Measured on device: with thinking allowed and 256 tokens the reply was EMPTY
  // (all budget spent deliberating); with this prefill it answered in 586ms.
  const p = formatChat([{ role: 'user', content: 'whats my name ??' }], 'chatml', { suppressThinking: true });
  assert.ok(p.endsWith('<|im_start|>assistant\n<think>\n\n</think>\n\n'));
});

test('without the option the assistant turn is left open for reasoning', () => {
  const p = formatChat([{ role: 'user', content: 'hi' }], 'chatml');
  assert.ok(p.endsWith('<|im_start|>assistant\n'));
  assert.doesNotMatch(p, /<think>/);
});

test('suppressThinking does not disturb the non-ChatML templates', () => {
  for (const t of ['llama3', 'gemma', 'mistral']) {
    const p = formatChat([{ role: 'user', content: 'hi' }], t, { suppressThinking: true });
    assert.doesNotMatch(p, /<think>/, `${t} must not gain a ChatML think block`);
  }
});
