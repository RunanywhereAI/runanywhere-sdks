# @runanywhere/electron

On-device LLM, VLM, STT, TTS, VAD, embeddings, and RAG for Electron and Node. It
is a thin binding over the C++ `runanywhere-commons` core: the addon and the
TypeScript facade marshal typed requests to and from commons, which does all the
inference. The public surface mirrors the Swift SDK, so the same code reads the
same across platforms.

## Install

The package ships prebuilt native addons, so no local toolchain is needed to use
it. It depends on the shared `@runanywhere/proto-ts` types.

```
npm install @runanywhere/electron
```

Platforms: macOS, Windows, and Linux on x64 and arm64. Node 20 or newer.

## Quick start

The SDK runs the same way in the main process and the renderer. In the main
process you talk to the addon directly through `NativeBackend`:

```ts
import { createRunAnywhere, NativeBackend, loadAddon } from '@runanywhere/electron';

const ra = createRunAnywhere(new NativeBackend(loadAddon()));
await ra.initialize();

await ra.models.register({ id: 'qwen2.5-0.5b', path: '/path/to/model.gguf' });
await ra.models.load('qwen2.5-0.5b');

const result = await ra.llm.generate('What is the capital of Japan?', { maxOutputTokens: 16 });
console.log(result.text); // "Tokyo"

for await (const event of ra.llm.generateStream('List three colors.')) {
  if (!event.isFinal) process.stdout.write(event.token);
}
```

Heavy inference should not run on the main thread. The recommended setup forks a
utility process that owns the addon and wires it to the renderer over a
MessagePort (see the process model below).

## Process model

`process.dlopen` is not thread-safe, so the native addon runs in a dedicated
`utilityProcess`, never in the main process or a worker thread. Tokens stream
straight from the utility to the renderer over a `MessageChannelMain` port, so
they do not hop through the main process per token.

- Main process: `import { RunAnywhereMain } from '@runanywhere/electron/main'`.
  It forks the utility, brokers a port to each window, and re-forks after a
  crash.
- BrowserWindow preload: `import '@runanywhere/electron/preload'`. It speaks the
  RPC protocol to the utility and exposes one transport function on
  `window.runanywhereRpc`.
- Renderer: `import { connectRenderer } from '@runanywhere/electron'` and call
  `connectRenderer()` to get the same `RunAnywhereApi` the main process has. The
  facade runs in the page's own world; only the transport crosses the bridge.

The renderer contract requires CommonJS preload scripts, which is why the package
ships as CommonJS.

## The surface

`initialize`, `reset`, `isReady`, `version`, `deviceId`, `environment`,
`capabilities`, `events`, plus fourteen namespaces: `llm`, `vlm`, `stt`, `tts`,
`vad`, `embeddings`, `rerank`, `images`, `diarization`, `segmentation`, `voice`,
`rag`, `models`, `lora`.

What is wired to commons today: `llm` (generate, stream, cancel), `vlm` (generate,
stream, cancel), `stt` (transcribe), `tts` (synthesize, stop), `vad` (configure,
process, reset, using the built-in energy detector), `embeddings` (embed),
`diarization` (diarize), `segmentation` (segment), `rag` (open a session, then
ingest, query, stats, clear, close), and `models` (register, download, load,
unload).

What reports its limitation instead of pretending to work: `rerank`, `voice`, and
`lora` throw `NOT_IMPLEMENTED`, and `images` throws `FEATURE_NOT_AVAILABLE` (no
image-generation backend is linked). LLM tool calling, live incremental STT
streaming, and grammar-constrained structured decoding are not wired yet either.

## Resource management

Native handles are released explicitly. Session objects (a RAG session, for
example) expose `close()` and support `await using` for scope-based cleanup:

```ts
await using session = await ra.rag.open({ embeddingModelId, llmModelId });
await session.ingest({ id: 'doc1', text });
const answer = await session.query('...');
// released at scope exit
```

A `FinalizationRegistry` frees a handle a caller forgot to release and logs a
warning, but it is a backstop, not the path to rely on. Underneath, the addon
holds each in-flight native call under a lease so an unload or shutdown waits for
the call to finish rather than freeing state out from under it.

## Structured output

Structured output uses commons' schema-in-prompt plus post-generation parse and
validation, the same approach as the Swift SDK. It does not constrain decoding, so
malformed output surfaces a validation error rather than being repaired.

## Hardware

The GPU backend is a compile-time choice in commons, reported by
`capabilities().device`.

- macOS uses llama.cpp with Metal, enabled by default.
- CUDA is an opt-in Windows and Linux build variant.
- CPU is the floor everywhere.

MLX is not used here: the commons MLX engine forwards to a Swift runtime that
Electron does not host, so its registration is refused without that provider.
WebGPU is a possible renderer-side fallback but is not part of the inference path
today.

## Build from source

Requires the commons native build. The addon is a CMake target under
`native/`, built via the root `CMakePresets.json`. On macOS:

```
cmake --preset rcli-macos-release -DRAC_BUILD_ELECTRON_ADDON=ON
cmake --build --preset rcli-macos-release --target runanywhere_native
```

TypeScript:

```
npm run build       # tsc -> dist
npm run typecheck
npm test            # hermetic unit tests
npm run test:integration   # needs RUNANYWHERE_NATIVE_PATH and a local model
```

## Status

Verified on macOS arm64 (Apple M4 Pro, Metal): LLM, VLM, STT, TTS, embeddings,
and VAD all produce correct output against real models through the facade.
Windows and Linux build through the same CMake targets but are not yet verified
here. The example app migration to this surface is tracked separately.
