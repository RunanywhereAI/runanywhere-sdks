# @runanywhere/electron

On-device **LLM / VLM / STT / TTS / embeddings** for Electron & Node — a native
N-API addon over the RunAnywhere `rac_*` C ABI and llama.cpp / ONNX Runtime /
sherpa-onnx. Windows-first (x64, arm64-ready); the QHexRT NPU backend seam is
kept open for later. Inference runs in an isolated Electron **utility process**,
streaming to the renderer over a `MessagePort`.

> Status: MVP. All five modalities, structured output, tool calling, multi-turn
> chat, model download/catalog, a voice pipeline, and audio I/O are implemented
> and covered by ~290 unit + integration tests.

## Install

```bash
npm install @runanywhere/electron
```

The package ships a prebuilt native addon for `win32-x64` under `prebuilds/`
(the `.node` plus the onnxruntime / sherpa DLLs it links). When bundling into an
Electron app, unpack them from the asar:

```jsonc
// electron-builder config
"asarUnpack": ["**/node_modules/@runanywhere/electron/prebuilds/**"]
```

## Quick start (Node)

```js
const { RunAnywhere } = require('@runanywhere/electron');

RunAnywhere.initialize();
const llm = await RunAnywhere.loadLLM('qwen2.5-0.5b'); // catalog id or a local path
for await (const t of llm.generate('Explain on-device AI in one sentence.')) {
  process.stdout.write(t);
}
llm.unload();
RunAnywhere.shutdown();
```

### Structured output (guaranteed-valid JSON)

Decoding is constrained by a GBNF grammar compiled from your schema, so the
result always parses:

```js
const person = await llm.generateObject(
  'Extract the person: "Ada Lovelace, 36, English mathematician."',
  {
    schema: {
      type: 'object',
      properties: {
        name: { type: 'string' },
        age: { type: 'integer' },
        interests: { type: 'array', items: { type: 'string' }, maxItems: 5 },
      },
      required: ['name', 'age', 'interests'],
    },
  }
);
// { name: 'Ada Lovelace', age: 36, interests: [...] }
```

### Tool calling

```js
const call = await llm.generateToolCall('Weather in Tokyo in celsius?', [
  {
    name: 'get_weather',
    description: 'Current weather for a city',
    parameters: {
      type: 'object',
      properties: { city: { type: 'string' }, unit: { type: 'string', enum: ['celsius', 'fahrenheit'] } },
      required: ['city', 'unit'],
    },
  },
]);
// { name: 'get_weather', arguments: { city: 'Tokyo', unit: 'celsius' } }
```

The grammar guarantees the *format* and a valid tool *name*; your prompt drives
the decision. Gate *whether* to call a tool in your app code.

### Multi-turn chat

```js
const chat = RunAnywhere.createChat(llm, { system: 'You are concise.' });
await chat.sendText('My name is Aman.');
await chat.sendText('What is my name?'); // -> "Your name is Aman."
```

### Voice (Node, file-driven)

```js
const { RunAnywhere, decodeWav, downsample, pcm16Bytes, encodeWav } = require('@runanywhere/electron');
const fs = require('fs');

const stt = await RunAnywhere.loadSTT('whisper-tiny');
const llm = await RunAnywhere.loadLLM('smollm2-135m');
const tts = await RunAnywhere.loadTTS('piper-lessac');
const agent = RunAnywhere.createVoiceAgent({ stt, llm, tts });

const { sampleRate, samples } = decodeWav(fs.readFileSync('input.wav'));
const turn = await agent.processTurn(pcm16Bytes(downsample(samples, sampleRate, 16000)));
fs.writeFileSync('reply.wav', encodeWav(turn.audio.samples, turn.audio.sampleRate));
```

## Electron (utility-process isolation)

Main process:

```js
const { RunAnywhereMain } = require('@runanywhere/electron/main');
const ra = new RunAnywhereMain({ nativePath: /* path to the .node, or omit to use the prebuild */ });
win.webContents.on('did-finish-load', () => ra.connect(win.webContents));
```

Renderer preload — point `webPreferences.preload` at
`@runanywhere/electron/preload`; it exposes `window.runanywhere` with the async
API (`loadLLM`, `generate(handle, prompt[, options], onToken)`, `transcribe`,
`synthesize`, …). See `examples/voice-app/` for a mic → STT → LLM → TTS → speaker
loop, and `examples/electron-app/` for streaming.

Renderers that bundle the SDK (webpack/vite) can import the audio helpers:

```js
import { MicRecorder, SpeakerPlayer } from '@runanywhere/electron/audio';
```

## Model catalog

`loadLLM`/`loadVLM`/`loadEmbedder`/`loadSTT`/`loadTTS` accept a catalog id
(auto-downloaded on first use) or a local path. Built-in ids: `smollm2-135m`,
`qwen2.5-0.5b`, `smolvlm-256m`, `minilm`, `whisper-tiny`, `piper-lessac`.

## Building from source

Requires the compiled RunAnywhere commons + engines (MSVC, `windows-release`
preset) and Node dev headers. Then:

```bash
npm install
npm run build          # TypeScript -> dist/
npm run bundle:native  # copy the built .node + DLLs into prebuilds/
npm test               # unit tests (hermetic, no native addon needed)
# integration tests need the addon + models:
$env:RUNANYWHERE_NATIVE_PATH = '<...>/runanywhere_native.node'
npm run test:integration
```

See `native/CMakeLists.txt` and the repo build docs for compiling the addon.

## License

See the repository `LICENSE`.
