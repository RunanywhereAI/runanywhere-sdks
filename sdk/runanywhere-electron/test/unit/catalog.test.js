const { test } = require('node:test');
const assert = require('node:assert/strict');

const { CATALOG, isCatalogId } = require('../../dist/catalog');

const VALID_TYPES = ['llm', 'vlm', 'embedder', 'stt', 'tts'];
const ARCHIVE_TYPES = ['stt', 'tts'];

test('CATALOG is a non-empty object', () => {
  assert.equal(typeof CATALOG, 'object');
  assert.notEqual(CATALOG, null);
  assert.ok(Object.keys(CATALOG).length > 0);
});

test('isCatalogId is a function', () => {
  assert.equal(typeof isCatalogId, 'function');
});

test('isCatalogId returns true for every key in CATALOG', () => {
  for (const id of Object.keys(CATALOG)) {
    assert.equal(isCatalogId(id), true, `expected isCatalogId(${JSON.stringify(id)}) to be true`);
  }
});

test('isCatalogId agrees with Object.keys(CATALOG) exactly', () => {
  const keys = new Set(Object.keys(CATALOG));
  // Every key resolves true; the membership relation is the definition of isCatalogId.
  for (const id of keys) {
    assert.equal(isCatalogId(id), true);
  }
  // A non-key does not resolve.
  assert.ok(!keys.has('definitely-not-a-key'));
  assert.equal(isCatalogId('definitely-not-a-key'), false);
});

test('isCatalogId returns false for a bare filename', () => {
  assert.equal(isCatalogId('model.gguf'), false);
});

test('isCatalogId returns false for an absolute path', () => {
  assert.equal(isCatalogId('/usr/local/models/model.gguf'), false);
  assert.equal(isCatalogId('C:\\models\\model.gguf'), false);
});

test('isCatalogId returns false for an unknown model id', () => {
  assert.equal(isCatalogId('unknown-model'), false);
});

test('isCatalogId returns false for the empty string', () => {
  assert.equal(isCatalogId(''), false);
});

test('isCatalogId is case-sensitive', () => {
  // 'smollm2-135m' is a real key; upper/mixed-case variants are not.
  assert.equal(isCatalogId('smollm2-135m'), true);
  assert.equal(isCatalogId('SmolLM2-135M'), false);
  assert.equal(isCatalogId('SMOLLM2-135M'), false);
  assert.equal(isCatalogId('MiniLM'), false);
  assert.equal(isCatalogId('minilm'), true);
});

test('isCatalogId returns false for id with surrounding whitespace', () => {
  assert.equal(isCatalogId(' minilm'), false);
  assert.equal(isCatalogId('minilm '), false);
  assert.equal(isCatalogId('\tminilm'), false);
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
  // hasOwnProperty coerces the key to a string, so none of these match a real key.
  assert.equal(isCatalogId(undefined), false);
  assert.equal(isCatalogId(null), false);
  assert.equal(isCatalogId(0), false);
  assert.equal(isCatalogId(123), false);
  assert.equal(isCatalogId(true), false);
  assert.equal(isCatalogId({}), false);
  assert.equal(isCatalogId([]), false);
  assert.equal(isCatalogId(Symbol('x')), false);
});

test('every CATALOG entry has a valid type', () => {
  for (const [id, entry] of Object.entries(CATALOG)) {
    assert.ok(VALID_TYPES.includes(entry.type), `entry ${id} has invalid type ${entry.type}`);
  }
});

test('every CATALOG entry has a non-empty files array', () => {
  for (const [id, entry] of Object.entries(CATALOG)) {
    assert.ok(Array.isArray(entry.files), `entry ${id} files is not an array`);
    assert.ok(entry.files.length > 0, `entry ${id} files is empty`);
  }
});

