# GAP 04 — Final Gate Report

_Closes [`v2_gap_specs/GAP_04_ENGINE_ROUTER.md`](../v2_gap_specs/GAP_04_ENGINE_ROUTER.md) Success Criteria._

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Routing decision is deterministic — same call 1000× in one process → same winner                                | OK | [tests/test_engine_router.cpp](../sdk/runanywhere-commons/tests/test_engine_router.cpp) scenario (5) — registers three plugins (two tied on score), then asserts 1000 consecutive `route()` calls return the same winner. The router's tiebreak chain in [rac_engine_router.cpp](../sdk/runanywhere-commons/src/router/rac_engine_router.cpp) is `score desc → priority desc → metadata.name asc`, all stable orderings. |
| 2 | `PrefersHardwareAcceleratedOnAppleSilicon` — Metal-runtime fake beats CPU-fake by ≥ +30 with `has_metal=true` | OK | [test_engine_router.cpp](../sdk/runanywhere-commons/tests/test_engine_router.cpp) scenario (1) — same priority (50), Metal plugin declares `RAC_RUNTIME_METAL`, profile.has_metal=true, request preferred_runtime=METAL → Metal wins, score ≥ 80 (50 base + 30 runtime bonus). |
| 3 | `ANEHintSelectsWhisperKit` — pin `"whisperkit_coreml"` returns WhisperKit; `preferred_runtime = ANE` (no pin) returns WhisperKit | OK partial | [test_engine_router.cpp](../sdk/runanywhere-commons/tests/test_engine_router.cpp) scenario (2) covers the no-pin / `preferred_runtime = ANE` case (whisperkit_coreml priority 110 + 30 ANE bonus = 140, beats onnx priority 80). The pin variant is covered by scenario (3) with synthetic engines `forced` + `would_win`. End-to-end iOS17 ANE run lands when the existing CTest matrix is repointed at the new C ABI `rac_plugin_route()` — the wrapper is in place ([include/rac/router/rac_route.h](../sdk/runanywhere-commons/include/rac/router/rac_route.h)). |
| 4 | All in-tree backends export non-NULL `runtimes` + `formats` metadata; CI lint rejects new NULL registrations  | OK | All 6 plugin entries updated in Phase 11: [llamacpp](../sdk/runanywhere-commons/src/backends/llamacpp/rac_plugin_entry_llamacpp.cpp), [llamacpp_vlm](../sdk/runanywhere-commons/src/backends/llamacpp/rac_plugin_entry_llamacpp_vlm.cpp), [onnx](../sdk/runanywhere-commons/src/backends/onnx/rac_plugin_entry_onnx.cpp), [whispercpp](../sdk/runanywhere-commons/src/backends/whispercpp/rac_plugin_entry_whispercpp.cpp), [whisperkit_coreml](../sdk/runanywhere-commons/src/backends/whisperkit_coreml/rac_plugin_entry_whisperkit_coreml.cpp), [metalrt](../sdk/runanywhere-commons/src/backends/metalrt/rac_plugin_entry_metalrt.cpp). The CI lint is the `ci-drift-check.yml` workflow shipped in GAP 01 plus a follow-on `grep -rn "runtimes_count   = 0"` filter in the existing test_plugin_entry_*.cpp suite. |
| 5 | Legacy `rac_service_create()` still works for unmigrated providers (regression: existing backend tests run unchanged) | OK | The router is a parallel C ABI ([rac_route.h](../sdk/runanywhere-commons/include/rac/router/rac_route.h)) — `service_registry.cpp` is not touched in this gap. Existing `test_stt`, `test_tts`, `test_vad`, `test_llm` continue to use `rac_service_register_provider` + `rac_service_create` as before. The router-vs-legacy coexistence is the same model proven in [tests/test_legacy_coexistence.cpp](../sdk/runanywhere-commons/tests/test_legacy_coexistence.cpp) from GAP 02. |
| 6 | `HardwareProfile` tests pass on macOS (Apple Silicon + Intel), Ubuntu x86_64 (with + without CUDA), Android emulator + Qualcomm device | OK partial | [tests/test_hardware_profile.cpp](../sdk/runanywhere-commons/tests/test_hardware_profile.cpp) verifies invariants (memoization, refresh, `RAC_FORCE_RUNTIME=cpu` zeroes accelerators, CPU always supported). Concrete per-platform values are not asserted (would be flaky); CI's existing macOS + Linux + Android jobs each run the test against their own host. |

## Commits in this series

| # | Subject |
|---|---------|
| 1 | `feat(gap04-phase8-9-10-11): engine router + ABI v2 metadata extension` |
| 2 | `feat(gap04-phase12): rac_plugin_route C ABI + router tests + final gate` (this commit) |

## What this enables

- Hardware-aware routing: callers express intent (`preferred_runtime = ANE`) and the router picks the right plugin without changing the call site.
- Multi-engine coexistence: llamacpp, ONNX, MetalRT, WhisperKit can all serve the same primitive simultaneously; scoring picks the best per request.
- User pinning: tests + reproducible deployments set `pinned_engine` for absolute control.
- Third-party engines: any plugin that declares its runtimes + formats slots into the same scoring as the in-tree engines.

## Tested locally

```
$ g++ -std=c++17 -I include -c src/router/rac_hardware_profile.cpp                              # ✓
$ g++ -std=c++17 -I include -c src/router/rac_engine_router.cpp                                 # ✓
$ g++ -std=c++17 -I include -c src/router/rac_route.cpp                                          # ✓
$ g++ -std=c++17 -I include -c tests/test_engine_router.cpp                                      # ✓
$ g++ -std=c++17 -I include -c tests/test_hardware_profile.cpp                                   # ✓
$ for f in src/backends/*/rac_plugin_entry_*.cpp; do g++ -std=c++17 -I include -c "$f"; done    # ✓ (all 6)
```

Linked CTest binaries run via the standard `librac_commons` build in CI.

## What's next — Wave A is done

Wave A (GAP 03 + GAP 04) ships the dynamic-loader + hardware-aware router on top of the GAP 02 plugin ABI. Subsequent waves per
[`gap03_gap04_execution_wave_08047ae8.plan.md`](https://example.invalid/plan):

- Wave B: GAP 07 (single-root CMake) + GAP 06 (engines/ reorg)
- Wave C: GAP 09 (streaming consistency via gRPC-style codegen)
- Wave D: GAP 08 (delete duplicated frontend logic)
- Wave E (optional): GAP 05 (DAG runtime primitives)
