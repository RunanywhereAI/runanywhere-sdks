const { test } = require('node:test');
const assert = require('node:assert/strict');

// ---------------------------------------------------------------------------
// Integration test: multi-turn chat memory against the REAL native addon +
// a REAL model (qwen2.5-0.5b). This exercises the full stack:
//   dist/index -> RunAnywhere.createChat -> Chat.sendText ->
//   LLMModel.generate -> native addon.generate (llama.cpp) -> streamed tokens.
//
// It MUST skip gracefully (rather than fail) when the environment can't run it:
//   * the SDK isn't built (no dist/), or
//   * the native runanywhere_native.node addon isn't present.
// bridge.ts resolves the addon EAGERLY at require() time and throws if it's
// missing, so simply requiring dist/ is enough to detect availability.
// ---------------------------------------------------------------------------

let RunAnywhere = null;
let loadError = null;
try {
  ({ RunAnywhere } = require('../../dist'));
} catch (e) {
  // dist not built, or native addon not found -> integration env unavailable.
  loadError = e;
}

// Guard: real model loads/downloads are heavy, so this only runs when the native
// addon is available (RUNANYWHERE_NATIVE_PATH points at a built .node, which is
// what makes `require('../../dist')` succeed). Consistent with the other
// integration tests; the whole integration directory is already opt-in via the
// separate `test:integration` script, so no extra flag is required.
const ADDON_OK = RunAnywhere != null && typeof RunAnywhere.initialize === 'function';
const ENABLED = ADDON_OK;
const MODEL = process.env.RUNANYWHERE_LLM || 'qwen2.5-0.5b';

// A shared, lazily-loaded model across the file's tests (loading is expensive).
let llm = null;
let setupError = null;

async function ensureLoaded() {
  if (llm) return llm;
  RunAnywhere.initialize();
  // loadLLM(idOrPath) auto-downloads the catalog model on first use, then
  // loads it via the native addon and returns an LLMModel handle.
  llm = await RunAnywhere.loadLLM(MODEL);
  return llm;
}

// Load once before the cases; capture any failure so each case can skip.
test('setup: initialize runtime and load LLM', { timeout: 120000 }, async (t) => {
  if (!ENABLED) {
    const why = !ADDON_OK
      ? `native addon unavailable (${loadError ? loadError.message : 'not built'})`
      : 'set RUNANYWHERE_INTEGRATION=1 to run integration tests';
    t.skip(why);
    return;
  }
  try {
    await ensureLoaded();
    assert.ok(llm, 'expected a loaded LLMModel');
    assert.equal(typeof llm.generate, 'function');
    assert.equal(typeof llm.generateText, 'function');
  } catch (e) {
    setupError = e;
    throw e;
  }
});

test('multi-turn chat remembers a fact stated earlier', { timeout: 120000 }, async (t) => {
  if (!ENABLED) {
    t.skip('integration disabled (need addon + RUNANYWHERE_INTEGRATION=1)');
    return;
  }
  if (setupError) {
    t.skip(`skipping: model load failed (${setupError.message})`);
    return;
  }

  const model = await ensureLoaded();
  const chat = RunAnywhere.createChat(model, {
    system: 'You are concise. Answer in one short sentence.',
  });

  // Turn 1: state a memorable fact. No assertion on this reply's content —
  // we only need it recorded into history so turn 2 has context.
  const ack = await chat.sendText('My name is Aman and I love astronomy.');
  assert.equal(typeof ack, 'string');

  // Turn 2: the model must recall the name from turn 1's history.
  const reply = await chat.sendText('What is my name?');
  assert.equal(typeof reply, 'string');
  assert.ok(reply.length > 0, 'expected a non-empty reply');
  assert.ok(
    reply.toLowerCase().includes('aman'),
    `expected the reply to recall the name "Aman", got: ${JSON.stringify(reply)}`
  );

  // History must reflect BOTH recorded turns plus the system message:
  //   [system, user1, assistant1, user2, assistant2] => length 5.
  const msgs = chat.messages;
  assert.ok(
    msgs.length >= 5,
    `expected >= 5 messages (system + 2 turns), got ${msgs.length}`
  );
  assert.equal(msgs[0].role, 'system');
  assert.equal(msgs[0].content, 'You are concise. Answer in one short sentence.');

  // The recorded user turns must be verbatim, in order.
  const userTurns = msgs.filter((m) => m.role === 'user').map((m) => m.content);
  assert.deepEqual(userTurns.slice(0, 2), [
    'My name is Aman and I love astronomy.',
    'What is my name?',
  ]);

  // Each user turn is followed by an assistant turn (the reply we just read
  // is the last assistant message, trimmed into history).
  const assistantTurns = msgs.filter((m) => m.role === 'assistant');
  assert.ok(assistantTurns.length >= 2, 'expected 2 recorded assistant replies');
  assert.equal(assistantTurns[assistantTurns.length - 1].content, reply.trim());
});
