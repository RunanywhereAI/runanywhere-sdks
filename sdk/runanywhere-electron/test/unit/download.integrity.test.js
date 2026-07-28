// Integrity + capacity guards for model downloads. These are the checks that stop
// a corrupted or tampered multi-GB model file from being loaded into llama.cpp,
// and stop a download from filling the user's disk.
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');

const http = require('node:http');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { downloadFile, sha256File, assertEnoughSpace } = require('../../dist/download');

const BODY = 'model-bytes\n'.repeat(500);
const GOOD_SHA = crypto.createHash('sha256').update(Buffer.from(BODY)).digest('hex');
const WRONG_SHA = 'f'.repeat(64);

let server;
let baseUrl;
let tmpDir;

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ra-integrity-'));
  server = http.createServer((req, res) => {
    if (req.url === '/model.gguf') {
      res.writeHead(200, { 'content-length': Buffer.byteLength(BODY) });
      res.end(BODY);
      return;
    }
    res.writeHead(404).end();
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  await new Promise((r) => server.close(r));
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

// --- sha256File --------------------------------------------------------------

test('sha256File hashes file contents', () => {
  const f = path.join(tmpDir, 'h.bin');
  fs.writeFileSync(f, BODY);
  assert.equal(sha256File(f), GOOD_SHA);
});

// --- downloadFile integrity gate --------------------------------------------

test('a download whose digest matches is published', async () => {
  const dest = path.join(tmpDir, 'ok.gguf');
  await downloadFile(`${baseUrl}/model.gguf`, dest, undefined, { sha256: GOOD_SHA });
  assert.equal(fs.existsSync(dest), true);
  assert.equal(sha256File(dest), GOOD_SHA);
});

test('a digest mismatch REJECTS and never publishes the file', async () => {
  const dest = path.join(tmpDir, 'bad.gguf');
  await assert.rejects(
    () => downloadFile(`${baseUrl}/model.gguf`, dest, undefined, { sha256: WRONG_SHA }),
    /checksum mismatch/
  );
  assert.equal(fs.existsSync(dest), false, 'the corrupt file must not be published');
});

test('a failed digest also deletes the .part, so a retry cannot "resume" bad bytes', async () => {
  const dest = path.join(tmpDir, 'bad2.gguf');
  await assert.rejects(() => downloadFile(`${baseUrl}/model.gguf`, dest, undefined, { sha256: WRONG_SHA }));
  assert.equal(fs.existsSync(dest + '.part'), false, 'the .part must be removed');
  // …and the same URL downloads cleanly once the expected digest is right.
  await downloadFile(`${baseUrl}/model.gguf`, dest, undefined, { sha256: GOOD_SHA });
  assert.equal(sha256File(dest), GOOD_SHA);
});

test('no digest supplied means no integrity gate (back-compat)', async () => {
  const dest = path.join(tmpDir, 'nosha.gguf');
  await downloadFile(`${baseUrl}/model.gguf`, dest);
  assert.equal(fs.existsSync(dest), true);
});

test('digest comparison is case-insensitive', async () => {
  const dest = path.join(tmpDir, 'upper.gguf');
  await downloadFile(`${baseUrl}/model.gguf`, dest, undefined, { sha256: GOOD_SHA.toUpperCase() });
  assert.equal(fs.existsSync(dest), true);
});

// --- assertEnoughSpace -------------------------------------------------------

test('assertEnoughSpace allows a download that obviously fits', () => {
  assert.doesNotThrow(() => assertEnoughSpace(1024, tmpDir));
});

test('assertEnoughSpace throws a legible error when the file cannot fit', () => {
  // 1 PB will not fit on any test machine.
  assert.throws(() => assertEnoughSpace(1e15, tmpDir), /not enough disk space/);
});

test('assertEnoughSpace is a no-op for unknown or zero sizes', () => {
  // A server that sends no content-length yields 0 — never block on that.
  assert.doesNotThrow(() => assertEnoughSpace(0, tmpDir));
  assert.doesNotThrow(() => assertEnoughSpace(NaN, tmpDir));
  assert.doesNotThrow(() => assertEnoughSpace(-5, tmpDir));
});

test('assertEnoughSpace works for a directory that does not exist yet', () => {
  // resolveModel checks capacity before creating the per-model directory.
  const missing = path.join(tmpDir, 'not', 'created', 'yet');
  assert.doesNotThrow(() => assertEnoughSpace(1024, missing));
  assert.throws(() => assertEnoughSpace(1e15, missing), /not enough disk space/);
});

test('a download refuses to start when the volume cannot hold it', async () => {
  // Serve a content-length far larger than any disk; the guard must fire before
  // we stream a single byte to disk.
  const big = http.createServer((_req, res) => {
    res.writeHead(200, { 'content-length': String(1e15) });
    res.write('x');
  });
  await new Promise((r) => big.listen(0, '127.0.0.1', r));
  const url = `http://127.0.0.1:${big.address().port}/huge.gguf`;
  const dest = path.join(tmpDir, 'huge.gguf');
  try {
    await assert.rejects(() => downloadFile(url, dest), /not enough disk space/);
    assert.equal(fs.existsSync(dest), false);
  } finally {
    // The response was never finished, so a live socket would keep close()
    // waiting for the full server timeout.
    big.closeAllConnections();
    await new Promise((r) => big.close(r));
  }
});
