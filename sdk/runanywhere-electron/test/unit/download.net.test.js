const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');

const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { downloadFile } = require('../../dist/download');

// A known, non-trivial body: 'hello world' repeated so we exercise multiple
// data chunks / a Content-Length larger than a single write.
const BODY = 'hello world\n'.repeat(1000); // 12000 bytes
const BODY_LEN = Buffer.byteLength(BODY);

let server;      // shared in-process HTTP server (127.0.0.1, ephemeral port)
let baseUrl;     // e.g. 'http://127.0.0.1:53421'
let tmpDir;      // fresh temp dir for all downloaded files

// Build a URL against the running local server for a given path.
function url(p) {
  return baseUrl + p;
}

// Fresh dest path inside the temp dir (distinct per name so tests don't collide).
function destFor(name) {
  return path.join(tmpDir, name);
}

before(async () => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'ra-dl-'));

  server = http.createServer((req, res) => {
    const u = req.url || '/';

    // Always-redirects-to-itself: exercises the >6 redirect guard.
    if (u === '/loop') {
      res.writeHead(302, { Location: '/loop' });
      res.end();
      return;
    }

    // One-hop redirect to a real body.
    if (u === '/redirect') {
      res.writeHead(302, { Location: '/final' });
      res.end();
      return;
    }

    if (u === '/final') {
      res.writeHead(200, {
        'Content-Type': 'text/plain',
        'Content-Length': String(BODY_LEN),
      });
      res.end(BODY);
      return;
    }

    // Missing Content-Length: send chunked so total stays 0 but bytes are whole.
    if (u === '/no-length') {
      res.writeHead(200, { 'Content-Type': 'text/plain' }); // no Content-Length
      // Write in two pieces to make it genuinely chunked/streamed.
      res.write(BODY.slice(0, 100));
      res.end(BODY.slice(100));
      return;
    }

    if (u === '/notfound') {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('nope');
      return;
    }

    // Default happy path: 200 + Content-Length + known body.
    if (u === '/ok' || u === '/ok2') {
      res.writeHead(200, {
        'Content-Type': 'text/plain',
        'Content-Length': String(BODY_LEN),
      });
      res.end(BODY);
      return;
    }

    res.writeHead(404);
    res.end('unknown route');
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  baseUrl = `http://127.0.0.1:${port}`;
});

after(async () => {
  if (server) {
    await new Promise((resolve) => server.close(resolve));
  }
  if (tmpDir) {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});

// --- happy path --------------------------------------------------------------

test('happy path: downloads exact bytes, reports 100% progress, no .part left', async () => {
  const dest = destFor('ok.bin');
  const progress = [];

  await downloadFile(url('/ok'), dest, (p) => progress.push(p));

  // File exists with EXACTLY the served bytes.
  assert.ok(fs.existsSync(dest), 'dest file must exist');
  assert.equal(fs.readFileSync(dest, 'utf8'), BODY);
  assert.equal(fs.statSync(dest).size, BODY_LEN);

  // Progress fired at least once, and the last call is a complete download.
  assert.ok(progress.length >= 1, 'onProgress must be called at least once');
  const last = progress[progress.length - 1];
  assert.equal(last.file, 'ok.bin', 'progress.file is the dest basename');
  assert.equal(last.percent, 100);
  assert.equal(last.received, BODY_LEN);
  assert.equal(last.total, BODY_LEN);
  assert.equal(last.received, last.total);

  // No leftover .part temp file.
  assert.ok(!fs.existsSync(dest + '.part'), 'the .part temp file must be gone after rename');
});

test('happy path: resolves undefined (Promise<void>)', async () => {
  const dest = destFor('ok-void.bin');
  const result = await downloadFile(url('/ok'), dest);
  assert.equal(result, undefined);
  assert.equal(fs.readFileSync(dest, 'utf8'), BODY);
});

// --- redirect ----------------------------------------------------------------

test('redirect: follows a 302 to the final body', async () => {
  const dest = destFor('redirected.bin');

  await downloadFile(url('/redirect'), dest);

  assert.ok(fs.existsSync(dest), 'final file must exist after following the redirect');
  assert.equal(fs.readFileSync(dest, 'utf8'), BODY);
  assert.ok(!fs.existsSync(dest + '.part'), 'no .part left after a redirected download');
});

// --- too many redirects ------------------------------------------------------

test('too many redirects: rejects with /too many redirects/', async () => {
  const dest = destFor('loop.bin');

  await assert.rejects(
    () => downloadFile(url('/loop'), dest),
    /too many redirects/
  );

  // Nothing should have been written for a redirect loop.
  assert.ok(!fs.existsSync(dest), 'no dest file for a redirect loop');
  assert.ok(!fs.existsSync(dest + '.part'), 'no .part for a redirect loop');
});

// --- non-200 -----------------------------------------------------------------

test('non-200: rejects with a message containing HTTP 404', async () => {
  const dest = destFor('notfound.bin');

  await assert.rejects(
    () => downloadFile(url('/notfound'), dest),
    (err) => {
      assert.ok(err instanceof Error);
      assert.match(err.message, /HTTP 404/);
      return true;
    }
  );

  assert.ok(!fs.existsSync(dest), 'no dest file on a 404');
  assert.ok(!fs.existsSync(dest + '.part'), 'no .part on a 404');
});

// --- missing Content-Length (chunked) ---------------------------------------

test('missing Content-Length: still writes the full body (total 0 => percent 0 ok)', async () => {
  const dest = destFor('no-length.bin');
  const progress = [];

  await downloadFile(url('/no-length'), dest, (p) => progress.push(p));

  // Full body written despite no Content-Length header.
  assert.ok(fs.existsSync(dest), 'file must exist');
  assert.equal(fs.readFileSync(dest, 'utf8'), BODY);
  assert.equal(fs.statSync(dest).size, BODY_LEN);
  assert.ok(!fs.existsSync(dest + '.part'), 'no .part after a chunked download');

  // With total unknown, percent is 0 and total is 0 in every reported progress,
  // but received still accumulates the real byte count.
  assert.ok(progress.length >= 1, 'onProgress must be called at least once');
  for (const p of progress) {
    assert.equal(p.total, 0, 'total is 0 when Content-Length is absent');
    assert.equal(p.percent, 0, 'percent is 0 when total is unknown');
  }
  const last = progress[progress.length - 1];
  assert.equal(last.received, BODY_LEN, 'received still reaches the full body length');
});

// --- distinct destinations do not collide -----------------------------------

test('distinct dest paths do not collide', async () => {
  const destA = destFor('collide-a.bin');
  const destB = destFor('collide-b.bin');

  await Promise.all([
    downloadFile(url('/ok'), destA),
    downloadFile(url('/ok2'), destB),
  ]);

  assert.ok(fs.existsSync(destA));
  assert.ok(fs.existsSync(destB));
  assert.equal(fs.readFileSync(destA, 'utf8'), BODY);
  assert.equal(fs.readFileSync(destB, 'utf8'), BODY);
  assert.notEqual(destA, destB);
  assert.ok(!fs.existsSync(destA + '.part'));
  assert.ok(!fs.existsSync(destB + '.part'));
});
