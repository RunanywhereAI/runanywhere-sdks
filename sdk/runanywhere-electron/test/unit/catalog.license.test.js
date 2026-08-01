// Licence metadata for the model catalog. Gemma and Llama weights are NOT open
// source — they carry use restrictions the user accepts by downloading — so the
// catalog must be able to tell a UI which terms apply before a download starts.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const { CATALOG, LICENSES } = require('../../dist/catalog');

test('every LLM and VLM entry declares a licence and a link to it', () => {
  const missing = Object.entries(CATALOG)
    .filter(([, e]) => e.type === 'llm' || e.type === 'vlm')
    .filter(([, e]) => !e.license || !e.licenseUrl)
    .map(([id]) => id);
  assert.deepEqual(missing, [], 'weights offered for download must disclose their licence');
});

test('licence URLs are absolute https links', () => {
  for (const [id, e] of Object.entries(CATALOG)) {
    if (!e.licenseUrl) continue;
    assert.match(e.licenseUrl, /^https:\/\//, `${id} licence URL must be https`);
  }
});

test('the restricted families are tagged with their real licence, not Apache', () => {
  // Mislabelling these as Apache would tell the user they have rights they do not.
  assert.match(CATALOG['gemma-4-e2b'].license, /Gemma/);
  assert.match(CATALOG['gemma-4-e4b'].license, /Gemma/);
  assert.match(CATALOG['gemma-4-e2b-vl'].license, /Gemma/);
  assert.match(CATALOG['llama-3.2-3b'].license, /Llama/);
  assert.match(CATALOG['nemotron3-nano-4b'].license, /NVIDIA/);
});

test('permissively licensed families are marked Apache 2.0', () => {
  for (const id of ['qwen3.5-0.8b', 'qwen3.5-2b', 'qwen3.5-4b', 'lfm2.5-1.2b']) {
    assert.match(CATALOG[id].license, /Apache/, `${id} should be Apache 2.0`);
  }
});

test('LICENSES exposes name + url for each licence the catalog uses', () => {
  const used = new Set(Object.values(CATALOG).map((e) => e.license).filter(Boolean));
  const known = new Set(Object.values(LICENSES).map((l) => l.name));
  for (const name of used) assert.ok(known.has(name), `${name} must be declared in LICENSES`);
  for (const [key, l] of Object.entries(LICENSES)) {
    assert.ok(l.name && l.url, `${key} needs both a name and a url`);
    assert.match(l.url, /^https:\/\//);
  }
});
