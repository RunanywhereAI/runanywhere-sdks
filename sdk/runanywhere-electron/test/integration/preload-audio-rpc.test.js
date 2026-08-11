// Integration: preload audio DSP + embeddings math route through utility-host
// RPC — never by resolving runanywhere_native.node in the preload/renderer.
//
// Intentionally does NOT call setAudioNativeForTests (that mock would hide the
// production failure mode where RUNANYWHERE_NATIVE_PATH is only set for the
// utilityProcess and no prebuilds exist beside the package).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const Module = require('module');

let electronPath = null;
try {
  electronPath = require.resolve('electron');
} catch {
  /* electron devDep missing */
}
const SKIP = electronPath ? false : 'electron devDependency not installed';
const preloadPath = electronPath ? require.resolve('../../dist/process/preload') : null;
const bridgePath = path.resolve(__dirname, '../../dist/bridge.js');

const tick = () => new Promise((r) => setImmediate(r));

function installFakeElectron() {
  const mainWorld = {};
  const state = { ipcOn: {}, ipcSends: [], mainWorld };
  const fakeElectron = {
    contextBridge: {
      exposeInMainWorld(name, api) {
        mainWorld[name] = Object.freeze(api);
      },
    },
    ipcRenderer: {
      on(channel, cb) {
        state.ipcOn[channel] = cb;
      },
      send(channel, ...args) {
        state.ipcSends.push({ channel, args });
      },
    },
  };
  require.cache[electronPath] = {
    id: electronPath,
    filename: electronPath,
    loaded: true,
    exports: fakeElectron,
  };
  return { state };
}

function freshPreload() {
  const { state } = installFakeElectron();
  // Drop any prior audio bind from other suites.
  const { bindAudioBackend, setAudioNativeForTests } = require('../../dist/audio');
  setAudioNativeForTests(null);
  bindAudioBackend(null);
  delete require.cache[preloadPath];
  // Ensure bridge is not already loaded — and make any attempt to load it fail loud.
  delete require.cache[bridgePath];
  const originalLoad = Module._load;
  Module._load = function patchedLoad(request, parent, isMain) {
    const resolved =
      request === './bridge' ||
      request === '../bridge' ||
      (typeof request === 'string' && request.replace(/\\/g, '/').endsWith('/bridge'))
        ? path.resolve(path.dirname(parent?.filename || ''), request)
        : request;
    if (
      resolved === bridgePath ||
      (typeof request === 'string' &&
        (request === './bridge' || request.endsWith('/bridge') || request.endsWith('/bridge.js')))
    ) {
      throw new Error('bridge resolveAddon must not run in preload/renderer audio DSP paths');
    }
    return originalLoad.apply(this, arguments);
  };
  state.restoreLoad = () => {
    Module._load = originalLoad;
  };
  try {
    require(preloadPath);
  } catch (e) {
    state.restoreLoad();
    throw e;
  }
  return {
    api: state.mainWorld.runanywhere,
    state,
  };
}

function fakePort() {
  return {
    posts: [],
    started: false,
    onmessage: null,
    postMessage(m) {
      this.posts.push(m);
    },
    start() {
      this.started = true;
    },
    last() {
      return this.posts[this.posts.length - 1];
    },
  };
}

function connect(state) {
  const port = fakePort();
  state.ipcOn['runanywhere-port']({ ports: [port] });
  return port;
}

test.afterEach(() => {
  try {
    const { bindAudioBackend, setAudioNativeForTests } = require('../../dist/audio');
    setAudioNativeForTests(null);
    bindAudioBackend(null);
  } catch {
    /* dist may be mid-rebuild */
  }
});

