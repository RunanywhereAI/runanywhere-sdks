# RunAnywhere Electron SDK

On-device **LLM, VLM, STT, TTS, and embeddings** for Electron and Node on Windows. The SDK is a native N-API addon over the RunAnywhere `rac_*` C ABI and llama.cpp / ONNX Runtime / Sherpa-ONNX. Inference runs in an isolated Electron **utility process**, streaming results to the renderer over a `MessagePort`.

> **Status:** Unpublished preview (`private: true`, version `0.1.0`). **Windows x64 only** — not available on npm. Build from source in this repository.

## Capabilities

- LLM text generation (streaming, structured JSON, tool calling, multi-turn chat)
- VLM image understanding
- STT, TTS, embeddings, and voice-agent pipeline
- Model catalog with auto-download
- Encrypted secure store (Windows DPAPI)
- Built-in energy VAD

## Build from source

This package is not published to npm. Clone the repository and build the native addon on Windows:

```bash
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/sdk/runanywhere-electron
npm install
npm run build
npm run bundle:native   # copies .node + DLLs into prebuilds/win32-x64/
```

Prerequisites: MSVC, Node.js, and a `windows-release` build of `runanywhere-commons` with backends enabled. See [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md) for CUDA builds, integration tests, and contributor details.

## Quick start (Node)

After building, require the local package from your app or the example:

```js
const { RunAnywhere } = require('@runanywhere/electron');

RunAnywhere.initialize();
const llm = await RunAnywhere.loadLLM('qwen2.5-0.5b'); // catalog id or local path
for await (const t of llm.generate('Explain on-device AI in one sentence.')) {
  process.stdout.write(t);
}
llm.unload();
RunAnywhere.shutdown();
```

Point at a custom native build with `RUNANYWHERE_NATIVE_PATH` if you are not using `prebuilds/win32-x64/`.

### Structured output

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
```

### Tool calling

```js
const tools = [{
  name: 'get_weather',
  description: 'Current weather for a city',
  parameters: {
    type: 'object',
    properties: { city: { type: 'string' } },
    required: ['city'],
  },
  execute: ({ city }) => fetchWeather(city),
}];

const run = await llm.generateWithTools('Weather in Tokyo?', tools);
// { name, arguments, result }
```

### Multi-turn chat

```js
const chat = RunAnywhere.createChat(llm, { system: 'You are concise.' });
await chat.sendText('My name is Aman.');
await chat.sendText('What is my name?');
```

## Electron (utility-process isolation)

> **Not LAN Connect.** `RunAnywhereMain.connect(webContents)` wires a **local** `MessagePort` between the renderer and an Electron **utility process** that hosts the native addon. It does **not** advertise or join RunAnywhere’s LAN Connect protocol (`_runanywhere-connect._tcp`). LAN Connect hosting/clients are native Swift/Kotlin only in this release; see the [root README Connect section](../../README.md#connect-trusted-lan).

**Main process:**

```js
const { RunAnywhereMain } = require('@runanywhere/electron/main');
const ra = new RunAnywhereMain({ nativePath: /* optional path to .node */ });
win.webContents.on('did-finish-load', () => ra.connect(win.webContents));
```

**Renderer preload** — set `webPreferences.preload` to `@runanywhere/electron/preload`. It exposes `window.runanywhere` with async APIs (`loadLLM`, `generate`, `transcribe`, `synthesize`, …).

Renderers that bundle the SDK can import audio helpers:

```js
import { MicRecorder, SpeakerPlayer } from '@runanywhere/electron/audio';
```

When packaging with electron-builder, unpack native artifacts from the asar:

```jsonc
"asarUnpack": ["**/node_modules/@runanywhere/electron/prebuilds/**"]
```

## Model catalog

`loadLLM`, `loadVLM`, `loadEmbedder`, `loadSTT`, and `loadTTS` accept a catalog id (auto-downloaded on first use) or a local path. Built-in ids include `smollm2-135m`, `qwen2.5-0.5b`, `smolvlm-256m`, `minilm`, `whisper-tiny`, and `piper-lessac`.

## Example application

From the repo root on Windows:

```cmd
examples\electron\RunAnywhereAI\run-demo.cmd
```

Or:

```cmd
set RUNANYWHERE_NATIVE_PATH=sdk\runanywhere-electron\prebuilds\win32-x64\runanywhere_native.node
npx electron examples/electron/RunAnywhereAI
```

The example covers chat/streaming, vision, embeddings, and a mic → STT → LLM → TTS → speaker voice loop. Source: `examples/electron/RunAnywhereAI/`.

## Errors

Failures throw `SDKException` with `.code`, `.category`, and `.recoverySuggestion`, consistent with other RunAnywhere SDKs.

## Support

- Documentation: [docs.runanywhere.ai](https://docs.runanywhere.ai)
- Discord: [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd)
- Email: [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

## Contributing

Build and test details: [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md).

## License

See the repository [LICENSE](../../LICENSE).