test('every file in every entry has an https url and a non-empty as', () => {
  for (const [id, entry] of Object.entries(CATALOG)) {
    for (const file of entry.files) {
      assert.equal(typeof file.url, 'string', `entry ${id} file url not a string`);
      assert.ok(
        file.url.startsWith('https://'),
        `entry ${id} file url does not start with https://: ${file.url}`
      );
      assert.equal(typeof file.as, 'string', `entry ${id} file as not a string`);
      assert.ok(file.as.length > 0, `entry ${id} file as is empty`);
      // `as` is a filename, not a path — it must not contain path separators.
      assert.ok(!file.as.includes('/'), `entry ${id} file as should be a bare filename: ${file.as}`);
      assert.ok(!file.as.includes('\\'), `entry ${id} file as should be a bare filename: ${file.as}`);
    }
  }
});

test('within an entry, every file has a distinct `as` target', () => {
  for (const [id, entry] of Object.entries(CATALOG)) {
    const names = entry.files.map((f) => f.as);
    assert.equal(new Set(names).size, names.length, `entry ${id} has duplicate as-filenames`);
  }
});

test('every CATALOG entry has a non-empty primary string', () => {
  for (const [id, entry] of Object.entries(CATALOG)) {
    assert.equal(typeof entry.primary, 'string', `entry ${id} primary not a string`);
    assert.ok(entry.primary.length > 0, `entry ${id} primary is empty`);
  }
});

test('non-archive primary points at one of the downloaded files', () => {
  // For non-archive entries the primary is a file that was actually saved (matches an `as`).
  // Archive entries extract to a directory, so their primary is a dir name, not an `as`.
  for (const [id, entry] of Object.entries(CATALOG)) {
    if (entry.archive === true) continue;
    const targets = entry.files.map((f) => f.as);
    assert.ok(
      targets.includes(entry.primary),
      `entry ${id} primary ${entry.primary} is not among downloaded files ${JSON.stringify(targets)}`
    );
  }
});

test('every vlm entry defines an mmproj string that matches one of its files', () => {
  for (const [id, entry] of Object.entries(CATALOG)) {
    if (entry.type === 'vlm') {
      assert.equal(typeof entry.mmproj, 'string', `vlm entry ${id} mmproj not a string`);
      assert.ok(entry.mmproj.length > 0, `vlm entry ${id} mmproj is empty`);
      const targets = entry.files.map((f) => f.as);
      assert.ok(
        targets.includes(entry.mmproj),
        `vlm entry ${id} mmproj ${entry.mmproj} is not among downloaded files ${JSON.stringify(targets)}`
      );
      // mmproj and primary are two different downloaded files.
      assert.notEqual(entry.mmproj, entry.primary, `vlm entry ${id} mmproj equals primary`);
    }
  }
});

test('only vlm entries define mmproj', () => {
  for (const [id, entry] of Object.entries(CATALOG)) {
    if (entry.type !== 'vlm') {
      assert.equal(entry.mmproj, undefined, `non-vlm entry ${id} should not define mmproj`);
    }
  }
});

test('stt and tts entries have archive === true and a .tar.bz2 download', () => {
  for (const [id, entry] of Object.entries(CATALOG)) {
    if (ARCHIVE_TYPES.includes(entry.type)) {
      assert.equal(entry.archive, true, `entry ${id} of type ${entry.type} should have archive true`);
      // Archive entries download a single tarball.
      for (const file of entry.files) {
        assert.ok(
          file.as.endsWith('.tar.bz2'),
          `archive entry ${id} download ${file.as} should be a .tar.bz2`
        );
      }
    }
  }
});

test('llm/vlm/embedder entries are not archives and omit the archive flag', () => {
  for (const [id, entry] of Object.entries(CATALOG)) {
    if (entry.type === 'llm' || entry.type === 'vlm' || entry.type === 'embedder') {
      // Source only ever sets archive to true; non-archive entries leave it undefined.
      assert.notEqual(entry.archive, true, `entry ${id} of type ${entry.type} should not be an archive`);
      assert.equal(entry.archive, undefined, `entry ${id} of type ${entry.type} should omit archive`);
    }
  }
});

