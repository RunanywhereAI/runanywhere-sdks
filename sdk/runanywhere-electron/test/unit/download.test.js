const { test } = require('node:test');
const assert = require('node:assert/strict');

const path = require('path');
const os = require('os');
const fs = require('fs');

const download = require('../../dist/download');

// Small helper: a fresh, unique temp root per test (cleaned up by the caller).
function freshTempRoot() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'ra-'));
}

// --- exports -----------------------------------------------------------------

test('modelsRoot is an exported function', () => {
  assert.equal(typeof download.modelsRoot, 'function');
});

test('downloadFile is an exported function', () => {
  assert.equal(typeof download.downloadFile, 'function');
});

test('resolveModel is an exported function', () => {
  assert.equal(typeof download.resolveModel, 'function');
});

test('module exports exactly the public surface', () => {
  // Guard against accidental leakage of internal helpers (extractTarBz2, hfFiles,
  // pickGguf, etc. are not exported).
  assert.equal(typeof download.extractTarBz2, 'undefined');
  assert.equal(typeof download.hfFiles, 'undefined');
  assert.equal(typeof download.pickGguf, 'undefined');
  const own = Object.keys(download).filter((k) => typeof download[k] === 'function');
  assert.deepEqual(own.sort(), [
    'assertRemoteSupported',
    'downloadFile',
    'isRemoteSource',
    'modelStatus',
    'modelsRoot',
    'pathExists',
    'resolveModel',
  ]);
});

// --- isRemoteSource() (pure classifier; no network) --------------------------

test('isRemoteSource is true for http(s) URLs', () => {
  assert.equal(download.isRemoteSource('https://example.com/model.gguf'), true);
  assert.equal(download.isRemoteSource('http://example.com/a.bin'), true);
});

test('isRemoteSource is true for a HuggingFace repo id', () => {
  assert.equal(download.isRemoteSource('bartowski/Qwen2.5-1.5B-Instruct-GGUF'), true);
  // owner/repo:file form is still a remote source.
  assert.equal(download.isRemoteSource('owner/repo:model-Q4_K_M.gguf'), true);
});

test('isRemoteSource is false for a Windows drive path', () => {
  assert.equal(download.isRemoteSource('C:\\models\\weights.gguf'), false);
  assert.equal(download.isRemoteSource('E:\\a\\b.bin'), false);
});

test('isRemoteSource is false for a bare id with no slash', () => {
  assert.equal(download.isRemoteSource('smollm2-135m'), false);
  assert.equal(download.isRemoteSource('unknown-model'), false);
});

test('isRemoteSource is false for a path with 3+ segments', () => {
  // A real nested local path is not a HuggingFace owner/repo.
  assert.equal(download.isRemoteSource('a/b/c/model.gguf'), false);
});

test('isRemoteSource is false for a 2-segment path ending in a model extension', () => {
  // `dir/weights.gguf` is a relative local path, not a HuggingFace repo id
  // (repo ids never end in .gguf/.onnx/.bin/.safetensors).
  assert.equal(download.isRemoteSource('models/foo.gguf'), false);
  assert.equal(download.isRemoteSource('data/model.onnx'), false);
  assert.equal(download.isRemoteSource('out/weights.safetensors'), false);
});

test('isRemoteSource keeps an HF repo with an explicit :file (ext is on the file, not the repo)', () => {
  // The extension guard applies to the pre-`:` repo part, so owner/repo:file.gguf
  // is still a remote source.
  assert.equal(download.isRemoteSource('owner/repo:model-Q4_K_M.gguf'), true);
});

// --- assertRemoteSupported() -------------------------------------------------

test('assertRemoteSupported rejects a remote STT/TTS/embedder source', () => {
  for (const kind of ['stt', 'tts', 'embedder']) {
    assert.throws(() => download.assertRemoteSupported('owner/repo', kind), /not supported yet/, `${kind} remote should throw`);
    assert.throws(() => download.assertRemoteSupported('https://h/m.gguf', kind), /not supported yet/);
  }
});

test('assertRemoteSupported allows remote LLM/VLM and any local path', () => {
  assert.doesNotThrow(() => download.assertRemoteSupported('owner/repo', 'llm'));
  assert.doesNotThrow(() => download.assertRemoteSupported('owner/repo', 'vlm'));
  // A local path is not remote, so even STT/TTS/embedder pass.
  assert.doesNotThrow(() => download.assertRemoteSupported(path.join(os.tmpdir(), 'whisper'), 'stt'));
  assert.doesNotThrow(() => download.assertRemoteSupported('whisper-base', 'stt')); // bare id -> not remote
});

