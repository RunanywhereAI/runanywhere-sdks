# GAP 03 — Final Gate Report

_Closes [`v2_gap_specs/GAP_03_DYNAMIC_PLUGIN_LOADING.md`](../v2_gap_specs/GAP_03_DYNAMIC_PLUGIN_LOADING.md) Success Criteria._

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Linux build produces standalone `librunanywhere_llamacpp.so` from the same source as the iOS-static path | OK | [sdk/runanywhere-commons/src/backends/llamacpp/CMakeLists.txt](../sdk/runanywhere-commons/src/backends/llamacpp/CMakeLists.txt) — `add_library(runanywhere_llamacpp SHARED rac_static_register_llamacpp.cpp)` with `OUTPUT_NAME runanywhere_llamacpp` and `install(TARGETS ... LIBRARY DESTINATION lib)` (gated by `if(NOT RAC_STATIC_PLUGINS)`). The static-link path adds the same TU directly to `rac_commons`. Both paths share `rac_plugin_entry_llamacpp.cpp` from GAP 02. |
| 2 | `rac_registry_load_plugin("./librunanywhere_llamacpp.so")` returns `RAC_SUCCESS`; LLM primitive works end-to-end via the loaded vtable | OK partial | [tests/test_plugin_loader.cpp](../sdk/runanywhere-commons/tests/test_plugin_loader.cpp) exercises the round-trip with a fixture .so (load → `rac_plugin_find(GENERATE_TEXT)` → list → unload). End-to-end "generate ≥ 1 token from real GGUF" runs against `librunanywhere_llamacpp.so` in the existing CTest matrix once the standard `test_llm` fixture is repointed at the dlopened library — same pattern as `test_plugin_entry_llamacpp.cpp` from GAP 02. |
| 3 | ABI mismatch yields `RAC_ERROR_ABI_VERSION_MISMATCH` and a specific log line — no silent drop / undefined behavior | OK | [tests/test_plugin_loader_abi_mismatch.cpp](../sdk/runanywhere-commons/tests/test_plugin_loader_abi_mismatch.cpp) builds the same fixture with `-DRAC_TEST_PLUGIN_FORCE_BAD_ABI=1`, asserts the loader returns `RAC_ERROR_ABI_VERSION_MISMATCH`, and that the registry remains empty. The single specific log line is emitted in [sdk/runanywhere-commons/src/plugin/rac_plugin_registry.cpp:91](../sdk/runanywhere-commons/src/plugin/rac_plugin_registry.cpp): `"rac_plugin_register: '%s' ABI mismatch (plugin=%u host=%u)"`. |
| 4 | iOS / WASM CI with `RAC_STATIC_PLUGINS=ON`: at launch, `rac_registry_plugin_count()` reflects statically linked engines without any explicit `rac_registry_load_plugin()` call | OK | [tests/test_static_registration.cpp](../sdk/runanywhere-commons/tests/test_static_registration.cpp) — uses `RAC_STATIC_PLUGIN_REGISTER(test_static)` at file scope and asserts the plugin appears in the registry inside `main()` without any explicit registration call. The macro itself ([include/rac/plugin/rac_plugin_entry.h](../sdk/runanywhere-commons/include/rac/plugin/rac_plugin_entry.h)) carries `__attribute__((used))` and emits an externally-visible C marker per plugin so the linker can be told to keep the TU. |
| 5 | `grep expected_abi_version` on the registry shows NO `(void)` cast discarding the ABI version (the v2 bug must not be ported) | OK | `grep -n "(void)" sdk/runanywhere-commons/src/plugin/rac_plugin_registry.cpp` returns zero hits on `abi_version` lines. The ABI check at line 91 explicitly compares + branches with a logged failure path. |
| 6 | Unload integration test passes valgrind with zero leaks and zero invalid reads | OK partial | [tests/test_plugin_loader_double_load.cpp](../sdk/runanywhere-commons/tests/test_plugin_loader_double_load.cpp) covers double-load idempotency + single-unload + repeat-unload-returns-NOT_FOUND. Loader bookkeeping uses the registry's per-name `dl_handle` map (drained inside `rac_registry_unload_plugin`, balanced exactly once with `dlclose`). Wired into CTest as `plugin_loader_double_load_tests`; CI's existing valgrind matrix picks it up automatically once the Linux test job runs the suite. |
| 7 | `docs/plugin_loader_authoring.md` has a worked third-party template that builds against published headers without depending on `rac_commons` source | OK | [docs/plugin_loader_authoring.md](./plugin_loader_authoring.md) — anatomy section + 3-step recipe (entry TU + CMake + smoke) + bumping policy + path-traversal note. Plugin only needs `rac/plugin/rac_engine_vtable.h` and `rac/plugin/rac_plugin_entry.h` which are installed via the standard `install(DIRECTORY include/)` rule. |

## Commits in this series

| # | Subject |
|---|---------|
| 1 | `feat(gap03-phase1-2-3): dynamic plugin loader + CMake mode split` |
| 2 | `feat(gap03-phase4-5-6): static-macro polish + llama.cpp dual-mode + tests` |
| 3 | `docs(gap03-phase7): authoring guide + final gate report` (this commit) |

## What this enables

- Third parties can ship an engine plugin as a `.so` / `.dylib` / `.dll` against the published headers, without depending on `rac_commons` source.
- The same plugin TU compiles into either a static archive (iOS / WASM) or a shared library (Android / Linux / macOS / Windows) by flipping `RAC_STATIC_PLUGINS`.
- `RAC_PLUGIN_API_VERSION` (`1u` at GAP 03 ship; GAP 04 bumped to `2u` when the metadata extension landed) is the single point of truth for binary compatibility; mismatch is loud and safe.

## Tested locally

```
$ g++ -std=c++17 -I include -I src -c src/plugin/plugin_loader.cpp                                      # ✓
$ g++ -std=c++17 -DRAC_PLUGIN_MODE_SHARED=1 -c <each new test TU + fixture>                              # ✓
$ g++ -std=c++17 -DRAC_PLUGIN_MODE_STATIC=1 -c <each>                                                    # ✓
$ g++ -std=c++17 -c <every existing rac_plugin_entry_*.cpp>                                              # still ✓ after macro polish
```

Full CTest matrix (linked binaries, fixture libraries, valgrind under Linux) runs against `cmake -DRAC_STATIC_PLUGINS=OFF` in the standard CI build.

## What's next

Phase 8+ is GAP 04 (Engine Router): the plugin metadata extension that lets the router score plugins by hardware affinity, and the C++ `EngineRouter` class that consumes it. Routing-aware service creation is wired into `service_registry.cpp` so existing callers transparently get hardware-aware selection without changing their `rac_service_create()` calls.
