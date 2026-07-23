// Unit tests for the renderer preload (src/process/preload.ts): it exposes the
// window.runanywhere API over contextBridge, correlates request/reply by id over
// a MessagePort, routes streamed tokens to onToken callbacks, and gates every
// call on the port handshake. We mock 'electron' (contextBridge + ipcRenderer)
// and drive a fake MessagePort — no real Electron / renderer needed.
const { test } = require('node:test');
const assert = require('node:assert/strict');

let electronPath = null;
try {
  electronPath = require.resolve('electron');
} catch {
  /* electron devDep missing */
}
const SKIP = electronPath ? false : 'electron devDependency not installed';
const preloadPath = electronPath ? require.resolve('../../dist/process/preload') : null;

const tick = () => new Promise((r) => setImmediate(r));

function installFakeElectron() {
  const exposed = {};
  const state = { ipcOn: {}, ipcSends: [] };
  const fakeElectron = {
    contextBridge: {
      exposeInMainWorld(name, api) {
        exposed[name] = api;
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
  return { exposed, state };
}

// Re-require the preload fresh so its module-level port/pending/ready reset.
function freshPreload() {
  const { exposed, state } = installFakeElectron();
  delete require.cache[preloadPath];
  require(preloadPath);
  return { exposed, state };
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

// Connect the preload to a port (simulate main delivering it over ipc).
function connect(state) {
  const port = fakePort();
  state.ipcOn['runanywhere-port']({ ports: [port] });
  return port;
}

test('exposes window.runanywhere with the full method surface', { skip: SKIP }, () => {
  const { exposed } = freshPreload();
  const api = exposed.runanywhere;
  assert.ok(api, 'runanywhere API exposed');
  for (const m of [
    'ready', 'version', 'initialize', 'onEvent', 'splitThinking', 'catalog', 'modelStatus', 'downloadModel',
    'loadLLM', 'generate', 'generateStream', 'generateStructured', 'generateObject', 'generateToolCall', 'unloadLLM',
    'loadVLM', 'generateVlm', 'unloadVLM',
    'loadEmbedder', 'embed', 'unloadEmbedder',
    'loadSTT', 'transcribe', 'unloadSTT',
    'loadTTS', 'synthesize', 'unloadTTS',
    'registerModel',
    'ragCreateSession', 'ragIngest', 'ragQuery', 'ragStats', 'ragClear', 'ragDestroySession',
    'secureSet', 'secureGet', 'secureDelete',
    'createVad', 'vadProcess', 'vadIsActive', 'vadSetThreshold', 'vadReset', 'unloadVad',
    'shutdown',
  ]) {
    assert.equal(typeof api[m], 'function', `runanywhere.${m} is a function`);
  }
});

test('splitThinking bridge splits reasoning from the answer', { skip: SKIP }, () => {
  const { exposed } = freshPreload();
  assert.deepEqual(exposed.runanywhere.splitThinking('<think>ponder</think>Answer.'), {
    thinking: 'ponder',
    response: 'Answer.',
  });
});

test('generateObject builds a grammar, accumulates the stream, and parses JSON', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const schema = { type: 'object', properties: { city: { type: 'string' } }, required: ['city'] };
  const p = exposed.runanywhere.generateObject(4, 'Where is the Eiffel Tower?', schema);
  await tick();
  const msg = port.last();
  assert.equal(msg.method, 'generate');
  assert.equal(msg.args[0], 4);
  assert.ok(typeof msg.args[2].grammar === 'string' && msg.args[2].grammar.includes('root ::='),
    'a grammar was compiled and passed');
  // Stream the JSON in pieces, then finish.
  for (const piece of ['{"city":', '"Paris"', '}']) port.onmessage({ data: { id: msg.id, token: piece } });
  port.onmessage({ data: { id: msg.id, done: true } });
  assert.deepEqual(await p, { city: 'Paris' });
});

test('generateStructured (house-uniform name) builds a grammar and parses JSON', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const schema = { type: 'object', properties: { city: { type: 'string' } }, required: ['city'] };
  const p = exposed.runanywhere.generateStructured(4, 'Where is the Eiffel Tower?', schema);
  await tick();
  const msg = port.last();
  assert.equal(msg.method, 'generate');
  assert.ok(msg.args[2].grammar.includes('root ::='));
  for (const piece of ['{"city":', '"Paris"', '}']) port.onmessage({ data: { id: msg.id, token: piece } });
  port.onmessage({ data: { id: msg.id, done: true } });
  assert.deepEqual(await p, { city: 'Paris' });
});

test('generateToolCall compiles an anyOf grammar and returns the parsed call', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const tools = [
    { name: 'get_weather', parameters: { type: 'object', properties: { city: { type: 'string' } }, required: ['city'] } },
    { name: 'set_timer', parameters: { type: 'object', properties: { seconds: { type: 'integer' } }, required: ['seconds'] } },
  ];
  const p = exposed.runanywhere.generateToolCall(4, 'Weather in Rome?', tools);
  await tick();
  const msg = port.last();
  assert.equal(msg.method, 'generate');
  assert.ok(msg.args[1].includes('Available tools:'), 'the tool list is injected into the prompt');
  assert.ok(msg.args[2].grammar.includes('get_weather'), 'the grammar names the tools');
  for (const piece of ['{"name":"get_weather",', '"arguments":{"city":"Rome"}}']) {
    port.onmessage({ data: { id: msg.id, token: piece } });
  }
  port.onmessage({ data: { id: msg.id, done: true } });
  assert.deepEqual(await p, { name: 'get_weather', arguments: { city: 'Rome' } });
});

test('generateToolCall rejects an empty tools array', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  connect(state);
  await assert.rejects(() => exposed.runanywhere.generateToolCall(4, 'hi', []), /at least one tool/);
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
  port.onmessage({ data: { id: msg.id, ok: true, result: 'v9.9' } });
  assert.equal(await p, 'v9.9');
});