test('archive flag, when present, is strictly the boolean true', () => {
  for (const [id, entry] of Object.entries(CATALOG)) {
    if ('archive' in entry) {
      assert.strictEqual(entry.archive, true, `entry ${id} archive should be exactly true when present`);
    }
  }
});

test('every archive entry has exactly one file', () => {
  for (const [id, entry] of Object.entries(CATALOG)) {
    if (entry.archive === true) {
      assert.equal(entry.files.length, 1, `archive entry ${id} should have exactly one file`);
    }
  }
});

test('spot check: smollm2-135m is a single-file llm', () => {
  const entry = CATALOG['smollm2-135m'];
  assert.ok(entry, 'smollm2-135m entry missing');
  assert.equal(entry.type, 'llm');
  assert.equal(entry.files.length, 1);
  assert.equal(entry.files[0].as, 'model.gguf');
  assert.equal(entry.primary, 'model.gguf');
  assert.equal(entry.archive, undefined);
  assert.equal(entry.mmproj, undefined);
});

test('spot check: qwen2.5-0.5b is a single-file llm', () => {
  const entry = CATALOG['qwen2.5-0.5b'];
  assert.ok(entry, 'qwen2.5-0.5b entry missing');
  assert.equal(entry.type, 'llm');
  assert.equal(entry.files.length, 1);
  assert.equal(entry.primary, 'model.gguf');
});

test('spot check: minilm is an embedder with model + vocab', () => {
  const entry = CATALOG['minilm'];
  assert.ok(entry, 'minilm entry missing');
  assert.equal(entry.type, 'embedder');
  assert.equal(entry.files.length, 2);
  const names = entry.files.map((f) => f.as);
  assert.deepEqual(names.sort(), ['model.onnx', 'vocab.txt']);
  assert.equal(entry.primary, 'model.onnx');
  assert.equal(entry.archive, undefined);
});

test('spot check: smolvlm-256m has exactly 2 files and an mmproj', () => {
  const entry = CATALOG['smolvlm-256m'];
  assert.ok(entry, 'smolvlm-256m entry missing');
  assert.equal(entry.type, 'vlm');
  assert.equal(entry.files.length, 2);
  assert.equal(typeof entry.mmproj, 'string');
  assert.ok(entry.mmproj.length > 0);
  assert.equal(entry.primary, 'model.gguf');
  assert.equal(entry.mmproj, 'mmproj.gguf');
});

test('spot check: whisper-tiny is an stt archive', () => {
  const entry = CATALOG['whisper-tiny'];
  assert.ok(entry, 'whisper-tiny entry missing');
  assert.equal(entry.type, 'stt');
  assert.equal(entry.archive, true);
  assert.equal(entry.files.length, 1);
  assert.ok(entry.files[0].as.endsWith('.tar.bz2'));
  assert.equal(entry.primary, 'sherpa-onnx-whisper-tiny.en');
});

test('spot check: piper-lessac is a tts archive', () => {
  const entry = CATALOG['piper-lessac'];
  assert.ok(entry, 'piper-lessac entry missing');
  assert.equal(entry.type, 'tts');
  assert.equal(entry.archive, true);
  assert.equal(entry.files.length, 1);
  assert.ok(entry.files[0].as.endsWith('.tar.bz2'));
  assert.equal(entry.primary, 'vits-piper-en_US-lessac-medium');
});

test('spot check: known ids are present and resolve via isCatalogId', () => {
  for (const id of ['smollm2-135m', 'qwen2.5-0.5b', 'smolvlm-256m', 'minilm', 'whisper-tiny', 'piper-lessac']) {
    assert.ok(Object.prototype.hasOwnProperty.call(CATALOG, id), `${id} missing from CATALOG`);
    assert.equal(isCatalogId(id), true);
  }
});

test('CATALOG covers at least one entry of every model type', () => {
  const typesPresent = new Set(Object.values(CATALOG).map((e) => e.type));
  for (const t of VALID_TYPES) {
    assert.ok(typesPresent.has(t), `no CATALOG entry of type ${t}`);
  }
});
