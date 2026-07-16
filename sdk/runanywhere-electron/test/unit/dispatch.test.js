const { test } = require('node:test');
const assert = require('node:assert/strict');
const os = require('os');
const path = require('path');

const { dispatch } = require('../../dist/process/dispatch');
const { STREAMING_METHODS } = require('../../dist/process/rpc');

// A fake port that records every posted message.
function makePort() {
  const posts = [];
  return {
    posts,
    postMessage(m) {
      posts.push(m);
    },
  };
}

// Wait one macrotask tick so async .then/.catch chains flush.
const tick = () => new Promise((r) => setImmediate(r));

// A baseline deps object; individual tests override the pieces they exercise.
function makeDeps(overrides = {}) {
  return {
    api: {},
    getVersion: () => 'v1.2.3',
    resolveLoadArgs: async (_method, args) => args,
    ...overrides,
  };
}

// ---- STREAMING ----------------------------------------------------------

test('streaming method injects onToken and posts token, token, done in order', async () => {
  const port = makePort();
  let sawArgs = null;
  const deps = makeDeps({
    api: {
      generate: (...allArgs) => {
        sawArgs = allArgs;
        const onToken = allArgs[allArgs.length - 1];
        onToken('a');
        onToken('b');
        return Promise.resolve();
      },
    },
  });

  dispatch(port, { id: 7, method: 'generate', args: ['prompt', { opt: 1 }] }, deps);
  await tick();

  assert.deepEqual(port.posts, [
    { id: 7, token: 'a' },
    { id: 7, token: 'b' },
    { id: 7, done: true },
  ]);

  // The injected onToken must be the LAST arg, appended after the caller's args.
  assert.equal(sawArgs.length, 3);
  assert.equal(sawArgs[0], 'prompt');
  assert.deepEqual(sawArgs[1], { opt: 1 });
  assert.equal(typeof sawArgs[sawArgs.length - 1], 'function');
});

test('streaming method whose promise rejects posts {ok:false,error} and no done', async () => {
  const port = makePort();
  const deps = makeDeps({
    api: {
      generate: () => Promise.reject(new Error('boom-stream')),
    },
  });

  dispatch(port, { id: 11, method: 'generate', args: [] }, deps);
  await tick();

  assert.deepEqual(port.posts, [{ id: 11, ok: false, error: 'boom-stream' }]);
  assert.equal(
    port.posts.some((m) => m.done === true),
    false
  );
});

// ---- VERSION ------------------------------------------------------------

test('version method uses getVersion and does not consult api', async () => {
  const port = makePort();
  let apiCalled = false;
  const deps = makeDeps({
    getVersion: () => 'v1.2.3',
    api: {
      version: () => {
        apiCalled = true;
        return 'should-not-be-used';
      },
    },
  });

  dispatch(port, { id: 3, method: 'version', args: [] }, deps);
  await tick();

  assert.deepEqual(port.posts, [{ id: 3, ok: true, result: 'v1.2.3' }]);
  assert.equal(apiCalled, false);
});

// ---- INITIALIZE ---------------------------------------------------------

test('initialize with explicit [secure, base] calls api.initialize(secure, base)', async () => {
  const port = makePort();
  let sawArgs = null;
  const deps = makeDeps({
    api: {
      initialize: (...a) => {
        sawArgs = a;
      },
    },
  });

  dispatch(port, { id: 42, method: 'initialize', args: ['/sec', '/base'] }, deps);
  await tick();

  assert.deepEqual(sawArgs, ['/sec', '/base']);
  assert.deepEqual(port.posts, [{ id: 42, ok: true }]);
});

test('initialize with [] defaults base and secure from os.homedir()', async () => {
  const port = makePort();
  let sawArgs = null;
  const deps = makeDeps({
    api: {
      initialize: (...a) => {
        sawArgs = a;
      },
    },
  });

  dispatch(port, { id: 43, method: 'initialize', args: [] }, deps);
  await tick();

  const expectedBase = path.join(os.homedir(), '.runanywhere');
  const expectedSecure = path.join(expectedBase, 'secure');
  // api.initialize is called (secure, base)
  assert.deepEqual(sawArgs, [expectedSecure, expectedBase]);
  assert.deepEqual(port.posts, [{ id: 43, ok: true }]);
});

// ---- LOAD ---------------------------------------------------------------

test('load method resolves args, calls api with resolved args, posts result', async () => {
  const port = makePort();
  let resolveInput = null;
  let apiInput = null;
  const deps = makeDeps({
    resolveLoadArgs: async (method, args) => {
      resolveInput = { method, args };
      return ['/resolved/path', 'extra'];
    },
    api: {
      loadModel: (...a) => {
        apiInput = a;
        return { handle: 99 };
      },
    },
  });

  dispatch(port, { id: 5, method: 'loadModel', args: ['catalog-id'] }, deps);
  await tick();

  assert.deepEqual(resolveInput, { method: 'loadModel', args: ['catalog-id'] });
  assert.deepEqual(apiInput, ['/resolved/path', 'extra']);
  assert.deepEqual(port.posts, [{ id: 5, ok: true, result: { handle: 99 } }]);
});

