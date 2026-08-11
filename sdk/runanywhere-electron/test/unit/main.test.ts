// Unit tests for RunAnywhereMain (src/process/main.ts) — the Electron main-process
// broker that forks the utility host and wires renderer <-> utility MessagePorts.
// We mock the 'electron' module (utilityProcess.fork + MessageChannelMain) by
// injecting a fake into the require cache, so no real Electron is spawned.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import * as path from 'node:path';

import type { RunAnywhereMain as RunAnywhereMainClass, RunAnywhereMainOptions } from '../../dist/process/main';

// If electron isn't installed (resolve throws), skip the whole file gracefully.
let electronPath: string | null = null;
try {
  electronPath = require.resolve('electron');
} catch {
  /* electron devDep missing */
}
const SKIP = electronPath ? false : 'electron devDependency not installed';

const mainPath = electronPath ? require.resolve('../../dist/process/main') : null;

/** What the fake electron recorded: every fork, and every channel opened. */
interface ForkRecord {
  hostPath: string;
  args: string[];
  opts: { stdio?: string; env: Record<string, string | undefined> };
  child: FakeChild;
}
interface FakeState {
  forks: ForkRecord[];
  channels: FakeMessageChannelMain[];
}

class FakeChild {
  readonly posts: Array<{ msg: unknown; transfer: unknown }> = [];
  killed = false;
  private readonly _handlers: Record<string, ((...a: unknown[]) => void) | undefined> = {};
  postMessage(msg: unknown, transfer: unknown): void {
    this.posts.push({ msg, transfer });
  }
  kill(): void {
    this.killed = true;
  }
  on(event: string, cb: (...a: unknown[]) => void): void {
    this._handlers[event] = cb;
  }
  emit(event: string, ...a: unknown[]): void {
    this._handlers[event]?.(...a);
  }
}
class FakeMessageChannelMain {
  readonly port1 = { tag: 'port1' };
  readonly port2 = { tag: 'port2' };
  constructor(state: FakeState) {
    state.channels.push(this);
  }
}

/** A stand-in WebContents that records postMessage / send and can be destroyed. */
interface FakeWebContents {
  posts: Array<{ channel: string; message: unknown; transfer: unknown }>;
  sent: Array<{ channel: string; args: unknown[] }>;
  destroyed: boolean;
  postMessage(channel: string, message: unknown, transfer: unknown): void;
  once(): void;
  isDestroyed(): boolean;
  send(channel: string, ...args: unknown[]): void;
}

// `electron`'s own .d.ts describes the real UtilityProcess / WebContents, which
// these fakes deliberately do not implement — only the members main.ts touches.
// The conversion happens once, here, at the injection seam.
type MainCtor = new (opts?: RunAnywhereMainOptions) => RunAnywhereMainClass;
const asWebContents = (wc: FakeWebContents): Parameters<RunAnywhereMainClass['connect']>[0] =>
  wc as unknown as Parameters<RunAnywhereMainClass['connect']>[0];

function installFakeElectron(): FakeState {
  const state: FakeState = { forks: [], channels: [] };

  const fakeElectron = {
    utilityProcess: {
      fork(hostPath: string, args: string[], opts: ForkRecord['opts']) {
        const child = new FakeChild();
        state.forks.push({ hostPath, args, opts, child });
        return child;
      },
    },
    MessageChannelMain: class extends FakeMessageChannelMain {
      constructor() {
        super(state);
      }
    },
  };
  require.cache[electronPath!] = {
    id: electronPath!,
    filename: electronPath!,
    loaded: true,
    exports: fakeElectron,
  } as unknown as NodeModule;
  return state;
}

// Fresh module state per scenario: reinstall the fake electron and re-require
// main so its captured `electron` reference points at the new recorders.
function freshMain(): { RunAnywhereMain: MainCtor; state: FakeState } {
  const state = installFakeElectron();
  delete require.cache[mainPath!];
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { RunAnywhereMain } = require(mainPath!) as { RunAnywhereMain: MainCtor };
  return { RunAnywhereMain, state };
}

function fakeWebContents(): FakeWebContents {
  return {
    posts: [],
    sent: [],
    destroyed: false,
    postMessage(channel, message, transfer) {
      this.posts.push({ channel, message, transfer });
    },
    once() {
      /* real WebContents is an EventEmitter; tests don't need destroy wiring */
    },
    isDestroyed() {
      return this.destroyed;
    },
    send(channel, ...args) {
      this.sent.push({ channel, args });
    },
  };
}

test('connect() forks the utility host exactly once', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  const m = new RunAnywhereMain({ hostPath: '/x/host.js' });
  m.connect(asWebContents(fakeWebContents()));
  m.connect(asWebContents(fakeWebContents()));
  assert.equal(state.forks.length, 1, 'child is memoized across connects');
  assert.equal(state.forks[0].hostPath, '/x/host.js');
  assert.deepEqual(state.forks[0].args, []);
  assert.equal(state.forks[0].opts.stdio, 'inherit');
});

test('connect() brokers a MessageChannel: port1 -> child, port2 -> webContents', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  const m = new RunAnywhereMain({ hostPath: '/x/host.js' });
  const wc = fakeWebContents();
  m.connect(asWebContents(wc));

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
  m.connect(asWebContents(wc), 'my-channel');
  assert.equal(wc.posts[0].channel, 'my-channel');
  assert.ok(state.channels.length >= 1);
});

