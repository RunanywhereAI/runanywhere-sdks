// Unit tests for the renderer preload (src/process/preload.ts): it exposes the
// window.runanywhere API over contextBridge, correlates request/reply by id over
// a MessagePort, routes streamed tokens to onToken callbacks, and gates every
// call on the port handshake. We mock 'electron' (contextBridge + ipcRenderer)
// and drive a fake MessagePort — no real Electron / renderer needed.
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { isSDKException, ErrorCodes } from '../../dist/errors';
import { registerCatalog, clearCatalog } from '../../dist/catalog';

let electronPath: string | null = null;
try {
  electronPath = require.resolve('electron');
} catch {
  /* electron devDep missing */
}
const SKIP = electronPath ? false : 'electron devDependency not installed';
const preloadPath = electronPath ? require.resolve('../../dist/process/preload') : null;

const tick = (): Promise<void> => new Promise((r) => setImmediate(r));

// The preload assembles two objects in the main world. What the page sees is a
// dynamic surface (namespaces plus loose helpers), so it is read through index
// signatures rather than the SDK's own interface — several of the assertions are
// about members that must NOT exist.
type MainWorldApi = Record<string, unknown> & {
  llm: Record<string, unknown> & { tools: Record<string, unknown> };
  models: Record<string, unknown>;
  rag: Record<string, unknown>;
  voice: Record<string, unknown>;
  vad: Record<string, unknown>;
  secure: Record<string, unknown>;
  ready(): Promise<void>;
  version(): Promise<unknown>;
  initialize(secureDir?: string, baseDir?: string): Promise<void>;
  catalog(): Record<string, { type: string }>;
};
interface MainWorldTest {
  done(ok: boolean): void;
  log(line: string): void;
}
interface Exposed {
  runanywhere: MainWorldApi;
  runanywhereTest: MainWorldTest;
}

/** The bridge globals the preload's main-world assembly step reads and writes. */
type BridgeGlobals = typeof globalThis & {
  __runanywhereBridge?: unknown;
  runanywhere?: unknown;
};
const bridgeGlobal = globalThis as BridgeGlobals;

interface FakeState {
  ipcOn: Record<string, ((event: { ports: FakePort[] }) => void) | undefined>;
  ipcSends: Array<{ channel: string; args: unknown[] }>;
  mainWorld: Record<string, unknown>;
}

// The real contextBridge hands the page a FROZEN clone, so the preload assembles
// window.runanywhere in the main world via executeInMainWorld. The fake models
// both halves: exposeInMainWorld freezes what it publishes, and executeInMainWorld
// runs the serialized function against a stand-in main-world global.
function installFakeElectron(): { exposed: Partial<Exposed>; state: FakeState } {
  const exposed: Partial<Exposed> = {};
  const mainWorld: Record<string, unknown> = {};
  const state: FakeState = { ipcOn: {}, ipcSends: [], mainWorld };
  const fakeElectron = {
    contextBridge: {
      exposeInMainWorld(name: string, api: unknown) {
        mainWorld[name] = Object.freeze(api);
      },
      executeInMainWorld({ func, args = [] }: { func: (...a: unknown[]) => unknown; args?: unknown[] }) {
        const saved = bridgeGlobal.__runanywhereBridge;
        bridgeGlobal.__runanywhereBridge = mainWorld.__runanywhereBridge;
        try {
          const ok = func(...args);
          if (bridgeGlobal.runanywhere) mainWorld.runanywhere = bridgeGlobal.runanywhere;
          return ok;
        } finally {
          bridgeGlobal.__runanywhereBridge = saved;
          delete bridgeGlobal.runanywhere;
        }
      },
    },
    ipcRenderer: {
      on(channel: string, cb: (event: { ports: FakePort[] }) => void) {
        state.ipcOn[channel] = cb;
      },
      send(channel: string, ...args: unknown[]) {
        state.ipcSends.push({ channel, args });
      },
    },
  };
  require.cache[electronPath!] = {
    id: electronPath!,
    filename: electronPath!,
    loaded: true,
    exports: fakeElectron,
  } as unknown as NodeModule;
  return { exposed, state };
}

// Re-require the preload fresh so its module-level port/pending/ready reset.
function freshPreload(): { exposed: Exposed; state: FakeState } {
  const { exposed, state } = installFakeElectron();
  delete require.cache[preloadPath!];
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  require(preloadPath!);
  // What the page ends up with is the assembled main-world object.
  exposed.runanywhere = state.mainWorld.runanywhere as MainWorldApi;
  exposed.runanywhereTest = state.mainWorld.runanywhereTest as MainWorldTest;
  return { exposed: exposed as Exposed, state };
}

/** A request posted to the host: the preload's own `{ id, method, args }`. */
interface PostedRequest {
  id: number;
  method: string;
  args: unknown[];
}

