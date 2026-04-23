# v3 Phase B — Complete

_Date: 2026-04-19_

All 11 sub-phases (B0-B10 + B11 verification) of the v3 ABI
extension + migration are in the tree.

## Summary

| Phase | Commit | What |
|-------|--------|------|
| B0    | `c721a9c6` | ABI extension: added `create(...)` op to 7 per-primitive ops structs (LLM / STT / TTS / VAD / VLM / embeddings / diffusion) + `initialize` to VAD for symmetry + v3 version-history entry in rac_plugin_entry.h. |
| B1    | `40d032d4` | llamacpp LLM register — `llamacpp_llm_create_impl` + delete legacy factory. |
| B2    | `e1824aa2` | llamacpp VLM register — `llamacpp_vlm_create_impl` with mmproj_path JSON parsing. |
| B3    | `67b7539e` | onnx register — STT+TTS+VAD (3 adapters), VAD `initialize` added. |
| B4    | `f75c2c85` | whispercpp STT register. |
| B5    | `c5ceb7b8` | whisperkit_coreml STT register (delegates to Swift callback). |
| B6    | `ce70e208` | metalrt register — LLM+STT+TTS+VLM (4 adapters), stub-build gating preserved. |
| B7    | `890d759e` | commons-side registers — onnx_embeddings wired into onnx plugin_entry (embedding_ops slot); new `rac_plugin_entry_platform.cpp` for Apple Foundation Models + System TTS + CoreML Diffusion; fixed `rac_embedding_service_ops` → `rac_embeddings_service_ops` naming drift in engine_vtable.h. |
| B8    | `f46c4485` | Consumer reroute — rac_{llm,stt,tts,vlm,embeddings,diffusion}_create + vad_component.load_model now route through rac_plugin_route + vt->ops->create. |
| B9    | `e33c6fa1` | JNI list-providers migration — commons JNI (2 sites) + onnx/whispercpp JNI (4 sites) swap `rac_service_list_providers` → `rac_plugin_list`. |
| B10   | `0b8e82e0` | Swift CppBridge+Services — migrated `listProviders` to `rac_plugin_list`; deleted `registerPlatformService`/`unregisterPlatformService` (obsolete — replaced by C++ plugin_entry_platform.cpp); added 5 CRACommons bridging headers. |

Total: **~11 commits**, net **-700 LOC** of legacy registry code.

## Verification

```
$ cmake --preset macos-release
-- Configuring done

$ cmake --build build/macos-release --target rac_commons \
                                             rac_backend_onnx \
                                             rac_backend_whisperkit_coreml \
                                             runanywhere_llamacpp
[201/201] Linking CXX shared library librunanywhere_llamacpp.dylib

$ cmake --preset macos-release -DRAC_BUILD_TESTS=ON
$ cmake --build build/macos-release --target test_proto_event_dispatch
$ ./build/macos-release/sdk/runanywhere-commons/tests/test_proto_event_dispatch
... [ OK  ] test_wakeword_arm
... [ OK  ] test_unregister_stops_dispatch
... [ OK  ] test_seq_monotonic
0 test(s) failed          ← 11/11

$ rg -c 'rac_service_register_provider|rac_service_create|rac_service_list_providers|rac_service_unregister_provider' \
        sdk/runanywhere-commons/src/features \
        sdk/runanywhere-commons/src/jni \
        engines/ \
        sdk/runanywhere-swift/Sources
# 6 hits across first-party files, ALL in comment blocks (explanatory
# text describing what was deleted). Zero actual function calls remain.
```

## What's left

The legacy shell is still compiled:

| Reference | Disposition |
|-----------|-------------|
| `sdk/runanywhere-commons/src/infrastructure/registry/service_registry.cpp` (311 LOC) | deleted in C1 |
| `sdk/runanywhere-commons/include/rac/core/rac_core.h` (legacy block L188-340) | deleted in C1 |
| `sdk/runanywhere-swift/Sources/RunAnywhere/CRACommons/include/rac_core.h` (mirror, 6 hits) | deleted in C1 |
| 4 exports in `RACommons.exports` + 4 in `wasm/CMakeLists.txt` | deleted in C1 |
| `sdk/runanywhere-flutter/packages/runanywhere/lib/native/ffi_types.dart` typedef block | deleted in C1 |

Once C1 lands, the tree compiles without any reference to `rac_service_*` — at
which point C2 (delete deprecated SDK-surface shims: VoiceSessionEvent etc.)
and C3 (`RAC_PLUGIN_API_VERSION 2u → 3u`, package-manifest 3.0.0) close out the
v3 cut-over.
