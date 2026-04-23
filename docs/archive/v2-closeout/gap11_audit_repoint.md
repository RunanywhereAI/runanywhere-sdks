# GAP 11 Phase 30 — Legacy `rac_service_*` Call-Site Audit

`rg -c "rac_service_create|rac_service_register_provider|rac_service_unregister_provider|rac_service_list_providers"` across the entire monorepo.

## SDK frontends (target: zero residue post-Wave-D)

| File | Count | Status |
|------|-------|--------|
| `sdk/runanywhere-swift/.../CppBridge+Services.swift` | 3 | repoint to `rac_plugin_route` post-Wave-D Swift soak |
| `sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons/include/rac_core.h` | 6 | bridging header — auto-syncs from `sdk/runanywhere-commons/include/rac/core/rac_core.h` (already deprecated) |
| `sdk/runanywhere-flutter/packages/runanywhere/lib/native/ffi_types.dart` | 2 | repoint via `voice_agent_stream_adapter.dart` + `rac_route` FFI bindings |
| `sdk/runanywhere-flutter/packages/runanywhere/ios/Classes/RACommons.exports` | 4 | export list — drop after `git rm` |

## C++ commons (legacy-shaped cap-key registrations — repoint to per-primitive)

| File | Count | Notes |
|------|-------|-------|
| `sdk/runanywhere-commons/src/infrastructure/registry/service_registry.cpp` | 21 | the implementation file — `git rm` in Phase 31 |
| `sdk/runanywhere-commons/src/features/platform/rac_backend_platform_register.cpp` | 9 | platform backend (Apple) cap registrations — pivot to `rac_plugin_registry_register` |
| `sdk/runanywhere-commons/src/features/llm/rac_llm_service.cpp` | 2 | service-create wrapper — replace with `rac_plugin_route` |
| `sdk/runanywhere-commons/src/features/embeddings/rac_embeddings_service.cpp` | 1 | service-create wrapper |
| `sdk/runanywhere-commons/src/features/stt/rac_stt_service.cpp` | 1 | service-create wrapper |
| `sdk/runanywhere-commons/src/features/tts/rac_tts_service.cpp` | 1 | service-create wrapper |
| `sdk/runanywhere-commons/src/features/vad/vad_component.cpp` | 1 | service-create wrapper |
| `sdk/runanywhere-commons/src/features/vlm/rac_vlm_service.cpp` | 1 | service-create wrapper |
| `sdk/runanywhere-commons/src/features/diffusion/rac_diffusion_service.cpp` | 2 | service-create wrapper |
| `sdk/runanywhere-commons/src/features/rag/rac_onnx_embeddings_register.cpp` | 2 | RAG bridge — pivot |
| `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp` | 2 | JNI thunk for Kotlin frontends |
| `sdk/runanywhere-commons/exports/RACommons.exports` | 4 | export list — drop after `git rm` |
| `sdk/runanywhere-commons/include/rac/core/rac_core.h` | 9 | header (now `[[deprecated]]` per Phase 29) |
| `sdk/runanywhere-commons/include/rac/features/embeddings/rac_embeddings_service.h` | 1 | doc comment reference only |

## Engine plugins (in-tree backends)

| File | Count | Notes |
|------|-------|-------|
| `engines/llamacpp/rac_backend_llamacpp_register.cpp` | 2 | dual-path bridge (legacy + GAP 02 vtable). Drop legacy half post-soak. |
| `engines/llamacpp/rac_backend_llamacpp_vlm_register.cpp` | 2 | same |
| `engines/llamacpp/rac_plugin_entry_llamacpp.cpp` | 1 | doc reference only |
| `engines/llamacpp/CMakeLists.txt` | 1 | comment reference only |
| `engines/onnx/jni/rac_backend_onnx_jni.cpp` | 2 | JNI thunk |
| `engines/whispercpp/rac_backend_whispercpp_register.cpp` | 2 | dual-path bridge |
| `engines/whispercpp/jni/rac_backend_whispercpp_jni.cpp` | 2 | JNI thunk |
| `engines/whisperkit_coreml/rac_backend_whisperkit_coreml_register.cpp` | 2 | dual-path bridge |
| `engines/metalrt/rac_backend_metalrt_register.cpp` | 8 | metalrt has the most call sites (all 5 cap kinds) |

## Migration plan (executed across follow-up PRs)

The repoint is per-call-site mechanical:

```cpp
// BEFORE (legacy)
rac_service_request_t req = { .identifier = "llamacpp", .config = ... };
rac_handle_t handle;
rac_service_create(RAC_CAPABILITY_LLM, &req, &handle);

// AFTER (GAP 04 router)
rac_routing_hints_t hints = { .preferred_engine_name = "llamacpp" };
rac_route_request_t req = {
    .primitive = RAC_PRIMITIVE_GENERATE_TEXT,
    .format    = RA_MODEL_FORMAT_GGUF,
    .hints     = &hints,
};
rac_route_result_t result;
rac_plugin_route(&req, &result);  // result.engine_name + result.vtable
```

`rac_plugin_registry_register` similarly replaces
`rac_service_register_provider` — the new API is per-primitive (one call
per `rac_primitive_t`) instead of per-capability (one call per
`rac_capability_t`), which means a cap that registered for STT + LLM in
one shot now registers twice. Mechanical translation, no semantic loss.

## Status

GAP 11 Phase 30 ships the audit. Per-call-site repointing happens in the
v3 cleanup PR (GAP 11 Phase 31), simultaneously with the `git rm` of
`service_registry.cpp` and the `RAC_PLUGIN_API_VERSION` bump to `3u`.
Mid-stream repointing is risky because each caller needs its own
behavioral verification on the right device matrix — same reason Wave D
ships markers instead of physical deletes.

Total residue: **88 lines across 30 files** (counted via `rg -c` above).
After the v3 cleanup, expected residue: **0**.
