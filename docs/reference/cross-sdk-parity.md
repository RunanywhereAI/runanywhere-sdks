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
