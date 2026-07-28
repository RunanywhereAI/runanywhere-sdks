// Which models are allowed to stay in memory. Without this policy the app loads
// a model per feature and never releases any of them: chat's ~1.2GB LLM, then a
// VLM on top for captioning, then STT and TTS for voice.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const { TAB_MODALITIES, modalitiesToKeep, modalitiesToRelease } = require('../../model-policy');

test('switching from chat to vision releases the language model', () => {
  // The exact case reported: chat, then caption an image.
  assert.deepEqual(modalitiesToRelease('vision', 'vlm', ['llm']), ['llm']);
});

test('switching from vision back to chat releases the vision model', () => {
  assert.deepEqual(modalitiesToRelease('chat', 'llm', ['vlm']), ['vlm']);
});

test('voice keeps speech-to-text, the LLM and text-to-speech together', () => {
  // A naive "one model at a time" rule would break voice completely.
  assert.deepEqual(modalitiesToRelease('voice', 'llm', ['stt', 'llm', 'tts']), []);
  assert.deepEqual(modalitiesToRelease('voice', 'stt', ['stt', 'tts', 'llm']), []);
});

test('arriving at voice from vision releases the vision model but keeps the rest', () => {
  assert.deepEqual(modalitiesToRelease('voice', 'stt', ['vlm', 'llm']), ['vlm']);
});

test('knowledge keeps the embedder and the LLM together', () => {
  assert.deepEqual(modalitiesToRelease('rag', 'llm', ['embedder', 'llm']), []);
  assert.deepEqual(modalitiesToRelease('rag', 'embedder', ['embedder', 'llm', 'vlm']), ['vlm']);
});

test('the model being acquired is never released, even from a screen that owns none', () => {
  // Loading explicitly from the Models library: keep only what was asked for.
  assert.deepEqual(modalitiesToKeep('models', 'vlm'), new Set(['vlm']));
  assert.deepEqual(modalitiesToRelease('models', 'vlm', ['llm', 'stt', 'vlm']).sort(), ['llm', 'stt']);
});

test('an unknown screen keeps only the model being acquired', () => {
  assert.deepEqual(modalitiesToRelease('something-new', 'llm', ['llm', 'vlm', 'stt']).sort(), ['stt', 'vlm']);
});

test('nothing loaded means nothing to release', () => {
  assert.deepEqual(modalitiesToRelease('chat', 'llm', []), []);
  assert.deepEqual(modalitiesToRelease('chat', 'llm', undefined), []);
});

test('re-acquiring on the same screen releases nothing', () => {
  assert.deepEqual(modalitiesToRelease('chat', 'llm', ['llm']), []);
});

test('the release order is stable (predictable teardown + logs)', () => {
  assert.deepEqual(modalitiesToRelease('chat', 'llm', ['vlm', 'stt', 'tts', 'embedder']),
    ['vlm', 'stt', 'tts', 'embedder']);
});

test('every screen that uses a model declares its slots', () => {
  for (const tab of ['chat', 'vision', 'voice', 'rag', 'embeddings', 'structured', 'tools']) {
    assert.ok(Array.isArray(TAB_MODALITIES[tab]), `${tab} must declare its model slots`);
  }
  // Voice is the reason the policy cannot be "one model at a time".
  assert.equal(TAB_MODALITIES.voice.length, 3);
});