test('a second connect() reuses the child but opens a fresh channel', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  const m = new RunAnywhereMain({ hostPath: '/x/host.js' });
  m.connect(asWebContents(fakeWebContents()));
  m.connect(asWebContents(fakeWebContents()));
  assert.equal(state.forks.length, 1);
  assert.equal(state.channels.length, 2, 'each connect opens a new MessageChannel');
  assert.equal(state.forks[0].child.posts.length, 2, 'both connects post to the same child');
});

test('nativePath is forwarded into the utility env as RUNANYWHERE_NATIVE_PATH', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  const m = new RunAnywhereMain({ hostPath: '/x/host.js', nativePath: 'C:/models/native.node' });
  m.connect(asWebContents(fakeWebContents()));
  assert.equal(state.forks[0].opts.env.RUNANYWHERE_NATIVE_PATH, 'C:/models/native.node');
});

test('without nativePath the env does not force RUNANYWHERE_NATIVE_PATH', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  // Ensure the ambient env doesn't leak a value into the assertion.
  const saved = process.env.RUNANYWHERE_NATIVE_PATH;
  delete process.env.RUNANYWHERE_NATIVE_PATH;
  try {
    const m = new RunAnywhereMain({ hostPath: '/x/host.js' });
    m.connect(asWebContents(fakeWebContents()));
    assert.equal(state.forks[0].opts.env.RUNANYWHERE_NATIVE_PATH, undefined);
  } finally {
    if (saved !== undefined) process.env.RUNANYWHERE_NATIVE_PATH = saved;
  }
});

test('pluginPaths option is forwarded as RUNANYWHERE_PLUGIN_PATHS', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  const a = path.resolve('/plugins/librunanywhere_llamacpp.dylib');
  const b = path.resolve('/plugins/librunanywhere_sherpa.dylib');
  const m = new RunAnywhereMain({ hostPath: '/x/host.js', pluginPaths: [a, b] });
  m.connect(asWebContents(fakeWebContents()));
  assert.equal(
    state.forks[0].opts.env.RUNANYWHERE_PLUGIN_PATHS,
    [a, b].join(path.delimiter)
  );
});

test('re-fork after kill replays RUNANYWHERE_PLUGIN_PATHS from pluginPaths', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  const plugin = path.resolve('/plugins/librunanywhere_onnx.dylib');
  const m = new RunAnywhereMain({ hostPath: '/x/host.js', pluginPaths: [plugin] });
  m.connect(asWebContents(fakeWebContents()));
  m.kill();
  m.connect(asWebContents(fakeWebContents()));
  assert.equal(state.forks.length, 2);
  assert.equal(state.forks[1].opts.env.RUNANYWHERE_PLUGIN_PATHS, plugin);
});

test('kill() kills the child and the next connect() re-forks', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  const m = new RunAnywhereMain({ hostPath: '/x/host.js' });
  m.connect(asWebContents(fakeWebContents()));
  const first = state.forks[0].child;
  m.kill();
  assert.ok(first.killed, 'kill() forwarded to the child');
  m.connect(asWebContents(fakeWebContents()));
  assert.equal(state.forks.length, 2, 're-forked after kill');
});

test('child exit clears the child, notifies onExit, and re-forks on reconnect', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  let exitCode: number | null = null;
  const m = new RunAnywhereMain({ hostPath: '/x/host.js', onExit: (c) => (exitCode = c) });
  m.connect(asWebContents(fakeWebContents()));
  state.forks[0].child.emit('exit', 7);
  assert.equal(exitCode, 7, 'onExit called with the exit code');
  m.connect(asWebContents(fakeWebContents()));
  assert.equal(state.forks.length, 2, 'crash recovery re-forks the utility');
});

test('child exit sends runanywhere-host-exited to every connected renderer', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  const m = new RunAnywhereMain({ hostPath: '/x/host.js' });
  const wc1 = fakeWebContents();
  const wc2 = fakeWebContents();
  m.connect(asWebContents(wc1));
  m.connect(asWebContents(wc2)); // reuses the same child
  state.forks[0].child.emit('exit', 9);
  for (const wc of [wc1, wc2]) {
    const msg = wc.sent.find((s) => s.channel === 'runanywhere-host-exited');
    assert.ok(msg, 'renderer notified of host exit');
    assert.equal(msg.args[0], 9, 'exit code forwarded');
  }
});

test('a destroyed renderer is not notified on host exit', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  const m = new RunAnywhereMain({ hostPath: '/x/host.js' });
  const wc = fakeWebContents();
  m.connect(asWebContents(wc));
  wc.destroyed = true;
  state.forks[0].child.emit('exit', 1);
  assert.equal(wc.sent.length, 0, 'no send() to a destroyed webContents');
});

test('default hostPath resolves to host.js beside the module', { skip: SKIP }, () => {
  const { RunAnywhereMain, state } = freshMain();
  const m = new RunAnywhereMain();
  m.connect(asWebContents(fakeWebContents()));
  const forked = state.forks[0].hostPath;
  assert.equal(path.basename(forked), 'host.js');
  assert.ok(path.isAbsolute(forked), 'default host path is absolute');
});
