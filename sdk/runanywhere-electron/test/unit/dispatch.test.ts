import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as os from 'os';
import * as path from 'path';

import { dispatch, ALLOWED_RPC_METHODS, DuplexCalls } from '../../dist/process/dispatch';
import type { DispatchDeps, DispatchPort } from '../../dist/process/dispatch';
import { STREAMING_METHODS } from '../../dist/process/rpc';
import { BACKEND_METHODS, rpcMethodFor } from '../../dist/api/backend';

/** Every message a posted reply can carry, read back by field in the assertions. */
interface PostedMessage {
  id: number;
  token?: unknown;
  done?: true;
  ok?: boolean;
  result?: unknown;
  error?: unknown;
  call?: { seq: number; event: unknown };
}

/** A fake port that records every posted message. */
interface RecordingPort extends DispatchPort {
  posts: PostedMessage[];
}

// A fake port that records every posted message.
function makePort(): RecordingPort {
  const posts: PostedMessage[] = [];
  return {
    posts,
    postMessage(m: unknown) {
      posts.push(m as PostedMessage);
    },
  };
}

// Wait one macrotask tick so async .then/.catch chains flush.
const tick = (): Promise<void> => new Promise((r) => setImmediate(r));

/**
 * A baseline deps object; individual tests override the pieces they exercise.
 *
 * The routing tests below drive dispatch with bare addon-shaped names
 * (`generate`, `loadModel`, `initialize`) because those are what exercise the
 * streaming / load / unary branches. Those names are deliberately NOT in the
 * production {@link ALLOWED_RPC_METHODS} any more — see the security tests at the
 * bottom of this file — so an explicit `allowedMethods` is injected here.
 *
 * That is what the override exists for: these tests are about dispatch's
 * ROUTING, and the allowlist is a separate property tested separately. Injecting
 * it keeps a routing test from silently doubling as an allowlist test.
 */
function makeDeps(overrides: Partial<DispatchDeps> = {}): DispatchDeps {
  const api = overrides.api ?? {};
  return {
    api,
    getVersion: () => 'v1.2.3',
    resolveLoadArgs: async (_method, args) => args,
    // Allow exactly the names this test's fake api implements, plus the two
    // dispatch special-cases, so routing can be exercised without widening the
    // real allowlist.
    allowedMethods: new Set([...Object.keys(api), 'version', 'initialize']),
    ...overrides,
  };
}

// ---- STREAMING ----------------------------------------------------------

