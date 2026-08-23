# RunAnywhere Electron SDK

On-device **LLM, VLM, STT, TTS, and embeddings** for Electron and Node. The SDK is a native N-API addon over the RunAnywhere `rac_*` C ABI and llama.cpp / ONNX Runtime / Sherpa-ONNX. Inference runs in an isolated Electron **utility process**, streaming results to the renderer over a `MessagePort`.

> **Status:** Published on npm. Native prebuilds ship for `darwin-arm64` and `win32-x64` (llama.cpp / ONNX / Sherpa) and for `win32-arm64` (QHexRT on the Qualcomm Hexagon NPU, via `@runanywhere/electron-qhexrt`). Linux builds from source.

## Capabilities

- LLM text generation (streaming, structured JSON, tool calling, multi-turn chat)
- VLM image understanding
- STT, TTS, embeddings, and voice-agent pipeline
- Model catalog with auto-download
- Encrypted secure store (Windows DPAPI)
- Built-in energy VAD

## Install

```bash
npm install @runanywhere/electron
npm install @runanywhere/electron-llamacpp @runanywhere/electron-onnx @runanywhere/electron-sherpa
npm install @runanywhere/electron-qhexrt   # Hexagon NPU, win32-arm64
```

Every backend package can be declared unconditionally. One with no payload for the
running platform records a path that does not exist, and the existence filter drops
it before the utility host forks, so it never loads and never appears in
`capabilities().backends`.

## Build from source

Only needed for Linux, or to run against local native changes:

```bash
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/bindings/electron
npm install
npm run build
npm run bundle:native   # stages the built .node + libs into prebuilds/<platform>-<arch>/
```

`bundle:native` compiles only itself (`tsconfig.bundle.json`), so it runs on a machine
that builds natives and never builds the SDK's TypeScript. Point it at a specific CMake
tree with `RA_NATIVE_DIR`, and stage the QAIRT runtime into the qhexrt package with
`RA_QNN_RUNTIME_DIR`.

Prerequisites: a C++ toolchain (MSVC on Windows), Node.js, and a `runanywhere-commons`
build with backends enabled. See the `electron-*` presets in `CMakePresets.json` for CUDA
builds, integration tests, and contributor details.

## Quick start (Node)

One `initialize` brings up the native runtime, the model store, and the secure
store. Generation verbs load (and download) whatever `options.model` names, so
there is nothing else to arrange.

```js
const { RunAnywhere } = require('@runanywhere/electron');

await RunAnywhere.initialize();

for await (const event of RunAnywhere.llm.generateStream(
  'Explain on-device AI in one sentence.',
  { model: 'qwen2.5-0.5b' }        // catalog id, HuggingFace repo, URL, or local path
)) {
  if (event.type === 'token') process.stdout.write(event.text);
  if (event.type === 'completed') console.log('\n', event.result.tokensPerSecond, 'tok/s');
}

await RunAnywhere.reset();
```

`apiKey` and `baseUrl` drive authentication and telemetry on a desktop-control-plane
build (`RAC_DESKTOP_ADAPTER=ON`): `initialize` runs the two-phase handshake over the
bundled libcurl transport. On an inference-only build they are accepted and ignored.
`deviceId` is the persistent id commons mints once the control plane runs, otherwise a
locally-minted fallback.

Point at a custom native build with `RUNANYWHERE_NATIVE_PATH` if you are not using
the bundled prebuild.

### Structured output

```js
const r = await RunAnywhere.llm.generateStructured(
  'Extract the person: "Ada Lovelace, 36, English mathematician."',
  {
    type: 'object',
    properties: {
      name: { type: 'string' },
      age: { type: 'integer' },
      interests: { type: 'array', items: { type: 'string' }, maxItems: 5 },
    },
    required: ['name', 'age', 'interests'],
  }
);
console.log(r.value, r.valid);
```

### Tool calling

Register a tool once, then generate. When the model picks it, the SDK runs the
executor and continues the loop up to `options.maxToolCalls`.

```js
RunAnywhere.llm.tools.register(
  {
    name: 'get_weather',
    description: 'Current weather for a city',
    parameters: { type: 'object', properties: { city: { type: 'string' } }, required: ['city'] },
  },
  ({ city }) => fetchWeather(city)
);

const r = await RunAnywhere.llm.generate('Weather in Tokyo?', { toolChoice: 'REQUIRED' });
console.log(r.toolCalls[0]);   // { id, name, arguments, result }
```

