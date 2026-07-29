const { test } = require('node:test');
const assert = require('node:assert/strict');

// --------------------------------------------------------------------------
// Native-addon skip guard.
//
// Requiring the compiled SDK (`../../dist`) transitively loads bridge.js, which
// resolves the native `runanywhere_native.node` at module-load time and THROWS
// when it is absent. So the require itself is wrapped: if the addon (or the
// build output) is missing, `sdk` stays null and every case skips gracefully
// instead of erroring the whole file. This is an INTEGRATION test — it needs
// the built SDK + native .node + a real model on disk.
// --------------------------------------------------------------------------
let sdk = null;
let loadError = null;
try {
  sdk = require('../../dist');
} catch (e) {
  loadError = e;
}

const HAVE_ADDON = sdk !== null;
const SKIP = HAVE_ADDON ? false : `native addon not available: ${loadError && loadError.message}`;

// Catalog id for the model under test (see dist/catalog.js: single-file llm).
const MODEL_ID = 'qwen2.5-0.5b';

// The two tools the model may be asked to call.
const TOOLS = [
  {
    name: 'get_weather',
    description: 'Get the current weather for a city.',
    parameters: {
      type: 'object',
      properties: {
        city: { type: 'string' },
        unit: { enum: ['celsius', 'fahrenheit'] },
      },
      required: ['city', 'unit'],
    },
  },
  {
    name: 'set_timer',
    description: 'Set a countdown timer.',
    parameters: {
      type: 'object',
      properties: {
        seconds: { type: 'integer' },
        label: { type: 'string' },
      },
      required: ['seconds', 'label'],
    },
  },
];

const TOOL_NAMES = TOOLS.map((t) => t.name);

// Shared model handle, brought up once for the whole file.
let llm = null;
let setupError = null;

test.before(async () => {
  if (!HAVE_ADDON) return;
  try {
    sdk.RunAnywhere.initialize();
    // Auto-downloads the catalog model if it is not already present.
    llm = await sdk.RunAnywhere.loadLLM(MODEL_ID);
  } catch (e) {
    // Leave llm null; each test asserts on it and skips if the model could not
    // be brought up (e.g. offline, no disk space). We record the reason.
    setupError = e;
  }
});

test.after(() => {
  if (!HAVE_ADDON) return;
  try {
    if (llm) llm.unload();
  } catch (_) {
    /* ignore */
  }
  try {
    sdk.RunAnywhere.shutdown();
  } catch (_) {
    /* ignore */
  }
});

/** Returns a skip-reason string if we cannot run a model-backed case, else null. */
function modelSkip() {
  if (!HAVE_ADDON) return SKIP;
  if (!llm) return `model ${MODEL_ID} could not be loaded: ${setupError && setupError.message}`;
  return null;
}

/** Assert an object looks like a well-formed ToolCall for one of our tools. */
function assertValidToolCall(call) {
  assert.ok(call, 'expected a tool call object');
  assert.equal(typeof call, 'object');
  assert.equal(typeof call.name, 'string');
  assert.ok(call.name.length > 0, 'tool call name should be non-empty');
  assert.ok(
    TOOL_NAMES.includes(call.name),
    `tool call name ${JSON.stringify(call.name)} should be one of ${JSON.stringify(TOOL_NAMES)}`
  );
  assert.ok(call.arguments !== null, 'arguments should not be null');
  assert.equal(typeof call.arguments, 'object', 'arguments should be an object');
  assert.ok(!Array.isArray(call.arguments), 'arguments should be a plain object, not an array');
}

// --------------------------------------------------------------------------
// Happy path: weather query routes to get_weather with an object of arguments.
// --------------------------------------------------------------------------
test('generateToolCall routes a weather question to get_weather', { timeout: 120000 }, async (t) => {
  const reason = modelSkip();
  if (reason) return t.skip(reason);

  const call = await llm.generateToolCall(
    'What is the weather in Tokyo in celsius?',
    TOOLS
  );

  assertValidToolCall(call);
  assert.equal(call.name, 'get_weather');
  // arguments is an object (grammar-guaranteed shape).
  assert.equal(typeof call.arguments, 'object');
  assert.ok(call.arguments !== null);
});

// --------------------------------------------------------------------------
// Happy path: timer request routes to set_timer.
// --------------------------------------------------------------------------
test('generateToolCall routes a timer request to set_timer', { timeout: 120000 }, async (t) => {
  const reason = modelSkip();
  if (reason) return t.skip(reason);

  const call = await llm.generateToolCall('Set a 5 minute timer for tea.', TOOLS);

  assertValidToolCall(call);
  assert.equal(call.name, 'set_timer');
});

// --------------------------------------------------------------------------
// REGRESSION: sampler-reset fix.
//
// Calling generateToolCall twice in a row with the SAME tools (hence the same
// grammar) must both return a valid, non-empty tool call. Before the fix the
// grammar/sampler state was not reset between calls, so the second call emitted
// 0 tokens and the parse threw. Both calls must succeed here.
// --------------------------------------------------------------------------
test('REGRESSION: two consecutive tool calls with the same grammar both succeed', { timeout: 120000 }, async (t) => {
  const reason = modelSkip();
  if (reason) return t.skip(reason);

  const first = await llm.generateToolCall('What is the weather in Paris in fahrenheit?', TOOLS);
  assertValidToolCall(first);

  // Second call reuses the identical `TOOLS` array -> identical grammar.
  const second = await llm.generateToolCall('Set a 30 second timer for eggs.', TOOLS);
  assertValidToolCall(second);

  // Both names are among the two tools (the crux of the regression: the second
  // call must not have returned an empty/unparseable completion).
  assert.ok(TOOL_NAMES.includes(first.name));
  assert.ok(TOOL_NAMES.includes(second.name));
});

// --------------------------------------------------------------------------
// Error path: an empty tools array is rejected before any generation.
// This one does not need a loaded model (the guard fires synchronously inside
// generateToolCall), but it still needs the SDK/addon require to have worked
// so the LLMModel class exists.
// --------------------------------------------------------------------------
test('generateToolCall rejects when given an empty tools array', { timeout: 120000 }, async (t) => {
  if (!HAVE_ADDON) return t.skip(SKIP);
  if (!llm) return t.skip(`model ${MODEL_ID} could not be loaded: ${setupError && setupError.message}`);

  await assert.rejects(
    () => llm.generateToolCall('anything at all', []),
    /at least one tool is required/
  );
});
