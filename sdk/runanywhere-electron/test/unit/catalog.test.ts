import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

import { registerCatalog, clearCatalog, catalogEntries, catalogEntry, isCatalogId } from '../../dist/catalog';
import type { Catalog, ModelType } from '../../dist/catalog';

// catalog.ts is a REGISTRY, not a built-in catalog: the SDK owns the entry
// shape and lookup surface, the app owns which models it offers. These tests
// exercise the registry mechanism against a small synthetic fixture rather
// than any real-world model id — the actual catalog data lives in the app
// (github.com/RunanywhereAI/runanywhere-electron, src/main/model-catalog).

const VALID_TYPES: ModelType[] = ['llm', 'vlm', 'embedder', 'stt', 'tts'];

// The registry's own signature says `string`, but nothing enforces it at
// runtime and callers reach it across a contextBridge, so the guards below are
// asserted against the values that actually arrive.
const notAString = (v: unknown): string => v as string;

const FIXTURE: Catalog = {
  'fixture-llm': {
    type: 'llm',
    files: [{ url: 'https://example.com/model.gguf', as: 'model.gguf' }],
    primary: 'model.gguf',
    license: 'Apache 2.0',
    licenseUrl: 'https://www.apache.org/licenses/LICENSE-2.0',
  },
  'fixture-vlm': {
    type: 'vlm',
    files: [
      { url: 'https://example.com/model.gguf', as: 'model.gguf' },
      { url: 'https://example.com/mmproj.gguf', as: 'mmproj.gguf' },
    ],
    primary: 'model.gguf',
    mmproj: 'mmproj.gguf',
  },
  'fixture-stt': {
    type: 'stt',
    files: [{ url: 'https://example.com/voice.tar.bz2', as: 'voice.tar.bz2' }],
    primary: 'sherpa-onnx-fixture',
    archive: true,
  },
};

beforeEach(() => {
  clearCatalog();
});

test('a fresh process registry is empty', () => {
  // The registry is Object.create(null) internally, so a strict deepEqual
  // against a plain {} literal fails on prototype alone -- compare keys.
  assert.deepEqual(Object.keys(catalogEntries()), []);
});

test('registerCatalog adds entries, retrievable via catalogEntries/catalogEntry/isCatalogId', () => {
  registerCatalog(FIXTURE);
  assert.deepEqual(Object.keys(catalogEntries()).sort(), Object.keys(FIXTURE).sort());
  for (const id of Object.keys(FIXTURE)) {
    assert.equal(isCatalogId(id), true);
    assert.deepEqual(catalogEntry(id), FIXTURE[id]);
  }
});

test('registerCatalog merges — a second call adds without dropping the first', () => {
  registerCatalog({ 'fixture-llm': FIXTURE['fixture-llm'] });
  registerCatalog({ 'fixture-vlm': FIXTURE['fixture-vlm'] });
  assert.deepEqual(Object.keys(catalogEntries()).sort(), ['fixture-llm', 'fixture-vlm']);
});

test('registerCatalog last write wins per id', () => {
  registerCatalog({ 'fixture-llm': FIXTURE['fixture-llm'] });
  const replacement = { ...FIXTURE['fixture-llm'], primary: 'replaced.gguf' };
  registerCatalog({ 'fixture-llm': replacement });
  assert.equal(catalogEntry('fixture-llm')?.primary, 'replaced.gguf');
});

test('clearCatalog drops every registered model', () => {
  registerCatalog(FIXTURE);
  clearCatalog();
  assert.deepEqual(Object.keys(catalogEntries()), []);
  for (const id of Object.keys(FIXTURE)) assert.equal(isCatalogId(id), false);
});

test('catalogEntry returns undefined for an unregistered id', () => {
  assert.equal(catalogEntry('not-registered'), undefined);
});

test('isCatalogId returns false for a bare filename', () => {
  assert.equal(isCatalogId('model.gguf'), false);
});