Registered tools apply to every request. Pass `toolChoice: 'NONE'` on requests that
should skip the selection round.

### Multi-turn chat

Pass the conversation; the SDK owns the chat template and history alternation.

```js
const r = await RunAnywhere.llm.generate([
  { role: 'system', content: 'You are concise.' },
  { role: 'user', content: 'My name is Aman.' },
  { role: 'assistant', content: 'Noted.' },
  { role: 'user', content: 'What is my name?' },
]);
```

### Other namespaces

`vlm`, `stt`, `tts`, `vad`, `embeddings`, `rerank`, `diarization`, `segmentation`,
`voice`, `rag`, `models`, `lora`, and `images` follow the same shape. `images`
throws: no diffusion backend is linked and `rac_diffusion_generate_proto` is not
bound in the addon.

The pre-v3 surface (`RunAnywhere.loadLLM`, `Chat`, `VoiceAgent`, `EventBus`,
handle objects) has been removed. `createRunAnywhere` is the whole API.

## Electron (utility-process isolation)

> **Not LAN Connect.** `RunAnywhereMain.connect(webContents)` wires a **local** `MessagePort` between the renderer and an Electron **utility process** that hosts the native addon. It does **not** advertise or join RunAnywhere’s LAN Connect protocol (`_runanywhere-connect._tcp`). LAN Connect hosting/clients are native Swift/Kotlin only in this release; see the [root README Connect section](../../README.md#connect-trusted-lan).

**Main process:**

```js
const { RunAnywhereMain } = require('@runanywhere/electron/main');
const ra = new RunAnywhereMain({ nativePath: /* optional path to .node */ });
win.webContents.on('did-finish-load', () => ra.connect(win.webContents));
```

**Renderer preload:** set `webPreferences.preload` to
`@runanywhere/electron/preload`. It builds `window.runanywhere` with the same shape
the main process gets, so renderer and main code are written once. Two Electron
constraints shape how it does that:

- `contextBridge` hands the page a frozen clone and does not proxy accessors, so
  the preload assembles the page object in the main world via
  `contextBridge.executeInMainWorld` and backs `isReady`, `version`, `deviceId`,
  `environment`, and `events` with live getters. Without that API those five are
  unavailable in the renderer and the SDK logs a warning.
- Symbol keys do not cross the bridge, so `for await...of` cannot iterate a bridged
  stream. Call `next()` until `done`.

Tool executors passed from a renderer run in the renderer. They cannot reach the
native addon directly.

Renderers that bundle the SDK can import audio helpers:

```js
import { MicRecorder, SpeakerPlayer } from '@runanywhere/electron/audio';
```

When packaging with electron-builder, unpack native artifacts from the asar:

```jsonc
"asarUnpack": ["**/node_modules/@runanywhere/electron/prebuilds/**"]
```

## Model catalog

`models.load(id)` and the `model:` option on a generation accept a catalog id (downloaded on first use) or a registered local path. Built-in ids include `smollm2-135m`, `qwen2.5-0.5b`, `smolvlm-256m`, `minilm`, `whisper-tiny`, and `piper-lessac`.

## Example application

The TypeScript demo app lives in its own repository:
[RunanywhereAI/runanywhere-electron](https://github.com/RunanywhereAI/runanywhere-electron).

```bash
git clone https://github.com/RunanywhereAI/runanywhere-electron
cd runanywhere-electron
npm install
npm start          # CPU
npm run start:gpu  # CUDA (when the GPU prebuild is present)
```

On Windows you can also double-click `RunAnywhere AI.cmd` / `RunAnywhere AI (GPU).cmd`.
The example covers chat/streaming, vision, embeddings, and a mic → STT → LLM → TTS → speaker voice loop.

## Errors

Failures throw `SDKException` with `.code`, `.category`, and `.recoverySuggestion`, consistent with other RunAnywhere SDKs.

## Support

- Documentation: [docs.runanywhere.ai](https://docs.runanywhere.ai)
- Discord: [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd)
- Email: [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

## Contributing

Build and test details: this file's Build section plus the `electron-*` presets in `CMakePresets.json` (each carries its own doc comment).

## License

See the repository [LICENSE](../../LICENSE).