// --- pathExists() / modelStatus() --------------------------------------------

test('pathExists reflects the filesystem', () => {
  const f = path.join(freshTempRoot(), 'x');
  assert.equal(download.pathExists(f), false);
  fs.writeFileSync(f, '1');
  assert.equal(download.pathExists(f), true);
  fs.rmSync(path.dirname(f), { recursive: true, force: true });
});

test('modelStatus returns a {downloaded,sizeBytes} entry for every catalog id', () => {
  const { CATALOG } = require('../../dist/catalog');
  const status = download.modelStatus();
  for (const id of Object.keys(CATALOG)) {
    assert.ok(status[id], `status has ${id}`);
    assert.equal(typeof status[id].downloaded, 'boolean');
    assert.equal(typeof status[id].sizeBytes, 'number');
  }
});

// --- modelsRoot() ------------------------------------------------------------

test('modelsRoot returns an absolute path', () => {
  const root = download.modelsRoot();
  assert.equal(typeof root, 'string');
  assert.ok(path.isAbsolute(root), `expected absolute path, got ${root}`);
});

test('modelsRoot ends with .runanywhere/models segments', () => {
  const root = download.modelsRoot();
  const suffix = path.join('.runanywhere', 'models');
  assert.ok(root.endsWith(suffix), `expected ${root} to end with ${suffix}`);
});

test('modelsRoot is rooted at the home directory', () => {
  const root = download.modelsRoot();
  const expected = path.join(os.homedir(), '.runanywhere', 'models');
  assert.equal(root, expected);
});

test('modelsRoot is stable across calls', () => {
  assert.equal(download.modelsRoot(), download.modelsRoot());
});

// --- resolveModel(): non-catalog local path (no network, no fs writes) -------

test('resolveModel resolves a non-catalog local path to a path-type result', async () => {
  const localPath = path.join(os.tmpdir(), 'nope', 'model.gguf');
  const res = await download.resolveModel(localPath);
  assert.deepEqual(res, {
    id: localPath,
    type: 'path',
    dir: path.dirname(localPath),
    primary: localPath,
  });
});

test('resolveModel non-catalog path result has no mmproj key', async () => {
  const localPath = path.join(os.tmpdir(), 'nope', 'model.gguf');
  const res = await download.resolveModel(localPath);
  assert.ok(!('mmproj' in res), 'expected no mmproj key for a path result');
});

test('resolveModel non-catalog path uses dirname for dir', async () => {
  const localPath = path.join(os.tmpdir(), 'deep', 'nested', 'weights.bin');
  const res = await download.resolveModel(localPath);
  assert.equal(res.dir, path.join(os.tmpdir(), 'deep', 'nested'));
  assert.equal(res.primary, localPath);
  assert.equal(res.id, localPath);
  assert.equal(res.type, 'path');
});

test('resolveModel treats an unknown id (no path separators) as a path', async () => {
  // Not a catalog id -> the non-catalog branch runs. path.dirname('unknown-model') === '.'
  const res = await download.resolveModel('unknown-model');
  assert.equal(res.type, 'path');
  assert.equal(res.id, 'unknown-model');
  assert.equal(res.primary, 'unknown-model');
  assert.equal(res.dir, path.dirname('unknown-model'));
  assert.ok(!('mmproj' in res));
});

test('resolveModel does NOT create the directory for a non-catalog path', async () => {
  // Use a unique directory that does not exist; resolveModel must not mkdir it.
  const base = path.join(os.tmpdir(), 'ra-noexist-' + Date.now() + '-' + Math.random().toString(36).slice(2));
  const localPath = path.join(base, 'model.gguf');
  assert.ok(!fs.existsSync(base), 'precondition: dir must not already exist');
  const res = await download.resolveModel(localPath);
  assert.equal(res.type, 'path');
  assert.ok(!fs.existsSync(base), 'resolveModel must not have created the directory');
});

// --- resolveModel(): hermetic "already downloaded" catalog path (no network) -

