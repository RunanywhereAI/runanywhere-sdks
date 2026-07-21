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
const person = await llm.generateStructured(
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

`generateStream(prompt, options?)` streams `LLMStreamEvent`s — a `token` per event
and a final event carrying `result` (text, token count, time-to-first-token,
tokens/second), matching the other SDKs. Errors are thrown as `SDKException`
(`.code` / `.category` / `.recoverySuggestion`), uniform across platforms.

### Tool calling

```js
const tools = [
  {
    name: 'get_weather',
    description: 'Current weather for a city',
    parameters: {
      type: 'object',
      properties: { city: { type: 'string' }, unit: { type: 'string', enum: ['celsius', 'fahrenheit'] } },
      required: ['city', 'unit'],
    },
    execute: ({ city, unit }) => fetchWeather(city, unit), // optional
  },
];

// Pick a tool (the primitive):
const call = await llm.generateToolCall('Weather in Tokyo in celsius?', tools);
// { name: 'get_weather', arguments: { city: 'Tokyo', unit: 'celsius' } }

// Pick AND run its executor (house-uniform):
const run = await llm.generateWithTools('Weather in Tokyo in celsius?', tools);
// { name: 'get_weather', arguments: { ... }, result: <fetchWeather return> }
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
`synthesize`, …). See the sample app at `examples/electron/RunAnywhereAI/` (repo
root) for chat/streaming, vision, embeddings, and a mic → STT → LLM → TTS → speaker
voice loop.

Renderers that bundle the SDK (webpack/vite) can import the audio helpers:

```js
import { MicRecorder, SpeakerPlayer } from '@runanywhere/electron/audio';
```

## Lifecycle, events, secure store, VAD

```js
RunAnywhere.initialize({ environment: 'production' }); // Phase 1 (sync)
await RunAnywhere.completeServicesInitialization();     // Phase 2 (background services)
RunAnywhere.isInitialized;      // true
RunAnywhere.areServicesReady;   // true

// Subscribe to lifecycle + telemetry events:
RunAnywhere.events.on((e) => {
  if (e.type === 'modelLoaded') console.log('loaded', e.modality, e.id);
  if (e.type === 'generation') console.log('tok/s', e.result.tokensPerSecond);
});

// Encrypted key-value store (Windows DPAPI):
RunAnywhere.secureSet('api-key', 'sk-…');
RunAnywhere.secureGet('api-key'); // -> 'sk-…' (decrypted); null if absent

// Voice activity detection (built-in energy VAD; no model):
const vad = RunAnywhere.createVad();
const speaking = vad.detect(float32Frame); // 16 kHz mono float samples
vad.close();
```

Errors are thrown as `SDKException` (`.code` / `.category` / `.recoverySuggestion`),
uniform across the RunAnywhere SDKs.

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

### Building for GPU (CUDA / NVIDIA)

The default build is CPU-only. To offload inference to an NVIDIA GPU, build with
`-DRAC_GPU_CUDA=ON` (needs the CUDA toolkit **≥ 12.4** and MSVC). This compiles
llama.cpp's CUDA backend; at load time `common_fit_params` auto-offloads as many
layers as fit VRAM — no runtime code changes.

```powershell
# From the repo root. Set CMAKE_CUDA_ARCHITECTURES to your GPU (86 = RTX 30-series).
$env:NVCC_PREPEND_FLAGS = '-allow-unsupported-compiler'   # only if MSVC is newer than the CUDA toolkit officially supports
cmake -S . -B build/windows-cuda -G "Visual Studio 17 2022" -A x64 `
  -T cuda="C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.6" `
  -DRAC_GPU_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86 `
  -DRAC_BUILD_ELECTRON_ADDON=ON -DRAC_BUILD_BACKENDS=ON -DRAC_STATIC_PLUGINS=ON -DRAC_BUILD_SHARED=OFF
cmake --build build/windows-cuda --config Release --target runanywhere_native --parallel
```

Then put the built `runanywhere_native.node` in `prebuilds/win32-x64-cuda/`
beside the DLLs it links: `cudart64_12.dll`, `cublas64_12.dll`,
`cublasLt64_12.dll` (from the CUDA `bin/`) plus `onnxruntime.dll`,
`onnxruntime_providers_shared.dll`, `sherpa-onnx-c-api.dll`. The demo's
`examples/electron/RunAnywhereAI/run-demo-gpu.cmd` launches against that prebuild.

## License

See the repository `LICENSE`.