test(
  'preload downsample / pcm16Bytes / rms post v3 audio RPC without loading bridge',
  { skip: SKIP },
  async () => {
    const savedNative = process.env.RUNANYWHERE_NATIVE_PATH;
    delete process.env.RUNANYWHERE_NATIVE_PATH;
    let restoreLoad = () => {};
    try {
      const { api, state } = freshPreload();
      restoreLoad = state.restoreLoad;
      const port = connect(state);
      await api.ready();

      const downP = api.downsample(new Float32Array([0, 0.5, -0.5, 1]), 16000, 8000);
      await tick();
      let msg = port.last();
      assert.equal(msg.method, 'v3.audioResampleF32');
      assert.equal(msg.args[1], 16000);
      assert.equal(msg.args[2], 8000);
      port.onmessage({
        data: { id: msg.id, ok: true, result: new Float32Array([0, 1]) },
      });
      const down = await downP;
      assert.equal(down.length, 2);

      const pcmP = api.pcm16Bytes(new Float32Array([0, 1]));
      await tick();
      msg = port.last();
      assert.equal(msg.method, 'v3.audioFloat32ToPcm16');
      port.onmessage({
        data: { id: msg.id, ok: true, result: new Int16Array([0, 32767]) },
      });
      const pcm = await pcmP;
      assert.equal(pcm.byteLength, 4);

      const rmsP = api.rms(new Float32Array([0.5, 0.5]));
      await tick();
      msg = port.last();
      assert.equal(msg.method, 'v3.audioComputeRms');
      port.onmessage({ data: { id: msg.id, ok: true, result: 0.5 } });
      assert.equal(await rmsP, 0.5);
    } finally {
      restoreLoad();
      if (savedNative !== undefined) process.env.RUNANYWHERE_NATIVE_PATH = savedNative;
      else delete process.env.RUNANYWHERE_NATIVE_PATH;
    }
  }
);

test(
  'preload embeddings cosineSimilarity / computeNorm post v3 vector RPC without bridge',
  { skip: SKIP },
  async () => {
    const savedNative = process.env.RUNANYWHERE_NATIVE_PATH;
    delete process.env.RUNANYWHERE_NATIVE_PATH;
    let restoreLoad = () => {};
    try {
      const { api, state } = freshPreload();
      restoreLoad = state.restoreLoad;
      const port = connect(state);
      await api.ready();

      const a = new Float32Array([1, 0]);
      const b = new Float32Array([0, 1]);
      const simP = api.embeddings.cosineSimilarity(a, b);
      await tick();
      let msg = port.last();
      assert.equal(msg.method, 'v3.embeddingsSimilarity');
      port.onmessage({ data: { id: msg.id, ok: true, result: 0 } });
      assert.equal(await simP, 0);

      const normP = api.embeddings.computeNorm(a);
      await tick();
      msg = port.last();
      assert.equal(msg.method, 'v3.embeddingsNorm');
      port.onmessage({ data: { id: msg.id, ok: true, result: 1 } });
      assert.equal(await normP, 1);
    } finally {
      restoreLoad();
      if (savedNative !== undefined) process.env.RUNANYWHERE_NATIVE_PATH = savedNative;
      else delete process.env.RUNANYWHERE_NATIVE_PATH;
    }
  }
);

test(
  'in-flight audio DSP rejects when the utility host exits',
  { skip: SKIP },
  async () => {
    const savedNative = process.env.RUNANYWHERE_NATIVE_PATH;
    delete process.env.RUNANYWHERE_NATIVE_PATH;
    let restoreLoad = () => {};
    try {
      const { api, state } = freshPreload();
      restoreLoad = state.restoreLoad;
      const port = connect(state);
      await api.ready();

      const downP = api.downsample(new Float32Array([0]), 16000, 8000);
      await tick();
      assert.equal(port.last().method, 'v3.audioResampleF32');
      // Host dies before the reply — pending must settle, not hang.
      state.ipcOn['runanywhere-host-exited'](null, 1);
      await assert.rejects(() => downP, /exited|retrying/i);
    } finally {
      restoreLoad();
      if (savedNative !== undefined) process.env.RUNANYWHERE_NATIVE_PATH = savedNative;
      else delete process.env.RUNANYWHERE_NATIVE_PATH;
    }
  }
);