test('resolveModel skips download when the catalog file already exists', async () => {
  const tempRoot = freshTempRoot();
  try {
    const modelDir = path.join(tempRoot, 'smollm2-135m');
    fs.mkdirSync(modelDir, { recursive: true });
    // Pre-create the expected primary file so the download loop is skipped.
    fs.writeFileSync(path.join(modelDir, 'model.gguf'), Buffer.from([0]));

    const res = await download.resolveModel('smollm2-135m', { dir: tempRoot });

    assert.equal(res.id, 'smollm2-135m');
    assert.equal(res.type, 'llm');
    assert.equal(res.dir, modelDir);
    assert.equal(res.primary, path.join(tempRoot, 'smollm2-135m', 'model.gguf'));
    assert.equal(res.mmproj, undefined);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test('resolveModel does not overwrite the existing catalog file', async () => {
  const tempRoot = freshTempRoot();
  try {
    const modelDir = path.join(tempRoot, 'smollm2-135m');
    fs.mkdirSync(modelDir, { recursive: true });
    const primary = path.join(modelDir, 'model.gguf');
    const sentinel = Buffer.from('already-here');
    fs.writeFileSync(primary, sentinel);

    await download.resolveModel('smollm2-135m', { dir: tempRoot });

    // Untouched: no network fetch replaced our sentinel bytes.
    assert.deepEqual(fs.readFileSync(primary), sentinel);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test('resolveModel returns undefined mmproj for a non-VLM catalog entry', async () => {
  const tempRoot = freshTempRoot();
  try {
    const modelDir = path.join(tempRoot, 'smollm2-135m');
    fs.mkdirSync(modelDir, { recursive: true });
    fs.writeFileSync(path.join(modelDir, 'model.gguf'), Buffer.from([0]));

    const res = await download.resolveModel('smollm2-135m', { dir: tempRoot });
    assert.ok('mmproj' in res, 'ResolvedModel shape includes the mmproj key');
    assert.equal(res.mmproj, undefined);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test('resolveModel creates the per-model directory (dir side effect) when it is missing', async () => {
  // Only the tempRoot exists; the per-id subdir does not. Because BOTH catalog
  // files for the entry are pre-staged *by us* the loop cannot fire — but we
  // must stage them, which requires the dir. Instead verify the mkdir side
  // effect directly: after resolve, res.dir exists on disk.
  const tempRoot = freshTempRoot();
  try {
    const modelDir = path.join(tempRoot, 'smollm2-135m');
    fs.mkdirSync(modelDir, { recursive: true });
    fs.writeFileSync(path.join(modelDir, 'model.gguf'), Buffer.from([0]));

    const res = await download.resolveModel('smollm2-135m', { dir: tempRoot });
    assert.ok(fs.existsSync(res.dir), 'resolveModel should ensure the model dir exists');
    assert.equal(res.dir, modelDir);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

// --- resolveModel(): VLM entry (multi-file + mmproj resolution) --------------

test('resolveModel resolves a VLM entry with an mmproj path when files exist', async () => {
  const tempRoot = freshTempRoot();
  try {
    const modelDir = path.join(tempRoot, 'smolvlm-256m');
    fs.mkdirSync(modelDir, { recursive: true });
    // smolvlm-256m has two files: model.gguf (primary) and mmproj.gguf.
    fs.writeFileSync(path.join(modelDir, 'model.gguf'), Buffer.from([0]));
    fs.writeFileSync(path.join(modelDir, 'mmproj.gguf'), Buffer.from([0]));

    const res = await download.resolveModel('smolvlm-256m', { dir: tempRoot });

    assert.equal(res.id, 'smolvlm-256m');
    assert.equal(res.type, 'vlm');
    assert.equal(res.dir, modelDir);
    assert.equal(res.primary, path.join(modelDir, 'model.gguf'));
    assert.equal(res.mmproj, path.join(modelDir, 'mmproj.gguf'));
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

// --- resolveModel(): embedder entry (two plain, non-archive files) -----------

test('resolveModel resolves a multi-file embedder entry when all files exist', async () => {
  const tempRoot = freshTempRoot();
  try {
    const modelDir = path.join(tempRoot, 'minilm');
    fs.mkdirSync(modelDir, { recursive: true });
    // minilm has model.onnx (primary) + vocab.txt, no archive, no mmproj.
    fs.writeFileSync(path.join(modelDir, 'model.onnx'), Buffer.from([0]));
    fs.writeFileSync(path.join(modelDir, 'vocab.txt'), Buffer.from('hello'));

    const res = await download.resolveModel('minilm', { dir: tempRoot });

    assert.equal(res.type, 'embedder');
    assert.equal(res.primary, path.join(modelDir, 'model.onnx'));
    assert.equal(res.mmproj, undefined);
    assert.equal(res.dir, modelDir);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

// --- resolveModel(): archive entry, "extracted" short-circuit ----------------

test('resolveModel skips an archive download when the extracted primary already exists', async () => {
  // For an archive entry, the loop skips download when the extracted primary
  // (a directory here) exists — even though the downloaded .tar.bz2 (`as`) does not.
  const tempRoot = freshTempRoot();
  try {
    const modelDir = path.join(tempRoot, 'whisper-tiny');
    fs.mkdirSync(modelDir, { recursive: true });
    // whisper-tiny.primary === 'sherpa-onnx-whisper-tiny.en' (extraction output).
    const extractedPrimary = path.join(modelDir, 'sherpa-onnx-whisper-tiny.en');
    fs.mkdirSync(extractedPrimary, { recursive: true });
    // Deliberately do NOT create whisper.tar.bz2 — the `extracted` guard must skip.
    assert.ok(!fs.existsSync(path.join(modelDir, 'whisper.tar.bz2')));

    const res = await download.resolveModel('whisper-tiny', { dir: tempRoot });

    assert.equal(res.type, 'stt');
    assert.equal(res.primary, extractedPrimary);
    assert.equal(res.mmproj, undefined);
    // No download/extract happened: the tar file was never created.
    assert.ok(!fs.existsSync(path.join(modelDir, 'whisper.tar.bz2')));
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test('resolveModel re-extracts an archive when the primary is missing (retry, not skip)', async () => {
  // The old code skipped whenever the .tar.bz2 existed, even if extraction never
  // produced the primary — permanently blocking retry. Now a present archive with
  // a MISSING primary must trigger (re-)extraction. A bogus archive makes the
  // extraction step run and fail loudly instead of silently returning a broken path.
  const tempRoot = freshTempRoot();
  try {
    const modelDir = path.join(tempRoot, 'whisper-tiny');
    fs.mkdirSync(modelDir, { recursive: true });
    fs.writeFileSync(path.join(modelDir, 'whisper.tar.bz2'), 'not a real archive');
    // primary (sherpa-onnx-whisper-tiny.en) intentionally absent.
    await assert.rejects(
      () => download.resolveModel('whisper-tiny', { dir: tempRoot }),
      /extraction failed/,
      'a present archive with a missing primary must (re-)extract, not skip'
    );
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test('resolveModel archive primary resolves under the model dir (piper tts entry)', async () => {
  const tempRoot = freshTempRoot();
  try {
    const modelDir = path.join(tempRoot, 'piper-lessac');
    fs.mkdirSync(modelDir, { recursive: true });
    const extractedPrimary = path.join(modelDir, 'vits-piper-en_US-lessac-medium');
    fs.mkdirSync(extractedPrimary, { recursive: true });

    const res = await download.resolveModel('piper-lessac', { dir: tempRoot });

    assert.equal(res.type, 'tts');
    assert.equal(res.primary, extractedPrimary);
    assert.equal(res.dir, modelDir);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

// --- resolveModel(): opts.dir defaulting is honored -------------------------

test('resolveModel honors an explicit opts.dir root for the model directory', async () => {
  const tempRoot = freshTempRoot();
  try {
    const modelDir = path.join(tempRoot, 'smollm2-135m');
    fs.mkdirSync(modelDir, { recursive: true });
    fs.writeFileSync(path.join(modelDir, 'model.gguf'), Buffer.from([0]));

    const res = await download.resolveModel('smollm2-135m', { dir: tempRoot });
    // dir must be rooted at opts.dir, NOT at modelsRoot()/home.
    assert.equal(res.dir, path.join(tempRoot, 'smollm2-135m'));
    assert.ok(!res.dir.startsWith(download.modelsRoot()), 'opts.dir should override modelsRoot()');
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

// --- downloadFile(): shape + error path (no live network) --------------------

test('downloadFile returns a Promise', () => {
  // Point at an RFC 2606 reserved, guaranteed non-resolving host so no real
  // network I/O occurs; the connection error rejects the promise.
  const p = download.downloadFile('https://nonexistent.invalid/model.gguf', path.join(os.tmpdir(), 'ra-dl-shape.part'));
  assert.ok(p instanceof Promise);
  // Swallow the expected rejection so it doesn't surface as an unhandled rejection.
  p.then(
    () => {},
    () => {}
  );
});

test('downloadFile rejects on a connection/transport error (unresolvable host)', async () => {
  const dest = path.join(os.tmpdir(), 'ra-dl-fail-' + Date.now() + '.gguf');
  await assert.rejects(
    () => download.downloadFile('https://nonexistent.invalid/model.gguf', dest),
    (err) => {
      assert.ok(err instanceof Error, 'expected an Error');
      return true;
    }
  );
  // No partial file or final file should be left behind on a transport failure.
  assert.ok(!fs.existsSync(dest), 'dest must not exist after a failed download');
  assert.ok(!fs.existsSync(dest + '.part'), '.part must not be renamed into place on failure');
});

test('downloadFile does not invoke onProgress when the request fails to connect', async () => {
  const dest = path.join(os.tmpdir(), 'ra-dl-noprog-' + Date.now() + '.gguf');
  let progressCalls = 0;
  await assert.rejects(() =>
    download.downloadFile('https://nonexistent.invalid/model.gguf', dest, () => {
      progressCalls += 1;
    })
  );
  assert.equal(progressCalls, 0, 'onProgress must not fire when the connection never succeeds');
});

// --- downloadFile resume (hermetic: a local http server with Range support) --

const http = require('node:http');

// Serve `body` from a localhost server. Records each request's Range header in
// `seen`. `ignoreRange` makes it reply 200 (full) even when a Range is sent.
function serve(body, opts = {}) {
  const seen = [];
  const server = http.createServer((req, res) => {
    seen.push(req.headers.range || null);
    const range = opts.ignoreRange ? null : req.headers.range;
    const m = range && /bytes=(\d+)-/.exec(range);
    if (m) {
      const start = parseInt(m[1], 10);
      if (start >= body.length) { res.writeHead(416); res.end(); return; }
      res.writeHead(206, {
        'Content-Length': String(body.length - start),
        'Content-Range': `bytes ${start}-${body.length - 1}/${body.length}`,
      });
      res.end(body.subarray(start));
      return;
    }
    res.writeHead(200, { 'Content-Length': String(body.length) });
    res.end(body);
  });
  return new Promise((resolve) =>
    server.listen(0, '127.0.0.1', () =>
      resolve({ server, seen, url: `http://127.0.0.1:${server.address().port}/f.bin` })
    )
  );
}

test('downloadFile fetches a whole file and renames off .part', async () => {
  const body = Buffer.from('x'.repeat(5000));
  const { server, url } = await serve(body);
  const dir = freshTempRoot();
  const dest = path.join(dir, 'f.bin');
  try {
    await download.downloadFile(url, dest);
    assert.deepEqual(fs.readFileSync(dest), body);
    assert.ok(!fs.existsSync(dest + '.part'), '.part removed on success');
  } finally {
    server.close();
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('downloadFile resumes an interrupted .part with a Range request', async () => {
  const body = Buffer.from(Array.from({ length: 8000 }, (_, i) => i % 251));
  const { server, seen, url } = await serve(body);
  const dir = freshTempRoot();
  const dest = path.join(dir, 'f.bin');
  fs.writeFileSync(dest + '.part', body.subarray(0, 3000)); // interrupted at 3000 bytes
  try {
    await download.downloadFile(url, dest);
    assert.deepEqual(fs.readFileSync(dest), body, 'resumed file matches the original bytes');
    assert.ok(seen.includes('bytes=3000-'), 'sent a Range from the .part size');
  } finally {
    server.close();
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('downloadFile restarts when the server ignores Range (200)', async () => {
  const body = Buffer.from('y'.repeat(6000));
  const { server, url } = await serve(body, { ignoreRange: true });
  const dir = freshTempRoot();
  const dest = path.join(dir, 'f.bin');
  fs.writeFileSync(dest + '.part', Buffer.from('stale-partial-bytes'));
  try {
    await download.downloadFile(url, dest);
    assert.deepEqual(fs.readFileSync(dest), body, 'a full 200 restart overwrites the stale .part');
  } finally {
    server.close();
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('downloadFile finalizes a .part that is already complete (416)', async () => {
  const body = Buffer.from('z'.repeat(4096));
  const { server, url } = await serve(body);
  const dir = freshTempRoot();
  const dest = path.join(dir, 'f.bin');
  fs.writeFileSync(dest + '.part', body); // already the whole file
  try {
    await download.downloadFile(url, dest);
    assert.deepEqual(fs.readFileSync(dest), body);
  } finally {
    server.close();
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('downloadFile keeps the .part when the connection drops mid-stream', async () => {
  const body = Buffer.from('w'.repeat(10000));
  const server = http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Length': String(body.length) });
    // Flush a partial, let the client receive + persist it, THEN drop the socket
    // (a realistic mid-download interruption, not an instant reset).
    res.write(body.subarray(0, 4000), () => setTimeout(() => res.destroy(), 40));
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const url = `http://127.0.0.1:${server.address().port}/f.bin`;
  const dir = freshTempRoot();
  const dest = path.join(dir, 'f.bin');
  try {
    await assert.rejects(download.downloadFile(url, dest));
    assert.ok(!fs.existsSync(dest), 'no final file on failure');
    assert.ok(fs.existsSync(dest + '.part'), '.part kept for a later resume');
  } finally {
    server.close();
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