/** The MessagePort surface the preload uses, recorded. */
interface FakePort {
  posts: PostedRequest[];
  started: boolean;
  onmessage: ((ev: { data: unknown }) => void) | null;
  onmessageerror?: (() => void) | null;
  postMessage(m: unknown): void;
  start(): void;
  last(): PostedRequest;
}

function fakePort(): FakePort {
  return {
    posts: [],
    started: false,
    onmessage: null,
    postMessage(m: unknown) {
      this.posts.push(m as PostedRequest);
    },
    start() {
      this.started = true;
    },
    last() {
      return this.posts[this.posts.length - 1];
    },
  };
}

// Connect the preload to a port (simulate main delivering it over ipc).
function connect(state: FakeState): FakePort {
  const port = fakePort();
  state.ipcOn['runanywhere-port']!({ ports: [port] });
  return port;
}

// v3 initialize() is a handshake rather than one call: v3.initialize, then
// v3.version, then the secure-store round trip that mints a device id. Answer
// every request as it is posted so the promise can settle.
async function pump(port: FakePort, replies: Record<string, unknown> = {}): Promise<void> {
  let answered = 0;
  for (let i = 0; i < 16; i++) {
    await tick();
    while (answered < port.posts.length) {
      const msg = port.posts[answered++];
      port.onmessage!({
        data: { id: msg.id, ok: true, result: replies[msg.method] },
      });
    }
  }
}

test.afterEach(() => {
  try {
    const { bindAudioBackend, setAudioNativeForTests } = require('../../dist/audio');
    setAudioNativeForTests(null);
    bindAudioBackend(null);
  } catch {
    /* dist may be absent in odd skip paths */
  }
});

test('exposes window.runanywhere as the v3 surface', { skip: SKIP }, () => {
  const { exposed } = freshPreload();
  const api = exposed.runanywhere;
  assert.ok(api, 'runanywhere API exposed');
  // All fourteen namespaces reach the page, so main-process and renderer code is
  // written once against the same shape.
  for (const ns of [
    'llm', 'vlm', 'stt', 'tts', 'vad', 'embeddings', 'rerank', 'images',
    'diarization', 'segmentation', 'voice', 'rag', 'models', 'lora',
  ]) {
    assert.equal(typeof api[ns], 'object', `runanywhere.${ns} namespace exposed`);
  }
  for (const extra of ['secure', 'auth', 'telemetry', 'audio', 'image', 'ragDocument']) {
    assert.equal(typeof api[extra], 'object', `runanywhere.${extra} exposed`);
  }
  for (const m of [
    'ready', 'initialize', 'reset', 'capabilities', 'version', 'catalog',
    'downsample', 'pcm16Bytes', 'rms',
  ]) {
    assert.equal(typeof api[m], 'function', `runanywhere.${m} is a function`);
  }
  assert.equal(typeof api.llm.generate, 'function');
  assert.equal(typeof api.llm.generateStream, 'function');
  assert.equal(typeof api.llm.tools.register, 'function');
  assert.equal(typeof api.models.download, 'function');
  assert.equal(typeof api.rag.open, 'function');
  assert.equal(typeof api.voice.createSession, 'function');
  assert.equal(typeof api.vad.detect, 'function');
  assert.equal(typeof api.secure.set, 'function');
});

test('the pre-v3 flat surface is gone', { skip: SKIP }, () => {
  const { exposed } = freshPreload();
  const api = exposed.runanywhere;
  for (const gone of [
    'loadLLM', 'generate', 'generateStream', 'generateStructured', 'generateObject',
    'generateToolCall', 'unloadLLM', 'loadVLM', 'generateVlm', 'unloadVLM',
    'loadEmbedder', 'embed', 'unloadEmbedder', 'loadSTT', 'transcribe', 'unloadSTT',
    'loadTTS', 'synthesize', 'unloadTTS', 'registerModel', 'modelStatus', 'exists',
    'downloadModel', 'createVad', 'vadProcess', 'vadIsActive', 'vadSetThreshold',
    'vadReset', 'unloadVad', 'secureSet', 'secureGet', 'secureDelete', 'onEvent',
    'splitThinking', 'speakableText', 'formatChat', 'shutdown',
  ]) {
    assert.equal(api[gone], undefined, `runanywhere.${gone} was removed`);
  }
});

test('exposes the runanywhereTest hook that forwards over ipc', { skip: SKIP }, () => {
  const { exposed, state } = freshPreload();
  assert.equal(typeof exposed.runanywhereTest.done, 'function');
  assert.equal(typeof exposed.runanywhereTest.log, 'function');
  exposed.runanywhereTest.done(true);
  exposed.runanywhereTest.log('hi');
  assert.deepEqual(state.ipcSends[0], { channel: 'runanywhere-test-done', args: [true] });
  assert.deepEqual(state.ipcSends[1], { channel: 'runanywhere-test-log', args: ['hi'] });
});

test('the port handshake starts the port and resolves ready()', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  assert.ok(port.started, 'port.start() called');
  assert.equal(typeof port.onmessage, 'function', 'onmessage handler installed');
  // ready() resolves now that the port is connected.
  await exposed.runanywhere.ready();
});

