# RunAnywhere React Native SDK Documentation

Updated: 2026-07-30
Public API contract: `thoughts/shared/plans/public_api_spec.md` (v3)
Architecture source of truth: `sdk/runanywhere-swift/ARCHITECTURE.md`

The React Native SDK implements the v3 public API spec over native `runanywhere-commons`. TypeScript marshals options and results; lifecycle, auth, device registration, model registry, downloads, imports, storage, and inference orchestration all live in native code.

## Install Shape

```typescript
import { RunAnywhere, SDKEnvironment } from '@runanywhere/core';
```

Backend packages such as `@runanywhere/llamacpp` and `@runanywhere/onnx` only register backends. They do not own downloads, model registry state, storage, or lifecycle orchestration.

## Initialization

Initialization is a single call; there is no second phase to remember.

```typescript
await RunAnywhere.initialize({
  apiKey: 'your-api-key',
  baseUrl: 'https://api.runanywhere.ai',
  environment: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
});
```

`initialize` registers platform adapters, loads native code, and brings commons up, then returns as soon as local inference is usable. Auth, device registration, the model catalog, and telemetry continue in the background and retry on their own; the first call that needs the network joins that work.

| Member | Meaning |
|---|---|
| `RunAnywhere.isReady` | Local inference is usable |
| `RunAnywhere.version` | SDK version |
| `RunAnywhere.deviceId` | Native persistent device identifier (a promise on RN) |
| `RunAnywhere.events` | `AsyncIterable<SdkEvent>` of lifecycle, model, and error breadcrumbs |
| `RunAnywhere.reset()` | Unload models, close sessions, clear state |

## Namespaces

Every capability hangs off a namespace, with spec-named options and results:

| Namespace | Verbs |
|---|---|
| `llm` | `generate`, `generateStream`, `generateStructured`, `tools.register/unregister/list` |
| `vlm` | `generate`, `generateStream` |
| `stt` | `transcribe`, `transcribeStream`, `state` |
| `tts` | `synthesize`, `synthesizeStream`, `speak`, `stop`, `voices` |
| `vad` | `detect`, `detectStream` |
| `embeddings` / `rerank` | `embed` / `rerank` |
| `images` / `diarization` / `segmentation` | `generate`, `generateStream` / `diarize` / `segment` |
| `voice` | `createSession` → `VoiceSession` (`events`, `start`, `say`, `interrupt`, `close`) |
| `rag` | `open` → `RagSession` (`ingest`, `search`, `query`, `queryStream`, `stats`, `clear`, `close`) |
| `models` | `list`, `get`, `register`, `download`, `delete`, `load`, `unload`, `state` |
| `lora` | `apply`, `remove`, `list` |

Generation verbs auto-load, and download when the named model is absent, so `models.load` is for callers who want to control when that cost is paid.

Platform services outside the modality spec stay reachable as their own namespaces: `storage`, `logging`, `auth`, `pluginLoader`, `solutions`, plus `lora.catalog` for adapter registration.

```typescript
const result = await RunAnywhere.llm.generate('Summarize on-device AI.', {
  model: 'smollm2-360m-q8_0',
  temperature: 0.7,
});
console.log(result.text, result.tokensPerSecond);
```

Option defaults are never written in TypeScript. Each option bag merges over the generated `*Defaults()` helper derived from the `rac_default` annotations in `idl/`, so a default has one declaration for all SDKs.

## Streaming

Every `*Stream` verb returns an `AsyncIterable` directly, so there is nothing to await before iterating. Events follow one grammar: `started`, then deltas, then `completed`, with failures thrown into the consumer.

Hermes cannot iterate the Nitro-backed streams with `for await...of`. Drive them manually and call `return()` to cancel:

```typescript
const iterator = RunAnywhere.llm.generateStream(prompt)[Symbol.asyncIterator]();
try {
  let step = await iterator.next();
  while (!step.done) {
    if (step.value.type === 'token') append(step.value.text);
    step = await iterator.next();
  }
} finally {
  await iterator.return?.();
}
```

Cancelling one stream cancels that one request. There are no global cancel verbs.

## Proto-Byte Bridge Pattern

Below the public surface, every bridge call is request/result proto bytes:

```typescript
const requestBytes = ModelLoadRequest.encode(request).finish();
const resultBytes = await NativeRunAnywhere.modelLifecycleLoadProto(requestBytes);
return ModelLoadResult.decode(resultBytes);
```

Avoid new JSON bridge methods for SDK-owned flows.

## Models, Downloads, Imports, And Storage

Native commons owns model paths, registry state, downloads, imports, and storage deletion. `models.register` takes one builder covering a single url, an archive, or a multi-file set; `models.download(id)` reports progress, extraction, and completion through one stream.

Do not reintroduce a JS-owned `DownloadService`, a JS-owned `ModelRegistry`, or `react-native-blob-util` as a model-management path. Apps may build their own download UI, but artifacts enter the registry through the native download and import completion paths.

## Modalities

Each namespace is a thin projection over the commons proto ABI:

- LLM text, thinking content, token counts, and metrics come from the native result and stream payloads.
- Structured output delegates schema validation and orchestration to commons.
- Tool calling keeps JS executors; commons owns parsing, validation, prompt formatting, and the follow-up loop.
- A voice session owns its models, microphone, endpointing, and reply playback. Subscribing to `events` does not open the microphone; `start()` does.
- A RAG session owns its pipeline, and `close()` releases it.
- Plugin loading exposes the commons registry surface, returning a typed unavailable error where dynamic loading is not supported.

## Auth, Device, Events, Logging, Errors

React Native should not persist duplicate SDK auth/device state in JavaScript. Native owns:

- API key/token storage.
- Device ID and vendor ID callbacks.
- Device registration and development build-token registration.
- HTTP setup and auth retries.
- SDK events, telemetry, and native log routing.

Errors should map native `rac_result_t` and structured proto errors to the React Native `SDKException` equivalent. Unsupported hardware or platform features should be explicit typed errors, not silent fallbacks.

## Removed Compatibility Paths

These are stale RN-owned paths and should not be documented as SDK architecture:

- JS `DownloadService` as the SDK model download engine.
- JS `ModelRegistry` as the source of truth for registry/downloaded state.
- `react-native-blob-util` as the SDK artifact downloader.
- JS auth-token/device-registration persistence.
- Old model registry aliases such as `getAvailableModels` or `getDownloadedModels`.
- JSON bridge calls for lifecycle, registry, download, storage, and inference once proto-byte equivalents exist.
- JS thinking-token helpers, JS structured-output orchestration, and JS tool-calling run loops that duplicate native commons.

## Validation

Documentation-only changes are verified by review. Code alignment PRs should include:

```bash
yarn workspace @runanywhere/core typecheck
yarn workspace @runanywhere/llamacpp typecheck
yarn workspace @runanywhere/onnx typecheck
yarn workspace runanywhere-ai-example typecheck
```

Full validation requires fresh install, continuous logs, model download, model load, real inference for the changed modalities, screenshots, and log review on Android and iOS. Build/install/launch is smoke evidence only.
