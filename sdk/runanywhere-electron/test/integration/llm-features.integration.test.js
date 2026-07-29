// Integration tests for the house-aligned LLM APIs against the real addon:
// generateStream (events + metrics), generateStructured, generateWithTools
// (executor loop), and SDKException on the tool-validation path.
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const NATIVE_PATH = process.env.RUNANYWHERE_NATIVE_PATH;
const HAVE_ADDON = Boolean(NATIVE_PATH) && (() => {
  try { return fs.existsSync(NATIVE_PATH); } catch { return false; }
})();
const SKIP = HAVE_ADDON ? {} : { skip: 'RUNANYWHERE_NATIVE_PATH unset or file missing' };
const withTimeout = (opts) => ({ timeout: 120000, ...opts });

let RunAnywhere = null;
let SDKException = null;
let llm = null;
let loadError = null;

before(async () => {
  if (!HAVE_ADDON) return;
  ({ RunAnywhere, SDKException } = require('../../dist'));
  try {
    RunAnywhere.initialize();
    llm = await RunAnywhere.loadLLM('qwen2.5-0.5b');
  } catch (e) {
    loadError = e;
  }
}, withTimeout());

after(() => {
  try { if (llm) llm.unload(); } finally { if (RunAnywhere) try { RunAnywhere.shutdown(); } catch {} }
});

function requireLlm() {
  if (loadError) throw new Error(`shared LLM load failed: ${loadError.message}`);
  assert.ok(llm, 'expected a loaded LLMModel');
  return llm;
}

test('generateStream yields token events then a final event with metrics', withTimeout(SKIP), async () => {
  const model = requireLlm();
  const events = [];
  for await (const e of model.generateStream('Say hello in one short sentence.', { maxTokens: 24 })) {
    events.push(e);
  }
  assert.ok(events.length >= 2, 'at least one token event + a final event');
  assert.equal(events[0].isFinal, false);
  assert.equal(typeof events[0].token, 'string');
  const final = events[events.length - 1];
  assert.equal(final.isFinal, true);
  assert.equal(final.token, '');
  assert.ok(final.result, 'final event carries the aggregated result');
  assert.equal(typeof final.result.text, 'string');
  assert.ok(final.result.tokenCount > 0, 'counted tokens');
  assert.ok(final.result.tokensPerSecond >= 0);
  assert.ok(final.result.totalTimeMs >= 0);
  assert.ok(final.result.timeToFirstTokenMs >= 0);
});

test('generateStructured (house-uniform name) returns typed JSON', withTimeout(SKIP), async () => {
  const model = requireLlm();
  const result = await model.generateStructured('Extract the person as JSON. Text: "Bob is 40 years old."', {
    maxTokens: 64,
    schema: {
      type: 'object',
      properties: { name: { type: 'string' }, age: { type: 'integer' } },
      required: ['name', 'age'],
    },
  });
  assert.equal(typeof result.name, 'string');
  assert.equal(typeof result.age, 'number');
});

test('generateWithTools picks a tool AND runs its executor', withTimeout(SKIP), async () => {
  const model = requireLlm();
  let received = null;
  const tools = [
    {
      name: 'get_weather',
      description: 'Get the current weather for a city',
      parameters: {
        type: 'object',
        properties: { city: { type: 'string' }, unit: { type: 'string', enum: ['celsius', 'fahrenheit'] } },
        required: ['city', 'unit'],
      },
      execute: (args) => { received = args; return { tempC: 21, city: args.city }; },
    },
    {
      name: 'set_timer',
      description: 'Start a countdown timer',
      parameters: { type: 'object', properties: { seconds: { type: 'integer' } }, required: ['seconds'] },
      execute: () => ({ started: true }),
    },
  ];
  const run = await model.generateWithTools('What is the weather in Tokyo in celsius?', tools);
  assert.ok(['get_weather', 'set_timer'].includes(run.name));
  assert.equal(typeof run.arguments, 'object');
  assert.ok(run.result !== undefined, 'the chosen tool executor produced a result');
  if (run.name === 'get_weather') {
    assert.ok(received, 'the get_weather executor received arguments');
    assert.equal(run.result.tempC, 21);
  }
});

test('generateToolCall rejects an empty tools array with an SDKException', withTimeout(SKIP), async () => {
  const model = requireLlm();
  await assert.rejects(
    () => model.generateToolCall('anything', []),
    (e) => {
      assert.equal(e.name, 'SDKException');
      assert.ok(SDKException && e instanceof SDKException);
      assert.equal(e.code, 259); // ERROR_CODE_INVALID_ARGUMENT
      assert.equal(e.fieldPath, 'tools');
      return true;
    }
  );
});
