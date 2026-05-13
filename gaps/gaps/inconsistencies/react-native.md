# React Native SDK - Swift Alignment Inconsistencies

Updated: 2026-05-13
Scope: `sdk/runanywhere-react-native/`
Source of truth: `sdk/runanywhere-swift/ARCHITECTURE.md`

React Native must align to Swift as the canonical SDK implementation. This backlog is deletion-forward: replace stale RN-specific JS ownership with Swift-shaped native commons ownership, and do not preserve backwards-compatible aliases unless they are explicitly documented as thin convenience wrappers.

Do not touch Kotlin, Flutter, or unrelated platform work in this stream.

## Current Decisions

- Public API, folder organization, bridge slices, initialization, and service ownership follow Swift.
- Nitro/JSI bridge calls for SDK-owned flows should pass proto bytes and return proto bytes.
- TypeScript owns ergonomic facades, generated proto encode/decode, subscriptions, and UI-friendly adapters only.
- Native owns auth, device, HTTP setup, downloads, model registry, model paths, storage, telemetry, logging, lifecycle, and orchestration.
- No JS `DownloadService`, JS `ModelRegistry`, or `react-native-blob-util` path should remain documented as SDK-owned model management.
- No backwards-compatibility requirement exists for old RN-only API names.

## High-Priority Backlog

### RN-SWIFT-001: File organization must mirror Swift

Move React Native public extensions and foundation folders toward Swift's `Public`, `Foundation`, `Generated`, `Adapters`, `Infrastructure`, `Features`, and bridge-slice concepts. Backend packages stay thin.

### RN-SWIFT-002: Initialization must be native two-phase init

Expose native Phase 1 and Phase 2 bridge calls that map to commons init proto entry points. Serialize Phase 2, expose `isInitialized` and `areServicesReady`, and require readiness for flows that need discovered models or online setup.

### RN-SWIFT-003: Platform adapter ownership is incomplete

React Native native code must provide the Swift-equivalent platform adapter slots for file I/O, secure storage, logging, device identity, HTTP/download, archive extraction, memory, clock, and directory enumeration.

### RN-SWIFT-004: Auth and device state are duplicated in JS

Delete JS-owned token/device registration persistence. Native commons-backed auth/device state is the source of truth; TypeScript exposes status and typed errors only.

### RN-SWIFT-005: Downloads and registry remain too JS-owned

Replace SDK-owned JS download/registry behavior with native plan/start/progress/poll/cancel/import/discover flows. Remove `react-native-blob-util` as the SDK model artifact engine.

### RN-SWIFT-006: Model storage/delete/import must use native proto requests

Set the native model base directory before registry/download use. Use Swift-equivalent import, lifecycle, storage analysis, and delete request/result types; delete paths must actually remove native files.

### RN-SWIFT-007: Bridge APIs must be proto-byte based

Replace JSON and per-field bridge calls for lifecycle, registry, download, storage, inference, and modality orchestration with encoded generated proto requests/results.

### RN-SWIFT-008: Public model API names must be Swift-canonical

Keep `listModels`, `queryModels`, `getModel`, `downloadedModels`, `registerModel`, `importModel`, and `loadModel(ModelLoadRequest)`. Delete old RN names such as `getAvailableModels` and `getDownloadedModels`.

### RN-SWIFT-009: Events, logging, and errors must match Swift ownership

Route native SDK events/logs/errors through RN facades. Map native result/proto errors to typed JS `SDKException` equivalents. Unsupported hardware/platform features must surface typed unavailable errors, not silent fallbacks.

### RN-SWIFT-010: LLM helpers duplicate native result fields

Delete old thinking helper RPCs and JS parsers. Read thinking content/tokens, response tokens, text, metrics, and streaming events from native proto results/events.

### RN-SWIFT-011: Structured output and tool calling are over-orchestrated in JS

Keep JS tool executors, but move parse/format/validate/follow-up orchestration and structured-output handling to native commons-backed proto flows.

### RN-SWIFT-012: Modalities need Swift readiness and failure semantics

STT, TTS, VAD, VLM, RAG, VoiceAgent, LoRA, Solutions, and PluginLoader should expose Swift-shaped request/result APIs, readiness checks, cancellation behavior, and typed unsupported errors.

## Verification Requirements

Minimum static gates for code PRs:

```bash
yarn workspace @runanywhere/core typecheck
yarn workspace @runanywhere/llamacpp typecheck
yarn workspace @runanywhere/onnx typecheck
yarn workspace runanywhere-ai-example typecheck
```

Full pass requires clean install, continuous logs, model download, model load, real inference for the changed RN modality set, screenshots, and reviewed logs on Android and iOS. Build/install/launch alone is smoke validation.