test('initialize forwards its args', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const p = exposed.runanywhere.initialize('/sec', '/base');
  await tick();
  const msg = port.last();
  assert.equal(msg.method, 'initialize');
  assert.deepEqual(msg.args, ['/sec', '/base']);
  port.onmessage({ data: { id: msg.id, ok: true } });
  await p;
});

test('transcribe forwards the pcm bytes and resolves with the transcript', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const pcm = new Uint8Array([1, 2, 3, 4]);
  const p = exposed.runanywhere.transcribe(7, pcm);
  await tick();
  const msg = port.last();
  assert.equal(msg.method, 'transcribe');
  assert.deepEqual(msg.args, [7, pcm]);
  port.onmessage({ data: { id: msg.id, ok: true, result: 'hello world' } });
  assert.equal(await p, 'hello world');
});

test('synthesize resolves with the {sampleRate,samples} audio result', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const p = exposed.runanywhere.synthesize(9, 'hi there');
  await tick();
  const msg = port.last();
  assert.equal(msg.method, 'synthesize');
  assert.deepEqual(msg.args, [9, 'hi there']);
  const audio = { sampleRate: 22050, samples: new Float32Array([0.1, -0.2]) };
  port.onmessage({ data: { id: msg.id, ok: true, result: audio } });
  const got = await p;
  assert.equal(got.sampleRate, 22050);
  assert.deepEqual(Array.from(got.samples), [0.1, -0.2].map((x) => Math.fround(x)));
});

test('a failing reply rejects with the error message', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const p = exposed.runanywhere.loadLLM('/model.gguf');
  await tick();
  const msg = port.last();
  assert.equal(msg.method, 'loadModel');
  port.onmessage({ data: { id: msg.id, ok: false, error: 'boom' } });
  await assert.rejects(() => p, /boom/);
});

test('generate streams tokens to onToken then resolves on done', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const tokens = [];
  const p = exposed.runanywhere.generate(3, 'hello', (t) => tokens.push(t));
  await tick();
  const msg = port.last();
  assert.equal(msg.method, 'generate');
  assert.deepEqual(msg.args, [3, 'hello']);
  port.onmessage({ data: { id: msg.id, token: 'a' } });
  port.onmessage({ data: { id: msg.id, token: 'b' } });
  assert.deepEqual(tokens, ['a', 'b'], 'tokens routed to onToken in order');
  port.onmessage({ data: { id: msg.id, done: true } });
  await p; // resolves on done
});

