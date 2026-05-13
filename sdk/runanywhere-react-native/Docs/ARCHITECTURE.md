# RunAnywhere React Native SDK Architecture

Updated: 2026-05-13
Source of truth: `sdk/runanywhere-swift/ARCHITECTURE.md`
Status: target architecture for React Native Swift parity.

React Native is a thin TypeScript and native bridge over `runanywhere-commons`. The Swift SDK is the canonical implementation for platform structure, public API names, bridge ownership, initialization, and service orchestration. React Native should match Swift unless a React Native runtime constraint makes that impossible; those exceptions must be typed native-unavailable errors, not alternate JS business logic.

## Architecture Decisions

- Swift parity is the product contract. React Native public APIs, folder names, bridge slices, and lifecycle behavior align to Swift.
- Proto bytes are the native bridge contract. TypeScript may create and decode generated proto messages, but native bridges receive and return encoded request/result bytes.
- Initialization is two-phase. Phase 1 is synchronous native core setup; Phase 2 is asynchronous service setup and can fall back to offline mode.
- Native owns SDK state. Auth, device identity, device registration, downloads, model paths, storage, model registry discovery, telemetry, logging sinks, and lifecycle state live in native commons-backed code.
- TypeScript is a facade. It validates ergonomic inputs, maps generated types, subscribes to events, and forwards proto bytes to native.
- No compatibility layer is preserved for stale RN-specific APIs. Old JS-owned paths are deleted when replaced by Swift-shaped APIs.

## Target Package Shape

```
sdk/runanywhere-react-native/
├── Docs/
│   ├── ARCHITECTURE.md
│   └── Documentation.md
├── packages/
│   ├── core/
│   │   ├── src/
│   │   │   ├── Public/              # RunAnywhere namespace and Swift-shaped extensions
│   │   │   ├── Foundation/          # Bridge, Errors, Security, Constants, Core helpers
│   │   │   ├── Generated/           # Proto-generated TS plus convenience wrappers
│   │   │   ├── Infrastructure/      # Events/logging facade over native ownership
│   │   │   ├── Adapters/            # Streaming adapters, handle adapters
│   │   │   ├── Features/            # System-backed RN feature facades
│   │   │   └── specs/               # Nitro specs for proto-byte bridge calls
│   │   ├── cpp/                     # HybridObjects and bridge slice implementations
│   │   ├── ios/                     # Swift/Obj-C platform adapter and native bridge glue
│   │   ├── android/                 # Kotlin/JNI platform adapter and native bridge glue
│   │   └── nitrogen/                # Generated Nitro bindings
│   ├── llamacpp/                    # Thin LlamaCPP backend registration package
│   └── onnx/                        # Thin ONNX/Sherpa backend registration package
└── package.json
```

`@runanywhere/core` owns the SDK facade and commons bridge. Backend packages do not own model lifecycle, registries, downloads, or orchestration; they only register backend availability and ship backend-specific binaries/glue.

## Runtime Layers

| Layer | Owner | Responsibility |
|---|---|---|
| TypeScript public API | `packages/core/src/Public` | Swift-named facade methods, generated proto helpers, event subscriptions |
| TypeScript adapters | `Adapters`, `Infrastructure`, `Features` | Stream/event conversion and RN-friendly wrappers without business orchestration |
| Nitro/JSI specs | `specs`, `cpp` | Proto-byte request/result bridge methods and native event handles |
| Platform glue | `ios`, `android` | Platform adapter slots for files, HTTP, secure storage, logging, device, memory, archive, downloads |
| Commons/core | `runanywhere-commons` | SDK lifecycle, auth, device registration, registry, downloads, storage, inference routing, events |
| Backend packages | `llamacpp`, `onnx` | Backend libraries and registration only |

## Two-Phase Initialization

React Native follows Swift's lifecycle:

