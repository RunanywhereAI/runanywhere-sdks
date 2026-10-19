# Cross-SDK parity reference

Linked from `AGENTS.md`. A side-by-side comparison of how each SDK implements the same
cross-cutting concerns — useful when porting a fix from one SDK to another or auditing
that all five stayed in sync after a change.

| Concern | iOS Swift | Kotlin (Android) | Flutter | React Native | Web |
|---------|-----------|------------------|---------|-------------|-----|
| Entry point | `enum RunAnywhere` | `object RunAnywhere` | `RunAnywhere` (final class, static members) | `RunAnywhere` object | `RunAnywhere` object |
| Bridge layer | `CppBridge` enum + extensions | `CppBridge` object + extensions | `DartBridge` + `DartBridge*.dart` | `HybridRunAnywhereCore` (Nitro) | `LlamaCppBridge` + `SherpaONNXBridge` |
| Streaming | `AsyncStream` | `Flow` | `Stream` (`StreamController`) | `AsyncIterable` (manual iteration) | `AsyncIterable` |
| Events | `EventBus` (Combine) | `EventBus` (SharedFlow) | `EventBus` (broadcast `StreamController`) | `EventBus` (NativeEventEmitter) | `EventBus` (custom pub/sub) |
| Secure storage | Keychain | Android Keystore | Keychain (iOS) / Keystore + atomic no-backup files (Android) | Keychain (iOS) / Keystore (Android) | localStorage — **not secure**, no secrets belong here |
| HTTP transport | URLSession | OkHttp | OkHttp (Android) / URLSession (iOS) | OkHttp (Android) / URLSession (iOS) | `emscripten_fetch` / `fetch()` |

## Model-registry refresh

The public refresh operation reconciles commons' model registry with local artifacts. The
defaults and best-effort failure behavior follow Swift's `models.refresh` implementation.

| SDK | Public entry point | Defaults (`rescanLocal`, `includeRemoteCatalog`, `pruneOrphans`) | Completion and failures |
|-----|--------------------|-----------------------------------------------|-------------------------|
| Swift | `RunAnywhere.models.refresh(...)` | `true`, `false`, `false` | `async`, returns `Void`; no-op before initialization and logs/contains refresh errors. |
| Kotlin | `RunAnywhere.models.refresh(...)` | `true`, `false`, `false` | `suspend`, returns `Unit`; best-effort. |
| Flutter | `RunAnywhere.models.refresh(...)` | `true`, `false`, `false` | `Future<void>`; best-effort. |
| React Native | `RunAnywhere.models.refresh(...)` | `true`, `false`, `false` | `Promise<void>`; best-effort. |
| Web | `RunAnywhere.models.refresh(options?)` | `true`, `false`, `false` | `Promise<void>`; no-op before initialization and logs/contains adapter failures. |
| Electron | `RunAnywhere.models.refresh(options?)` | `true`, `false`, `false` | `Promise<void>`; logs/contains refresh failures. |
| Python | `runanywhere.models.refresh(options?)` / `arefresh(options?)` | `true`, `false`, `false` | `None`; no-op before initialization and logs/contains operational failures. A native extension missing the refresh ABI raises `NOT_IMPLEMENTED`. Protobuf-backed refresh requires the optional `runanywhere[rag]` extra. |

All SDKs call `rac_model_registry_refresh_proto` with serialized
`ModelRegistryRefreshRequest` bytes. Some bindings use generated protobuf codecs; React Native
hand-encodes the wire bytes because its native bridge does not link the protobuf runtime. None
should return the refreshed model rows as the result of this operation. The current commons
refresh implementation reports `prune_orphans` as unsupported and leaves missing-file rows
unchanged; adapters log the returned warning where available. Python's local catalog remains
process-local; refresh reconciles the shared native registry and does not rebuild that catalog.
