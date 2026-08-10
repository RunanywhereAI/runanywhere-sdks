// F18 + F19 — the commons download orchestrator and storage analyzer, against
// the real addon.
//
// The bytes come from a localhost HTTP server rather than a real model host: a
// multi-GB catalog entry proves nothing extra about plan/start/pause/resume and
// makes the run untestable offline. The server is real HTTP — commons fetches it
// through the registered libcurl transport, honours Range on resume, and
// verifies the checksum itself — so nothing about the SDK path is stubbed.
//
// Everything runs against a throwaway base directory, so this file never reads
// or deletes anything in the developer's ~/.runanywhere model store.

const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');

const NATIVE_PATH = process.env.RUNANYWHERE_NATIVE_PATH;
const SKIP = NATIVE_PATH && fs.existsSync(NATIVE_PATH)
  ? {}
  : { skip: 'RUNANYWHERE_NATIVE_PATH unset or file missing' };

// Big enough that the transfer spans many chunks (so progress events are real
// events and not one terminal callback), small enough to finish in under a
// second on loopback.
const BODY = crypto.randomBytes(4 * 1024 * 1024);
const BODY_SHA256 = crypto.createHash('sha256').update(BODY).digest('hex');

const BASE_DIR = fs.mkdtempSync(path.join(os.tmpdir(), 'ra-download-'));

/**
 * A model host that honours HEAD (commons probes Content-Length before it
 * plans), serves ranged GETs, and records what it was asked for so a resume can
 * be asserted from the wire rather than from a log line.
 */
function startServer() {
  const requests = [];
  const server = http.createServer((req, res) => {
    requests.push({ method: req.method, url: req.url, range: req.headers.range });
    if (req.method === 'HEAD') {
      res.writeHead(200, { 'Content-Length': String(BODY.length), 'Accept-Ranges': 'bytes' });
      res.end();
      return;
    }
    const match = /^bytes=(\d+)-/.exec(req.headers.range ?? '');
    const start = match ? Number(match[1]) : 0;
    if (start >= BODY.length) {
      res.writeHead(416, { 'Content-Range': `bytes */${BODY.length}` });
      res.end();
      return;
    }
    const body = BODY.subarray(start);
    res.writeHead(start > 0 ? 206 : 200, {
      'Content-Length': String(body.length),
      'Accept-Ranges': 'bytes',
      ...(start > 0 ? { 'Content-Range': `bytes ${start}-${BODY.length - 1}/${BODY.length}` } : {}),
    });
    // Trickle the body so a pause has somewhere to land mid-transfer.
    const CHUNK = 64 * 1024;
    let offset = 0;
    const pump = () => {
      if (offset >= body.length) {
        res.end();
        return;
      }
      res.write(body.subarray(offset, offset + CHUNK));
      offset += CHUNK;
      setTimeout(pump, 4);
    };
    pump();
  });
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      resolve({
        url: (name) => `http://127.0.0.1:${port}/${name}`,
        requests,
        close: () => new Promise((done) => server.close(done)),
      });
    });
  });
}

let sdkPromise = null;
function sdk() {
  if (!sdkPromise) {
    sdkPromise = (async () => {
      const { createRunAnywhere, NativeBackend, clearCatalog } = require('../../dist');
      const { addon } = require('../../dist/bridge');
      clearCatalog();
      const instance = createRunAnywhere(new NativeBackend(addon));
      await instance.initialize({ environment: 'production', baseDir: BASE_DIR });
      return instance;
    })();
  }
  return sdkPromise;
}

async function registerModel(ra, id, url) {
  return ra.models.register({
    id,
    name: id,
    url,
    category: 'LANGUAGE',
    framework: 'LLAMA_CPP',
  });
}

async function drain(stream) {
  const events = [];
  for await (const event of stream) events.push(event);
  return events;
}

