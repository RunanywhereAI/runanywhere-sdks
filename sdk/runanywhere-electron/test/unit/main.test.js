// Unit tests for RunAnywhereMain (src/process/main.ts) — the Electron main-process
// broker that forks the utility host and wires renderer <-> utility MessagePorts.
// We mock the 'electron' module (utilityProcess.fork + MessageChannelMain) by
// injecting a fake into the require cache, so no real Electron is spawned.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

// If electron isn't installed (resolve throws), skip the whole file gracefully.
let electronPath = null;
try {
  electronPath = require.resolve('electron');
} catch {
  /* electron devDep missing */
}
const SKIP = electronPath ? false : 'electron devDependency not installed';

const mainPath = electronPath ? require.resolve('../../dist/process/main') : null;

function installFakeElectron() {
  const state = { forks: [], channels: [] };

  class FakeChild {
    constructor() {
      this.posts = [];
      this.killed = false;
      this._handlers = {};
    }
    postMessage(msg, transfer) {
      this.posts.push({ msg, transfer });
    }
    kill() {
      this.killed = true;
    }
    on(event, cb) {
      this._handlers[event] = cb;
    }
    emit(event, ...a) {
      if (this._handlers[event]) this._handlers[event](...a);
    }
  }
  class FakeMessageChannelMain {
    constructor() {
      this.port1 = { tag: 'port1' };
      this.port2 = { tag: 'port2' };
      state.channels.push(this);
    }
  }
  const fakeElectron = {
    utilityProcess: {
      fork(hostPath, args, opts) {
        const child = new FakeChild();
        state.forks.push({ hostPath, args, opts, child });
        return child;
      },
    },
    MessageChannelMain: FakeMessageChannelMain,
  };
  require.cache[electronPath] = {
    id: electronPath,
    filename: electronPath,
    loaded: true,
    exports: fakeElectron,
  };
  return state;
}

// Fresh module state per scenario: reinstall the fake electron and re-require
// main so its captured `electron` reference points at the new recorders.
function freshMain() {
  const state = installFakeElectron();
  delete require.cache[mainPath];
  const { RunAnywhereMain } = require(mainPath);
  return { RunAnywhereMain, state };
}

function fakeWebContents() {
  return {
    posts: [],
    postMessage(channel, message, transfer) {
      this.posts.push({ channel, message, transfer });
    },
  };
}

test('connect() forks the utility host exactly once', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  const m = new RunAnywhereMain({ hostPath: '/x/host.js' });
  m.connect(fakeWebContents());
  m.connect(fakeWebContents());
  assert.equal(state.forks.length, 1, 'child is memoized across connects');
  assert.equal(state.forks[0].hostPath, '/x/host.js');
  assert.deepEqual(state.forks[0].args, []);
  assert.equal(state.forks[0].opts.stdio, 'inherit');
});

test('connect() brokers a MessageChannel: port1 -> child, port2 -> webContents', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  const m = new RunAnywhereMain({ hostPath: '/x/host.js' });
  const wc = fakeWebContents();
  m.connect(wc);

  const child = state.forks[0].child;
  const chan = state.channels[0];
  // child gets a {type:'connect'} message transferring port1.
  assert.equal(child.posts.length, 1);
  assert.deepEqual(child.posts[0].msg, { type: 'connect' });
  assert.deepEqual(child.posts[0].transfer, [chan.port1]);
  // webContents gets the default channel + port2.
  assert.equal(wc.posts.length, 1);
  assert.equal(wc.posts[0].channel, 'runanywhere-port');
  assert.equal(wc.posts[0].message, null);
  assert.deepEqual(wc.posts[0].transfer, [chan.port2]);
});

test('connect() honors a custom channel name', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  const m = new RunAnywhereMain({ hostPath: '/x/host.js' });
  const wc = fakeWebContents();
  m.connect(wc, 'my-channel');
  assert.equal(wc.posts[0].channel, 'my-channel');
  assert.ok(state.channels.length >= 1);
});

test('a second connect() reuses the child but opens a fresh channel', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  const m = new RunAnywhereMain({ hostPath: '/x/host.js' });
  m.connect(fakeWebContents());
  m.connect(fakeWebContents());
  assert.equal(state.forks.length, 1);
  assert.equal(state.channels.length, 2, 'each connect opens a new MessageChannel');
  assert.equal(state.forks[0].child.posts.length, 2, 'both connects post to the same child');
});

test('nativePath is forwarded into the utility env as RUNANYWHERE_NATIVE_PATH', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  const m = new RunAnywhereMain({ hostPath: '/x/host.js', nativePath: 'C:/models/native.node' });
  m.connect(fakeWebContents());
  assert.equal(state.forks[0].opts.env.RUNANYWHERE_NATIVE_PATH, 'C:/models/native.node');
});

test('without nativePath the env does not force RUNANYWHERE_NATIVE_PATH', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  // Ensure the ambient env doesn't leak a value into the assertion.
  const saved = process.env.RUNANYWHERE_NATIVE_PATH;
  delete process.env.RUNANYWHERE_NATIVE_PATH;
  try {
    const m = new RunAnywhereMain({ hostPath: '/x/host.js' });
    m.connect(fakeWebContents());
    assert.equal(state.forks[0].opts.env.RUNANYWHERE_NATIVE_PATH, undefined);
  } finally {
    if (saved !== undefined) process.env.RUNANYWHERE_NATIVE_PATH = saved;
  }
});

test('kill() kills the child and the next connect() re-forks', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  const m = new RunAnywhereMain({ hostPath: '/x/host.js' });
  m.connect(fakeWebContents());
  const first = state.forks[0].child;
  m.kill();
  assert.ok(first.killed, 'kill() forwarded to the child');
  m.connect(fakeWebContents());
  assert.equal(state.forks.length, 2, 're-forked after kill');
});

test('child exit clears the child, notifies onExit, and re-forks on reconnect', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  let exitCode = null;
  const m = new RunAnywhereMain({ hostPath: '/x/host.js', onExit: (c) => (exitCode = c) });
  m.connect(fakeWebContents());
  state.forks[0].child.emit('exit', 7);
  assert.equal(exitCode, 7, 'onExit called with the exit code');
  m.connect(fakeWebContents());
  assert.equal(state.forks.length, 2, 'crash recovery re-forks the utility');
});

test('default hostPath resolves to host.js beside the module', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  const m = new RunAnywhereMain();
  m.connect(fakeWebContents());
  const forked = state.forks[0].hostPath;
  assert.equal(path.basename(forked), 'host.js');
  assert.ok(path.isAbsolute(forked), 'default host path is absolute');
});