1. Phase 1 runs synchronously enough to make the C ABI callable. It registers the platform adapter, configures logging, stores init params in native secure storage where required, resolves the native documents/model base directory, and calls the commons Phase 1 proto entry point.
2. Phase 1 sets the public initialized flag after native setup succeeds.
3. Phase 2 runs once through a serialized native-backed task. It configures HTTP/auth, performs device registration and model assignment fetches, discovers downloaded models through the native registry, and marks services ready.
4. Phase 2 errors are non-fatal for offline operation. They must be surfaced as typed events/logs and should not roll back Phase 1.

Any API that needs online assignments, downloaded model discovery, or model lifecycle state must await services readiness or return the same typed unavailable/not-ready error Swift returns.

## Native Bridge Contract

React Native bridge methods use encoded proto payloads, not ad hoc JSON or per-field argument lists. The expected shape is:

```typescript
const requestBytes = ModelLoadRequest.encode(request).finish();
const resultBytes = await NativeRunAnywhere.loadModel(requestBytes);
const result = ModelLoadResult.decode(resultBytes);
```

Bridge slices should be organized by the same concepts Swift documents for `CppBridge`: SDK init, state, auth, device, HTTP, model registry, model lifecycle, downloads, storage, events, logging, LLM, STT, TTS, VAD, VLM, RAG, tool calling, structured output, LoRA, solutions, voice agent, and plugin loading.

The bridge should not expose legacy helpers such as `getAvailableModels`, `getDownloadedModels`, JS thinking-token parsers, JS tool-call run loops, or JSON-based lifecycle methods once the Swift-shaped proto entry exists.

## Native-Owned Services

The following are SDK-owned native paths:

- Auth token storage and auth state.
- Device ID, vendor ID callbacks, registration, and dev-mode build-token registration.
- Model-path base directory resolution.
- Model registry discovery/query/import.
- Download planning, start, progress, polling, cancellation, completion import, and storage flags.
- Storage analysis and delete operations.
- Event emission, logging destinations, telemetry, and error mapping.

The following are not SDK-owned JS paths:

- A TypeScript `DownloadService` as the source of truth for model downloads.
- A TypeScript `ModelRegistry` as the source of truth for registry state.
- `react-native-blob-util` as the SDK download engine.
- Duplicate JS persistence for auth tokens, device registration, or downloaded model state.

Apps may still provide their own file pickers, UI progress display, or non-SDK downloads, but SDK model lifecycle uses native commons-backed APIs.

## Public API Shape

`RunAnywhere` is the single public namespace. Capability files should mirror Swift extension areas and expose Swift-named APIs. Canonical areas include:

- Initialization and SDK state.
- Models, model lifecycle, model import, downloads, and storage.
- LLM generation/streaming, structured output, tool calling, RAG, VLM.
- STT, TTS, VAD, voice agent, audio capture/playback wrappers where RN supports them.
- LoRA, solutions, plugin loader, events, logging, telemetry, device, auth.

Convenience wrappers are allowed only when they are thin overloads over the canonical proto request/result surface. Backwards-compatible aliases for old RN names should be removed during alignment.

## Error, Event, And Logging Rules

- Native `rac_result_t`, structured proto errors, and thrown platform errors map to `SDKException`-equivalent typed JS errors.
- Missing hardware, unsupported plugin loading, or unavailable platform functionality returns typed unavailable errors instead of silent fallback.
- Event names and payload ownership follow Swift's SDK event model. TypeScript may adapt subscriptions for React Native ergonomics but should not synthesize divergent lifecycle facts.
- Logging controls mirror Swift and route native logs to the RN-visible logging bridge.

## Verification

Documentation-only edits do not require build gates. Code alignment PRs must at minimum run:

```bash
yarn workspace @runanywhere/core typecheck
yarn workspace @runanywhere/llamacpp typecheck
yarn workspace @runanywhere/onnx typecheck
yarn workspace runanywhere-ai-example typecheck
```

A full React Native pass requires fresh uninstall/install, continuous Android/iOS logs, model download, model load, real inference for the exposed modality under test, screenshots, and reviewed logs. Build/install/launch alone is smoke validation.