test(
  'download: commons streams progress and lands a complete, verified file',
  { timeout: 120000, ...SKIP },
  async () => {
    const server = await startServer();
    try {
      const ra = await sdk();
      const id = 'dl-complete';
      await registerModel(ra, id, server.url('model.gguf'));

      const events = await drain(ra.models.download(id));
      const progress = events.filter((e) => e.type === 'progress');
      const completed = events.find((e) => e.type === 'completed');

      assert.ok(progress.length > 0, 'the download reported progress, not just a terminal event');
      assert.ok(
        progress.some((e) => e.bytesDone > 0 && e.bytesDone < BODY.length),
        'at least one progress event landed mid-transfer'
      );
      assert.equal(progress.at(-1).bytesTotal, BODY.length, 'the total is the real content length');
      assert.ok(completed, 'the stream ended with a completed event');

      // The registry, not a filesystem walk, is what says the model is here.
      const row = await ra.models.get(id);
      assert.ok(row.downloaded, 'the registry row is marked downloaded');
      assert.ok(row.localPath, 'the registry row carries the path commons wrote to');
      assert.ok(fs.existsSync(row.localPath), `${row.localPath} exists on disk`);
      assert.equal(fs.statSync(row.localPath).size, BODY.length, 'every byte landed');
      assert.equal(
        crypto.createHash('sha256').update(fs.readFileSync(row.localPath)).digest('hex'),
        BODY_SHA256,
        'the bytes on disk are the bytes the server served'
      );

      // Downloading again must not refetch. commons plans into its own model
      // folder with no already-downloaded short circuit, so the SDK owns this.
      const getsBefore = server.requests.filter((r) => r.method === 'GET').length;
      const again = await drain(ra.models.download(id));
      assert.ok(again.some((e) => e.type === 'completed'), 'a second download completes at once');
      assert.equal(
        server.requests.filter((r) => r.method === 'GET').length,
        getsBefore,
        'a model already on disk is not fetched again'
      );
    } finally {
      await server.close();
    }
  }
);

test(
  'download: pause keeps the partial bytes and resume asks the server for the rest',
  { timeout: 120000, ...SKIP },
  async () => {
    const server = await startServer();
    try {
      const ra = await sdk();
      const id = 'dl-resume';
      await registerModel(ra, id, server.url('resume.gguf'));

      // Pause as soon as the transfer is genuinely under way but nowhere near
      // done, so the resume has a real offset to carry.
      let pausedAt = 0;
      const stream = ra.models.download(id);
      for await (const event of stream) {
        if (event.type === 'progress' && event.bytesDone > 0 && !pausedAt) {
          pausedAt = event.bytesDone;
          await ra.models.pause(id);
        }
      }
      assert.ok(pausedAt > 0, 'the download was paused after some bytes had landed');

      const paused = await ra.models.interrupted();
      assert.ok(paused.includes(id), 'the persisted task table remembers the paused download');

      const before = server.requests.filter((r) => r.method === 'GET').length;
      const events = await drain(ra.models.download(id));
      const gets = server.requests.filter((r) => r.method === 'GET');
      assert.ok(gets.length > before, 'resuming issued a new GET');

      const resumeRequest = gets.at(-1);
      assert.match(
        resumeRequest.range ?? '',
        /^bytes=\d+-$/,
        'the resume GET carried a Range header'
      );
      const resumeFrom = Number(/^bytes=(\d+)-$/.exec(resumeRequest.range)[1]);
      assert.ok(resumeFrom > 0, 'the resume started past byte zero');
      assert.ok(
        resumeFrom <= BODY.length,
        `the resume offset ${resumeFrom} is inside the file`
      );

      assert.ok(events.some((e) => e.type === 'completed'), 'the resumed download completed');
      const row = await ra.models.get(id);
      assert.equal(fs.statSync(row.localPath).size, BODY.length, 'the resumed file is whole');
      assert.equal(
        crypto.createHash('sha256').update(fs.readFileSync(row.localPath)).digest('hex'),
        BODY_SHA256,
        'resuming produced the same bytes as a fresh download, not a spliced file'
      );
      assert.ok(
        !(await ra.models.interrupted()).includes(id),
        'the task table forgot the download once it finished'
      );
    } finally {
      await server.close();
    }
  }
);

test(
  'download: cancel stops the transfer, discards the partial, and clears the task',
  { timeout: 120000, ...SKIP },
  async () => {
    const server = await startServer();
    try {
      const ra = await sdk();
      const id = 'dl-cancel';
      await registerModel(ra, id, server.url('cancel.gguf'));

      let cancelled = false;
      for await (const event of ra.models.download(id)) {
        if (event.type === 'progress' && event.bytesDone > 0 && !cancelled) {
          cancelled = true;
          await ra.models.cancel(id);
        }
        assert.notEqual(event.type, 'completed', 'a cancelled download never completes');
      }
      assert.ok(cancelled, 'the download was cancelled mid-transfer');

      const row = await ra.models.get(id);
      assert.ok(!row.downloaded, 'a cancelled download leaves the row not downloaded');
      assert.ok(
        !(await ra.models.interrupted()).includes(id),
        'cancel dropped the persisted task'
      );
    } finally {
      await server.close();
    }
  }
);

