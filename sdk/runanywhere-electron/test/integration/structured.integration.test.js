const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');

const fs = require('node:fs');

// --------------------------------------------------------------------------
// Availability guard
// --------------------------------------------------------------------------
// This is an INTEGRATION test: it needs the built SDK (dist/) AND the compiled
// native addon (runanywhere_native.node) AND a real model (downloaded on first
// use). Requiring '../../dist' eagerly evaluates bridge.ts, whose module-level
// resolveAddon() THROWS if the addon can't be found — so we must guard the
// require itself, not just check the env var.
//
// We consider the suite runnable only when RUNANYWHERE_NATIVE_PATH is set and
// points at an existing file. Everything else -> skip gracefully.
const NATIVE_PATH = process.env.RUNANYWHERE_NATIVE_PATH;
const HAVE_ADDON = Boolean(NATIVE_PATH) && (() => {
  try {
    return fs.existsSync(NATIVE_PATH);
  } catch {
    return false;
  }
})();

// Per-case option: skip with a clear reason when the addon is unavailable.
const SKIP = HAVE_ADDON
  ? {}
  : { skip: 'RUNANYWHERE_NATIVE_PATH unset or file missing — needs built native addon' };

// A generous timeout: first run may download the model + run real inference.
const CASE_TIMEOUT = 120000;
const withTimeout = (opts) => ({ timeout: CASE_TIMEOUT, ...opts });

// Model + generation knobs kept small/deterministic.
const MODEL_ID = 'qwen2.5-0.5b';
const GEN = { maxTokens: 128, temperature: 0 };

// --------------------------------------------------------------------------
// Shared load / teardown
// --------------------------------------------------------------------------
let RunAnywhere = null;
let llm = null;
let loadError = null;

before(async () => {
  if (!HAVE_ADDON) return;
  // Require lazily so an unavailable addon can't crash test collection.
  ({ RunAnywhere } = require('../../dist'));
  try {
    RunAnywhere.initialize();
    llm = await RunAnywhere.loadLLM(MODEL_ID);
  } catch (e) {
    // Record so individual tests can fail with context instead of a bare
    // "llm is null". (E.g. offline first-run with no cached model.)
    loadError = e;
  }
}, withTimeout());

after(() => {
  try {
    if (llm) llm.unload();
  } finally {
    if (RunAnywhere) {
      try {
        RunAnywhere.shutdown();
      } catch {
        /* idempotent; ignore */
      }
    }
  }
});

/** Fail fast with a helpful message if the shared load didn't produce a model. */
function requireLlm() {
  if (loadError) {
    throw new Error(
      `shared LLM load failed (model "${MODEL_ID}" unavailable / offline?): ${loadError.message}`
    );
  }
  assert.ok(llm, 'expected the shared LLMModel to be loaded');
  return llm;
}

// --------------------------------------------------------------------------
// Cases
// --------------------------------------------------------------------------

test(
  'generateObject: object schema { name:string, age:integer } yields correctly-typed fields',
  withTimeout(SKIP),
  async () => {
    const model = requireLlm();
    const schema = {
      type: 'object',
      properties: {
        name: { type: 'string' },
        age: { type: 'integer' },
      },
      required: ['name', 'age'],
    };
    const result = await model.generateObject(
      'Extract the person as JSON. Sentence: "Alice is 30 years old."',
      { ...GEN, schema }
    );

    // generateObject guarantees parseable JSON (JSON.parse inside the facade),
    // so result is a plain object here.
    assert.equal(typeof result, 'object');
    assert.ok(result !== null);
    assert.equal(typeof result.name, 'string');
    // integer in the grammar still parses to a JS number.
    assert.equal(typeof result.age, 'number');
    assert.ok(Number.isInteger(result.age), `age should be an integer, got ${result.age}`);
  }
);

test(
  'generateObject: enum schema constrains sentiment to one of the allowed values',
  withTimeout(SKIP),
  async () => {
    const model = requireLlm();
    const allowed = ['positive', 'negative', 'neutral'];
    const schema = {
      type: 'object',
      properties: {
        sentiment: { type: 'string', enum: allowed },
      },
      required: ['sentiment'],
    };
    const result = await model.generateObject(
      'Classify the sentiment of this review as JSON: "I absolutely love this, it is wonderful!"',
      { ...GEN, schema }
    );

    assert.equal(typeof result, 'object');
    assert.equal(typeof result.sentiment, 'string');
    assert.ok(
      allowed.includes(result.sentiment),
      `sentiment "${result.sentiment}" must be one of ${allowed.join(', ')}`
    );
  }
);

test(
  'generateObject: nested schema (object containing an array of strings)',
  withTimeout(SKIP),
  async () => {
    const model = requireLlm();
    const schema = {
      type: 'object',
      properties: {
        title: { type: 'string' },
        // Bounded so a small model that would otherwise loop into an endless
        // tag list is forced by the grammar to close the array within the
        // token budget (the JSON always parses). Exercises maxItems support.
        tags: { type: 'array', items: { type: 'string' }, maxItems: 5 },
      },
      required: ['title', 'tags'],
    };
    const result = await model.generateObject(
      'Summarize as JSON with a title and a list of tags. Text: "A blog post about cats, dogs, and birds."',
      { ...GEN, schema }
    );

    assert.equal(typeof result, 'object');
    assert.equal(typeof result.title, 'string');
    assert.ok(Array.isArray(result.tags), 'tags must be an array');
    // Every element the grammar allowed is a string.
    for (const t of result.tags) {
      assert.equal(typeof t, 'string', `each tag must be a string, got ${typeof t}`);
    }
  }
);

test(
  'generateObject: array-of-objects style schema holds its shape',
  withTimeout(SKIP),
  async () => {
    const model = requireLlm();
    // Root wrapper object with a "people" array of {name, age} objects. (A bare
    // array root is valid too, but wrapping keeps the prompt/JSON unambiguous.)
    const schema = {
      type: 'object',
      properties: {
        people: {
          type: 'array',
          items: {
            type: 'object',
            properties: {
              name: { type: 'string' },
              age: { type: 'integer' },
            },
            required: ['name', 'age'],
          },
        },
      },
      required: ['people'],
    };
    const result = await model.generateObject(
      'Extract every person as JSON. Text: "Bob is 40. Carol is 25."',
      { ...GEN, schema }
    );

    assert.equal(typeof result, 'object');
    assert.ok(Array.isArray(result.people), 'people must be an array');
    // The grammar constrains each element to the object shape; verify structure
    // for whatever the model produced (may be an empty array, which is valid).
    for (const p of result.people) {
      assert.equal(typeof p, 'object');
      assert.ok(p !== null);
      assert.equal(typeof p.name, 'string', `person.name must be a string in ${JSON.stringify(p)}`);
      assert.equal(typeof p.age, 'number', `person.age must be a number in ${JSON.stringify(p)}`);
      assert.ok(Number.isInteger(p.age), `person.age must be an integer, got ${p.age}`);
    }
  }
);