test('a unary call posts {id,method,args} and resolves with the reply result', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const p = exposed.runanywhere.version();
  await tick();
  const msg = port.last();
  assert.equal(msg.method, 'version');
  assert.deepEqual(msg.args, []);
  assert.equal(typeof msg.id, 'number');
  port.onmessage!({ data: { id: msg.id, ok: true, result: '1.2.3' } });
  assert.equal(await p, '1.2.3');
});

test('initialize folds the pre-v3 positional form into the v3 handshake', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const p = exposed.runanywhere.initialize('/sec', '/base');
  await Promise.all([p, pump(port, { 'v3.version': '9.9.9' })]);
  const init = port.posts.find((m) => m.method === 'v3.initialize');
  assert.ok(init, 'initialize reaches the host as a v3 backend call');
  assert.deepEqual(init.args, [{ secureDir: '/sec', baseDir: '/base' }]);
});

test('a namespace call reaches the host as its v3 backend method', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const get = exposed.runanywhere.secure.get as (k: string) => Promise<unknown>;
  const p = get('api-key');
  await tick();
  const msg = port.last();
  assert.equal(msg.method, 'v3.secureGet');
  assert.deepEqual(msg.args, ['api-key']);
  port.onmessage!({ data: { id: msg.id, ok: true, result: 'sk-1' } });
  assert.equal(await p, 'sk-1');
});

test('a failing reply rejects with the error message', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const get = exposed.runanywhere.secure.get as (k: string) => Promise<unknown>;
  const p = get('k');
  await tick();
  const msg = port.last();
  port.onmessage!({ data: { id: msg.id, ok: false, error: 'boom' } });
  await assert.rejects(() => p, /boom/);
});

test('a structured failing reply rejects with a typed SDKException', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const get = exposed.runanywhere.secure.get as (k: string) => Promise<unknown>;
  const p = get('k');
  await tick();
  const msg = port.last();
  port.onmessage!({
    data: {
      id: msg.id,
      ok: false,
      error: {
        message: 'load_model failed: -111',
        code: 111,
        cAbiCode: -111,
        category: 3,
      },
    },
  });
  await assert.rejects(() => p, (e: unknown) => {
    assert.ok(isSDKException(e));
    assert.equal(e.code, ErrorCodes.MODEL_LOAD_FAILED);
    assert.equal(e.cAbiCode, -111);
    return true;
  });
});

test('catalog() returns whatever the process has registered', { skip: SKIP }, () => {
  // catalog.ts is a per-process REGISTRY, not a built-in catalog (the app
  // supplies its own table via registerCatalog()) -- register a fixture so
  // catalog() has something to return.
  clearCatalog();
  registerCatalog({
    'fixture-llm': {
      type: 'llm',
      files: [{ url: 'https://example.com/model.gguf', as: 'model.gguf' }],
      primary: 'model.gguf',
    },
  });
  try {
    const { exposed } = freshPreload();
    const cat = exposed.runanywhere.catalog();
    assert.equal(typeof cat, 'object');
    assert.ok(cat['fixture-llm'], 'includes the registered catalog id');
    assert.equal(cat['fixture-llm'].type, 'llm');
  } finally {
    clearCatalog();
  }
});

test('calls made BEFORE the handshake wait for the port, then post once connected', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  // No connect() yet — the port is null and ready is unresolved.
  const p = exposed.runanywhere.version();
  await tick();
  // Nothing could have been posted (no port). Now connect.
  const port = connect(state);
  await tick();
  assert.equal(port.posts.length, 1, 'the queued call posts after the handshake');
  const msg = port.last();
  port.onmessage!({ data: { id: msg.id, ok: true, result: 'ok' } });
  assert.equal(await p, 'ok');
});

test('reply ids are unique per in-flight call and route independently', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const p1 = exposed.runanywhere.version();
  const del = exposed.runanywhere.secure.delete as (k: string) => Promise<void>;
  const p2 = del('k');
  await tick();
  assert.equal(port.posts.length, 2);
  const [m1, m2] = port.posts;
  assert.notEqual(m1.id, m2.id, 'each call gets a distinct id');
  // Resolve out of order: reply to the 2nd first.
  port.onmessage!({ data: { id: m2.id, ok: true } });
  port.onmessage!({ data: { id: m1.id, ok: true, result: 'v' } });
  await p2;
  assert.equal(await p1, 'v');
});

test('an unknown reply id is ignored (no throw, no cross-talk)', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const p = exposed.runanywhere.version();
  await tick();
  const msg = port.last();
  // A stray message for an id we never sent must be a no-op.
  assert.doesNotThrow(() => port.onmessage!({ data: { id: 999999, ok: true, result: 'nope' } }));
  port.onmessage!({ data: { id: msg.id, ok: true, result: 'real' } });
  assert.equal(await p, 'real');
});