test(
  'download: a checksum that does not match the bytes fails the download',
  { timeout: 120000, ...SKIP },
  async () => {
    const server = await startServer();
    try {
      const ra = await sdk();
      const { NativeBackend } = require('../../dist');
      const { addon } = require('../../dist/bridge');
      const { DownloadAbi, isTerminalState } = require('../../dist/api/download-abi');
      const {
        DownloadPlanRequest,
        DownloadStartRequest,
        DownloadState,
        DownloadSubscribeRequest,
      } = require('../../dist/proto/download_service');
      const { InferenceFramework, ModelCategory, ModelFormat } =
        require('../../dist/proto/model_types');

      // The public registration surface carries no checksum field, so the wrong
      // digest is put on the ModelInfo the plan is built from. That is the same
      // message commons would get from a catalog that shipped a bad checksum.
      const id = 'dl-checksum';
      await registerModel(ra, id, server.url('checksum.gguf'));

      const downloads = new DownloadAbi(new NativeBackend(addon));
      const plan = await downloads.plan(
        DownloadPlanRequest.fromPartial({
          modelId: id,
          model: {
            id,
            name: id,
            downloadUrl: server.url('checksum.gguf'),
            framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
            category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
            format: ModelFormat.MODEL_FORMAT_GGUF,
            checksumSha256: 'f'.repeat(64),
          },
        })
      );
      assert.ok(plan.canStart, 'a plan with a checksum still starts');
      assert.equal(plan.files[0].checksumSha256, 'f'.repeat(64), 'the checksum reached the plan');

      const started = await downloads.start(
        DownloadStartRequest.fromPartial({ modelId: id, plan })
      );
      assert.ok(started.accepted, 'the download started');

      const request = DownloadSubscribeRequest.fromPartial({
        modelId: id,
        taskId: started.taskId,
      });
      let last = null;
      const deadline = Date.now() + 60000;
      while (Date.now() < deadline) {
        last = await downloads.poll(request);
        if (isTerminalState(last.state)) break;
        await new Promise((r) => setTimeout(r, 50));
      }
      assert.equal(
        last.state,
        DownloadState.DOWNLOAD_STATE_FAILED,
        'a mismatched checksum fails the download instead of accepting the bytes'
      );
      await downloads.cleanup();

      const row = await ra.models.get(id);
      assert.ok(!row.downloaded, 'a failed checksum leaves the model not downloaded');
    } finally {
      await server.close();
    }
  }
);

test(
  'storage: the analyzer counts the downloaded bytes and delete gives them back',
  { timeout: 120000, ...SKIP },
  async () => {
    const server = await startServer();
    try {
      const ra = await sdk();
      const id = 'dl-storage';
      await registerModel(ra, id, server.url('storage.gguf'));

      const before = await ra.models.state();
      assert.ok(before.storageFreeBytes > 0, 'the analyzer reports real free space');

      await drain(ra.models.download(id));
      const row = await ra.models.get(id);

      const after = await ra.models.state();
      assert.ok(
        after.storageUsedBytes - before.storageUsedBytes >= BODY.length,
        `used bytes grew by at least the file (${before.storageUsedBytes} -> ${after.storageUsedBytes})`
      );

      await ra.models.delete(id);
      assert.equal(await ra.models.get(id), null, 'the registry row is gone');
      assert.ok(!fs.existsSync(row.localPath), `${row.localPath} was removed from disk`);

      const reclaimed = await ra.models.state();
      assert.ok(
        reclaimed.storageUsedBytes <= after.storageUsedBytes - BODY.length,
        `used bytes fell back after the delete (${after.storageUsedBytes} -> ${reclaimed.storageUsedBytes})`
      );
    } finally {
      await server.close();
    }
  }
);

test.after(async () => {
  if (SKIP.skip) return;
  const ra = await sdk();
  await ra.reset();
  fs.rmSync(BASE_DIR, { recursive: true, force: true });
});
