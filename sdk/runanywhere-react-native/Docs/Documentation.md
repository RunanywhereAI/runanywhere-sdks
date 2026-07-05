# RunAnywhere React Native SDK Documentation

Updated: 2026-05-13
Source of truth: `sdk/runanywhere-swift/ARCHITECTURE.md`
Status: target public documentation for Swift-parity React Native alignment.

The React Native SDK exposes a Swift-shaped API over native `runanywhere-commons` services. TypeScript is a facade over generated protobuf request/result types and native bridge calls. SDK-owned lifecycle, auth, device registration, model registry, downloads, imports, storage, and inference orchestration are native-owned.

## Install Shape

```typescript
import { RunAnywhere, SDKEnvironment } from '@runanywhere/core';
```

Backend packages such as `@runanywhere/llamacpp` and `@runanywhere/onnx` are thin backend-registration packages. They do not own downloads, model registry state, storage, or lifecycle orchestration.

## Initialization

React Native follows Swift's two-phase initialization contract.

```typescript
await RunAnywhere.initialize({
  apiKey: 'your-api-key',
  baseURL: 'https://api.runanywhere.ai',
  environment: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
});

await RunAnywhere.completeServicesInitialization();
```

Phase 1 registers native platform adapters, configures native state, resolves model storage paths, and calls commons Phase 1. Phase 2 configures HTTP/auth, registers the device when needed, fetches assignments, discovers downloaded models, and marks services ready. Phase 2 may fall back to offline mode, matching Swift.

Public state should mirror Swift:

| Property | Meaning |
|---|---|
| `RunAnywhere.isInitialized` | Phase 1 completed and native ABI is callable |
| `RunAnywhere.areServicesReady` | Phase 2 completed |
| `RunAnywhere.isActive` | SDK has initialized params and Phase 1 is active |
| `RunAnywhere.version` | SDK version |
| `RunAnywhere.environment` | Current SDK environment |
| `RunAnywhere.deviceId` | Native persistent device identifier |
| `RunAnywhere.isAuthenticated` | Native auth state |
| `RunAnywhere.events` | SDK event bus facade |

## Proto-Byte API Pattern

Canonical lifecycle and modality APIs are request/result based. TypeScript constructs generated proto messages and native bridges receive encoded bytes.

```typescript
const result = await RunAnywhere.loadModel(ModelLoadRequest.fromPartial({
  modelId: 'smollm2-360m-q8_0',
  category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
}));
```

Bridge internals should follow this pattern:

```typescript
const requestBytes = ModelLoadRequest.encode(request).finish();
const resultBytes = await NativeRunAnywhere.loadModel(requestBytes);
return ModelLoadResult.decode(resultBytes);
```

Avoid new JSON bridge methods for SDK-owned flows. Delete old RN-specific compatibility aliases when the Swift-shaped method exists.

## Models, Downloads, Imports, And Storage

Native commons owns model paths, registry state, downloads, imports, and storage deletion. React Native should expose Swift-equivalent methods such as:

| Area | Canonical surface |
|---|---|
| Registry | `listModels`, `queryModels`, `getModel`, `downloadedModels`, `registerModel` |
| Lifecycle | `loadModel(ModelLoadRequest)`, `unloadModel`, lifecycle status/current model queries |
| Downloads | plan/start/progress/poll/cancel/complete methods matching Swift request/result semantics |
| Imports | `importModel` and completed-download import flows with managed-storage flags |
| Storage | storage analysis and delete APIs backed by native storage requests |

Do not document or reintroduce JS-owned `DownloadService`, JS-owned `ModelRegistry`, or `react-native-blob-util` as SDK model-management paths. Apps may use their own download UI, but SDK model artifacts enter the registry through native import/download completion APIs.

## Modalities

All modalities should be thin wrappers over native commons-backed proto APIs:

- LLM generation and streaming read generated text, token counts, thinking fields, metrics, and events from native result/event payloads.
- Structured output delegates schema validation/orchestration to native commons.
- Tool calling keeps JS tool executors, while native owns parsing, validation, formatting, follow-up orchestration, and result envelopes.
- RAG exposes Swift-equivalent resolved configuration helpers and model-info/model-id overloads.
- STT, TTS, VAD, VLM, and VoiceAgent use Swift-equivalent request/result types, readiness checks, cancellation semantics, and typed unavailable errors.
- LoRA and Solutions use flattened Swift-named APIs.
- Plugin loading should expose the Swift surface; if dynamic plugin loading is not supported in RN mobile, return the typed unavailable error.

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