test('streaming method injects onToken and posts token, token, done in order', async () => {
  const port = makePort();
  let sawArgs: unknown[] | null = null;
  const deps = makeDeps({
    api: {
      generate: (...allArgs: unknown[]) => {
        sawArgs = allArgs;
        const onToken = allArgs[allArgs.length - 1] as (t: string) => void;
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
  assert.ok(sawArgs, 'the api method was called');
  const args: unknown[] = sawArgs;
  assert.equal(args.length, 3);
  assert.equal(args[0], 'prompt');
  assert.deepEqual(args[1], { opt: 1 });
  assert.equal(typeof args[args.length - 1], 'function');
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

  // Read the `done` invariant first: assert.deepEqual is a type assertion, so it
  // narrows `port.posts` to the literal shape and hides the optional fields.
  assert.equal(
    port.posts.some((m) => m.done === true),
    false
  );
  assert.deepEqual(port.posts, [
    { id: 11, ok: false, error: { name: 'Error', message: 'boom-stream' } },
  ]);
});

test('streaming method that resolves a value carries it on the done message', async () => {
  const port = makePort();
  const resolved = { id: 'hf-x', dir: '/models/hf-x', primary: '/models/hf-x/model.gguf' };
  const deps = makeDeps({
    streamingMethods: new Set(['downloadModel']),
    api: {
      downloadModel: (...allArgs: unknown[]) => {
        const onProgress = allArgs[allArgs.length - 1] as (p: unknown) => void;
        onProgress({ percent: 100 });
        return Promise.resolve(resolved);
      },
    },
  });

  dispatch(port, { id: 21, method: 'downloadModel', args: ['owner/repo'] }, deps);
  await tick();

  assert.deepEqual(port.posts, [
    { id: 21, token: { percent: 100 } },
    { id: 21, done: true, result: resolved },
  ]);
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
  let sawArgs: unknown[] | null = null;
  const deps = makeDeps({
    api: {
      initialize: (...a: unknown[]) => {
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
  let sawArgs: unknown[] | null = null;
  const deps = makeDeps({
    api: {
      initialize: (...a: unknown[]) => {
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
  let resolveInput: { method: string; args: unknown[] } | null = null;
  let apiInput: unknown[] | null = null;
  const deps = makeDeps({
    resolveLoadArgs: async (method, args) => {
      resolveInput = { method, args };
      return ['/resolved/path', 'extra'];
    },
    api: {
      loadModel: (...a: unknown[]) => {
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

  assert.deepEqual(port.posts, [
    { id: 8, ok: false, error: { name: 'Error', message: 'resolve-failed' } },
  ]);
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

  assert.deepEqual(port.posts, [
    { id: 9, ok: false, error: { name: 'Error', message: 'load-boom' } },
  ]);
});

// ---- PLAIN UNARY --------------------------------------------------------

test('plain unary method calls api with args and posts result', async () => {
  const port = makePort();
  let sawArgs: unknown[] | null = null;
  const deps = makeDeps({
    api: {
      embed: (...a: unknown[]) => {
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

  assert.deepEqual(port.posts, [
    { id: 2, ok: false, error: { name: 'Error', message: 'sync-boom' } },
  ]);
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

  assert.deepEqual(port.posts, [
    { id: 20, ok: false, error: { name: 'Error', message: 'the-message' } },
  ]);
});

test('a structured native Error keeps numeric SDK fields over RPC', async () => {
  const port = makePort();
  // The addon decorates its Errors with the rac_result_t it failed on; the
  // fields are attached the same way native does, not declared on Error.
  const err = Object.assign(new Error('load_model failed: -111'), {
    code: 111,
    cAbiCode: -111,
    category: 3,
  });
  const deps = makeDeps({
    api: {
      embed: () => {
        throw err;
      },
    },
  });

  dispatch(port, { id: 23, method: 'embed', args: [] }, deps);
  await tick();

  assert.deepEqual(port.posts, [
    {
      id: 23,
      ok: false,
      error: {
        name: 'Error',
        message: 'load_model failed: -111',
        code: 111,
        cAbiCode: -111,
        category: 3,
      },
    },
  ]);
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
      generate: (...a: unknown[]) => {
        const onToken = a[a.length - 1] as (t: string) => void;
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

// ---- async (Promise-returning) unary bindings (e.g. ragQuery/ragIngest) --

test('a Promise-returning unary binding is awaited and its resolved value posted', async () => {
  const port = makePort();
  const deps = makeDeps({
    api: {
      ragQuery: async (h: unknown, bytes: unknown) =>
        new Uint8Array([h as number, (bytes as Uint8Array).length, 9]),
    },
  });
  dispatch(port, { id: 40, method: 'ragQuery', args: [3, new Uint8Array([1, 2])] }, deps);
  assert.equal(port.posts.length, 0, 'nothing posted synchronously — the result is awaited');
  await tick();
  assert.equal(port.posts.length, 1);
  assert.equal(port.posts[0].id, 40);
  assert.equal(port.posts[0].ok, true);
  assert.deepEqual(Array.from(port.posts[0].result as Uint8Array), [3, 2, 9]);
});

test('a rejected Promise from a unary binding is posted as an error', async () => {
  const port = makePort();
  const deps = makeDeps({
    api: { ragIngest: async () => { throw new Error('ingest boom'); } },
  });
  dispatch(port, { id: 41, method: 'ragIngest', args: [1, new Uint8Array()] }, deps);
  await tick();
  assert.deepEqual(port.posts, [
    { id: 41, ok: false, error: { name: 'Error', message: 'ingest boom' } },
  ]);
});

test('a synchronous unary binding still posts synchronously (no regression)', () => {
  const port = makePort();
  const deps = makeDeps({ api: { ragStats: () => new Uint8Array([5]) } });
  dispatch(port, { id: 42, method: 'ragStats', args: [1] }, deps);
  // Sync methods must not be deferred to a microtask.
  assert.equal(port.posts.length, 1);
  assert.equal(port.posts[0].ok, true);
  assert.deepEqual(Array.from(port.posts[0].result as Uint8Array), [5]);
});

// ---- STREAMING_METHODS membership --------------------------------------

test('STREAMING_METHODS contains generate and generateVlm, not embed/loadModel', () => {
  assert.equal(STREAMING_METHODS.has('generate'), true);
  assert.equal(STREAMING_METHODS.has('generateVlm'), true);
  assert.equal(STREAMING_METHODS.has('embed'), false);
  assert.equal(STREAMING_METHODS.has('loadModel'), false);
});

// ---- RPC ALLOWLIST ------------------------------------------------------

// ---- ALLOWLIST: the security boundary ------------------------------------
//
// `dispatch` resolves an allowed name straight off `deps.api`, and in `host.ts`
// that object is a Proxy whose fallthrough is the RAW ADDON. So any bare
// addon-shaped name in this set is a lease-less native call reachable by anything
// that can post to the port — bypassing NativeBackend and the `begin_op` lease
// that stops an unload-during-generate use-after-free.
//
// The allowlist therefore carries exactly one bare name (`version`, answered from
// deps.getVersion() without touching `api`) plus the namespaced v3 surface.

test('ALLOWED_RPC_METHODS exposes exactly one bare name, and it reaches no addon', () => {
  const bare = [...ALLOWED_RPC_METHODS].filter((m) => !m.startsWith('v3.'));
  assert.deepEqual(bare, ['version'], 'only `version` may be reachable un-namespaced');
});

test('ALLOWED_RPC_METHODS covers every RaBackend operation, namespaced', () => {
  for (const op of BACKEND_METHODS) {
    assert.equal(
      ALLOWED_RPC_METHODS.has(rpcMethodFor(op)),
      true,
      `expected allowlist to include the namespaced ${rpcMethodFor(op)}`
    );
  }
});

test('bare addon-shaped names are rejected and never reach the addon', async () => {
  // One representative per capability the old allowlist proxied directly.
  const legacy = [
    'initialize',
    'shutdown',
    'secureGet',
    'secureSet',
    'secureDelete',
    'downloadModel',
    'modelStatus',
    'exists',
    'loadModel',
    'generate',
    'unloadModel',
    'loadVlmModel',
    'generateVlm',
    'embed',
    'transcribe',
    'synthesize',
    'createVad',
    'vadProcess',
    'ragCreateSession',
    'ragIngest',
    'ragQuery',
    'ragDestroySession',
    'registerModel',
  ];

  for (const method of legacy) {
    const port = makePort();
    const reached: string[] = [];
    // A Proxy that records ANY property read, the way host.ts's api Proxy would
    // fall through to the addon.
    const api = new Proxy({} as Record<string, (...a: unknown[]) => unknown>, {
      get(_target, prop: string) {
        reached.push(prop);
        return () => 'raw-addon-result';
      },
    });
    dispatch(
      port,
      { id: 1, method, args: [] },
      // The REAL allowlist, not an injected one — that is the point of this test.
      { api, getVersion: () => 'v1.2.3', resolveLoadArgs: async (_m, a) => a }
    );
    await tick();

    assert.equal(ALLOWED_RPC_METHODS.has(method), false, `${method} must not be allowlisted`);
    assert.deepEqual(
      port.posts,
      [{ id: 1, ok: false, error: `unknown RPC method: '${method}'` }],
      `${method} must be rejected`
    );
    assert.deepEqual(reached, [], `${method} must not touch the addon at all`);
  }
});

test('unknown RPC method is rejected before calling api', async () => {
  const port = makePort();
  let apiCalled = false;
  const deps = makeDeps({
    api: new Proxy(
      {} as Record<string, (...a: unknown[]) => unknown>,
      {
        get() {
          apiCalled = true;
          return () => null;
        },
      }
    ),
  });

  dispatch(port, { id: 99, method: '__not_a_real_method__', args: [] }, deps);
  await tick();

  assert.equal(apiCalled, false);
  assert.deepEqual(port.posts, [
    { id: 99, ok: false, error: "unknown RPC method: '__not_a_real_method__'" },
  ]);
});

// ---- DUPLEX (the tool-calling run loop) ---------------------------------

test('duplex method posts each call and resolves it from the client reply', async () => {
  const port = makePort();
  const duplex = new DuplexCalls();
  let answers: unknown[] | null = null;
  const deps = makeDeps({
    duplex,
    api: {
      'v3.toolRunLoop': async (_bytes: unknown, onEvent: unknown) => {
        const ask = onEvent as (e: unknown) => Promise<unknown>;
        answers = [await ask({ handle: 12 }), await ask({ toolCall: 'call-bytes' })];
        return 'result-bytes';
      },
    },
  });

  dispatch(port, { id: 3, method: 'v3.toolRunLoop', args: ['request-bytes'] }, deps);
  await tick();

  assert.deepEqual(port.posts[0], { id: 3, call: { seq: 1, event: { handle: 12 } } });
  duplex.settle({ id: 3, seq: 1, ok: true, result: undefined });
  await tick();

  assert.deepEqual(port.posts[1], { id: 3, call: { seq: 2, event: { toolCall: 'call-bytes' } } });
  duplex.settle({ id: 3, seq: 2, ok: true, result: 'tool-result-bytes' });
  await tick();

  assert.deepEqual(answers, [undefined, 'tool-result-bytes']);
  assert.deepEqual(port.posts[2], { id: 3, ok: true, result: 'result-bytes' });
});

test('a rejected duplex reply surfaces inside the run loop rather than hanging', async () => {
  const port = makePort();
  const duplex = new DuplexCalls();
  let raised: string | null = null;
  const deps = makeDeps({
    duplex,
    api: {
      'v3.toolRunLoop': async (_bytes: unknown, onEvent: unknown) => {
        const ask = onEvent as (e: unknown) => Promise<unknown>;
        try {
          await ask({ toolCall: 'call-bytes' });
        } catch (e: unknown) {
          raised = (e as Error).message;
        }
        return 'result-bytes';
      },
    },
  });

  dispatch(port, { id: 4, method: 'v3.toolRunLoop', args: ['request-bytes'] }, deps);
  await tick();
  duplex.settle({ id: 4, seq: 1, ok: false, error: 'executor blew up' });
  await tick();

  assert.equal(raised, 'executor blew up');
  assert.deepEqual(port.posts[1], { id: 4, ok: true, result: 'result-bytes' });
});

test('a duplex method without a channel fails instead of calling the api', async () => {
  const port = makePort();
  let called = false;
  const deps = makeDeps({ api: { 'v3.toolRunLoop': () => { called = true; } } });

  dispatch(port, { id: 5, method: 'v3.toolRunLoop', args: [] }, deps);
  await tick();

  assert.equal(called, false);
  assert.deepEqual(port.posts, [
    { id: 5, ok: false, error: "no duplex channel for 'v3.toolRunLoop'" },
  ]);
});

test('an unanswered duplex call is failed once its request settles', async () => {
  const port = makePort();
  const duplex = new DuplexCalls();
  let raised: string | null = null;
  const deps = makeDeps({
    duplex,
    api: {
      'v3.toolRunLoop': (_bytes: unknown, onEvent: unknown) => {
        const ask = onEvent as (e: unknown) => Promise<unknown>;
        ask({ toolCall: 'call-bytes' }).catch((e: unknown) => {
          raised = (e as Error).message;
        });
        return Promise.resolve('result-bytes');
      },
    },
  });

  dispatch(port, { id: 6, method: 'v3.toolRunLoop', args: ['request-bytes'] }, deps);
  await tick();
  await tick();
  await tick();

  assert.equal(raised, 'request finished before the executor replied');
});
