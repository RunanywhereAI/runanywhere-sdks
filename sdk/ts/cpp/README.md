# JSI bridge for RunAnywhere v2 TypeScript adapter

Phase 3 deliverable: a JSI TurboModule `jsi_bridge.cpp` that:

1. Resolves `ra_pipeline_create_from_solution` at module load.
2. Installs a JSI host function on the JS runtime.
3. Maps V8/Hermes `ArrayBuffer` ↔ `(const uint8_t*, size_t)`.
4. Emits `VoiceEvent` back as a queued JSI `PromiseResolver`.

Until the TurboModule is wired, `VoiceSession.run()` emits
`{ kind: 'error', code: -6 }` so downstream code is forced to handle the
native-unavailable branch.