test('load method where resolveLoadArgs rejects posts {ok:false,error}', async () => {
  const port = makePort();
  let apiCalled = false;
  const deps = makeDeps({
    resolveLoadArgs: async () => {
      throw new Error('resolve-failed');
    },
    api: {
      loadModel: () => {
        apiCalled = true;
        return null;
      },
    },
  });

  dispatch(port, { id: 8, method: 'loadModel', args: [] }, deps);
  await tick();

  assert.deepEqual(port.posts, [{ id: 8, ok: false, error: 'resolve-failed' }]);
  assert.equal(apiCalled, false);
});

test('load method where api throws after resolve posts {ok:false,error}', async () => {
  const port = makePort();
  const deps = makeDeps({
    resolveLoadArgs: async (_m, args) => args,
    api: {
      loadModel: () => {
        throw new Error('load-boom');
      },
    },
  });

  dispatch(port, { id: 9, method: 'loadModel', args: ['x'] }, deps);
  await tick();

  assert.deepEqual(port.posts, [{ id: 9, ok: false, error: 'load-boom' }]);
});

// ---- PLAIN UNARY --------------------------------------------------------

test('plain unary method calls api with args and posts result', async () => {
  const port = makePort();
  let sawArgs = null;
  const deps = makeDeps({
    api: {
      embed: (...a) => {
        sawArgs = a;
        return [0.1, 0.2, 0.3];
      },
    },
  });

  dispatch(port, { id: 1, method: 'embed', args: ['hello', 5] }, deps);
  await tick();

  assert.deepEqual(sawArgs, ['hello', 5]);
  assert.deepEqual(port.posts, [{ id: 1, ok: true, result: [0.1, 0.2, 0.3] }]);
});

test('plain unary method that throws synchronously posts {ok:false,error}', async () => {
  const port = makePort();
  const deps = makeDeps({
    api: {
      embed: () => {
        throw new Error('sync-boom');
      },
    },
  });

  dispatch(port, { id: 2, method: 'embed', args: [] }, deps);
  await tick();

  assert.deepEqual(port.posts, [{ id: 2, ok: false, error: 'sync-boom' }]);
});

// ---- ERROR MESSAGE EXTRACTION ------------------------------------------

test('an Error thrown is posted as its .message', async () => {
  const port = makePort();
  const deps = makeDeps({
    api: {
      embed: () => {
        throw new Error('the-message');
      },
    },
  });

  dispatch(port, { id: 20, method: 'embed', args: [] }, deps);
  await tick();

  assert.deepEqual(port.posts, [{ id: 20, ok: false, error: 'the-message' }]);
});

test('a non-Error thrown value is String()-ified', async () => {
  const port = makePort();
  const deps = makeDeps({
    api: {
      embed: () => {
        // eslint-disable-next-line no-throw-literal
        throw 'plain-string-error';
      },
    },
  });

  dispatch(port, { id: 21, method: 'embed', args: [] }, deps);
  await tick();

  assert.deepEqual(port.posts, [{ id: 21, ok: false, error: 'plain-string-error' }]);
});

test('a non-Error object thrown is String()-ified via its toString', async () => {
  const port = makePort();
  const deps = makeDeps({
    api: {
      embed: () => {
        // eslint-disable-next-line no-throw-literal
        throw { toString: () => 'obj-stringified' };
      },
    },
  });

  dispatch(port, { id: 22, method: 'embed', args: [] }, deps);
  await tick();

  assert.deepEqual(port.posts, [{ id: 22, ok: false, error: 'obj-stringified' }]);
});

// ---- ID ECHO ------------------------------------------------------------

test('the id from req is echoed on every posted message', async () => {
  // Streaming path: multiple messages, all must carry the same id.
  const port = makePort();
  const deps = makeDeps({
    api: {
      generate: (...a) => {
        const onToken = a[a.length - 1];
        onToken('t');
        return Promise.resolve();
      },
    },
  });

  const REQ_ID = 123456;
  dispatch(port, { id: REQ_ID, method: 'generate', args: [] }, deps);
  await tick();

  assert.ok(port.posts.length >= 2);
  for (const m of port.posts) {
    assert.equal(m.id, REQ_ID);
  }
});

// ---- STREAMING_METHODS membership --------------------------------------

test('STREAMING_METHODS contains generate and generateVlm, not embed/loadModel', () => {
  assert.equal(STREAMING_METHODS.has('generate'), true);
  assert.equal(STREAMING_METHODS.has('generateVlm'), true);
  assert.equal(STREAMING_METHODS.has('embed'), false);
  assert.equal(STREAMING_METHODS.has('loadModel'), false);
});