test('generateStream yields token events then a final event with metrics', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const events = [];
  const p = exposed.runanywhere.generateStream(3, 'hi', { maxTokens: 8 }, (e) => events.push(e));
  await tick();
  const msg = port.last();
  assert.equal(msg.method, 'generate');
  assert.deepEqual(msg.args, [3, 'hi', { maxTokens: 8 }]);
  port.onmessage({ data: { id: msg.id, token: 'a' } });
  port.onmessage({ data: { id: msg.id, token: 'b' } });
  port.onmessage({ data: { id: msg.id, done: true } });
  await p;
  assert.ok(events.length >= 3, 'two token events + a final event');
  assert.equal(events[0].token, 'a');
  assert.equal(events[0].isFinal, false);
  const final = events[events.length - 1];
  assert.equal(final.isFinal, true);
  assert.ok(final.result, 'final event carries metrics');
  assert.equal(final.result.text, 'ab');
  assert.equal(final.result.tokenCount, 2);
});

test('catalog() returns the built-in model catalog', { skip: SKIP }, () => {
  const { exposed } = freshPreload();
  const cat = exposed.runanywhere.catalog();
  assert.equal(typeof cat, 'object');
  assert.ok(cat['qwen2.5-0.5b'], 'includes a known catalog id');
  assert.equal(cat['qwen2.5-0.5b'].type, 'llm');
});

test('onEvent subscribes to lifecycle events and returns an unsubscribe', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const seen = [];
  const off = exposed.runanywhere.onEvent((e) => seen.push(e.type));
  assert.equal(typeof off, 'function');
  const p = exposed.runanywhere.initialize('/s', '/b');
  await tick();
  port.onmessage({ data: { id: port.last().id, ok: true } });
  await p;
  assert.ok(seen.includes('initialized'), 'initialize emits an initialized event');
  off();
});

test('generate forwards a generation-options object before the callback', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const p = exposed.runanywhere.generate(3, 'hi', { grammar: 'root ::= "x"', maxTokens: 8 }, () => {});
  await tick();
  const msg = port.last();
  assert.equal(msg.method, 'generate');
  assert.deepEqual(msg.args, [3, 'hi', { grammar: 'root ::= "x"', maxTokens: 8 }]);
  port.onmessage({ data: { id: msg.id, done: true } });
  await p;
});

test('generateVlm streams tokens over an image + prompt call', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const tokens = [];
  const p = exposed.runanywhere.generateVlm(5, '/img.png', 'describe', (t) => tokens.push(t));
  await tick();
  const msg = port.last();
  assert.equal(msg.method, 'generateVlm');
  assert.deepEqual(msg.args, [5, '/img.png', 'describe']);
  port.onmessage({ data: { id: msg.id, token: 'red' } });
  port.onmessage({ data: { id: msg.id, done: true } });
  assert.deepEqual(tokens, ['red']);
  await p;
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
  port.onmessage({ data: { id: msg.id, ok: true, result: 'ok' } });
  assert.equal(await p, 'ok');
});

test('reply ids are unique per in-flight call and route independently', { skip: SKIP }, async () => {
  const { exposed, state } = freshPreload();
  const port = connect(state);
  const p1 = exposed.runanywhere.version();
  const p2 = exposed.runanywhere.shutdown();
  await tick();
  assert.equal(port.posts.length, 2);
  const [m1, m2] = port.posts;
  assert.notEqual(m1.id, m2.id, 'each call gets a distinct id');
  // Resolve out of order: reply to the 2nd first.
  port.onmessage({ data: { id: m2.id, ok: true } });
  port.onmessage({ data: { id: m1.id, ok: true, result: 'v' } });
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
  assert.doesNotThrow(() => port.onmessage({ data: { id: 999999, ok: true, result: 'nope' } }));
  port.onmessage({ data: { id: msg.id, ok: true, result: 'real' } });
  assert.equal(await p, 'real');
});