test('isCatalogId returns false for an absolute path', () => {
  assert.equal(isCatalogId('/usr/local/models/model.gguf'), false);
  assert.equal(isCatalogId('C:\\models\\model.gguf'), false);
});

test('isCatalogId returns false for the empty string', () => {
  assert.equal(isCatalogId(''), false);
});

test('isCatalogId is case-sensitive', () => {
  registerCatalog({ 'fixture-llm': FIXTURE['fixture-llm'] });
  assert.equal(isCatalogId('fixture-llm'), true);
  assert.equal(isCatalogId('Fixture-LLM'), false);
  assert.equal(isCatalogId('FIXTURE-LLM'), false);
});

test('isCatalogId returns false for id with surrounding whitespace', () => {
  registerCatalog({ 'fixture-llm': FIXTURE['fixture-llm'] });
  assert.equal(isCatalogId(' fixture-llm'), false);
  assert.equal(isCatalogId('fixture-llm '), false);
  assert.equal(isCatalogId('\tfixture-llm'), false);
});

test('isCatalogId returns false for inherited Object.prototype names (hasOwnProperty guard)', () => {
  assert.equal(isCatalogId('toString'), false);
  assert.equal(isCatalogId('hasOwnProperty'), false);
  assert.equal(isCatalogId('constructor'), false);
  assert.equal(isCatalogId('valueOf'), false);
  assert.equal(isCatalogId('isPrototypeOf'), false);
  assert.equal(isCatalogId('propertyIsEnumerable'), false);
  assert.equal(isCatalogId('__proto__'), false);
});

test('isCatalogId does not throw and returns false for non-string arguments', () => {
  // The TS signature says string, but nothing enforces it at runtime.
  assert.equal(isCatalogId(notAString(undefined)), false);
  assert.equal(isCatalogId(notAString(null)), false);
  assert.equal(isCatalogId(notAString(0)), false);
  assert.equal(isCatalogId(notAString(123)), false);
  assert.equal(isCatalogId(notAString(true)), false);
  assert.equal(isCatalogId(notAString({})), false);
  assert.equal(isCatalogId(notAString([])), false);
  assert.equal(isCatalogId(notAString(Symbol('x'))), false);
});

test('registering __proto__ as a key does not pollute Object.prototype', () => {
  registerCatalog({ __proto__: FIXTURE['fixture-llm'] } as Catalog);
  assert.equal(isCatalogId('__proto__'), false);
  assert.equal(({} as { type?: unknown }).type, undefined);
});

test('fixture entries satisfy the CatalogEntry shape', () => {
  registerCatalog(FIXTURE);
  for (const [id, entry] of Object.entries(catalogEntries())) {
    assert.ok(VALID_TYPES.includes(entry.type), `entry ${id} has invalid type ${entry.type}`);
    assert.ok(Array.isArray(entry.files) && entry.files.length > 0, `entry ${id} files is empty`);
    for (const file of entry.files) {
      assert.ok(file.url.startsWith('https://'), `entry ${id} file url should be https`);
      assert.ok(file.as.length > 0, `entry ${id} file as is empty`);
    }
    assert.ok(entry.primary.length > 0, `entry ${id} primary is empty`);
  }
});

test('vlm fixture defines an mmproj that matches one of its files', () => {
  registerCatalog(FIXTURE);
  const entry = catalogEntry('fixture-vlm');
  assert.ok(entry, 'the vlm fixture is registered');
  const targets = entry.files.map((f) => f.as);
  assert.ok(entry.mmproj !== undefined && targets.includes(entry.mmproj));
  assert.notEqual(entry.mmproj, entry.primary);
});

test('archive fixture has archive === true and a single .tar.bz2 file', () => {
  registerCatalog(FIXTURE);
  const entry = catalogEntry('fixture-stt');
  assert.ok(entry, 'the stt fixture is registered');
  assert.equal(entry.archive, true);
  assert.equal(entry.files.length, 1);
  assert.ok(entry.files[0].as.endsWith('.tar.bz2'));
});
