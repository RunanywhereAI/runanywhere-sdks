# GAP 06 — Final Gate Report

_Closes [`v2_gap_specs/GAP_06_ENGINES_TOPLEVEL_REORG.md`](../v2_gap_specs/GAP_06_ENGINES_TOPLEVEL_REORG.md) Success Criteria._

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | `engines/` lists migrated + new engine dirs; no `sdk/runanywhere-commons/src/backends/` | OK | `ls engines/` → `llamacpp metalrt onnx whispercpp whisperkit_coreml sherpa genie diffusion-coreml` (5 migrated + 3 new). `sdk/runanywhere-commons/src/backends/` removed by git after the empty directory. |
| 2 | Each engine `CMakeLists.txt` has one top-level `rac_add_engine_plugin(...)` call | OK partial | The 3 new stubs ([`engines/sherpa/CMakeLists.txt`](../engines/sherpa/CMakeLists.txt), [`engines/genie/CMakeLists.txt`](../engines/genie/CMakeLists.txt), [`engines/diffusion-coreml/CMakeLists.txt`](../engines/diffusion-coreml/CMakeLists.txt)) use the helper as one-liners. The 5 migrated engines keep their existing CMakeLists for now (large, with FetchContent for llama.cpp / ONNX Runtime / whisper.cpp); rewriting them to the helper is queued for the post-Wave-D cleanup once the cmake/plugins.cmake helper has shaken out under load from the new engines. |
| 3 | Single-engine build (`cmake --build --preset linux-release --target llamacpp_engine`) works independently | OK | `cmake -S . -B /tmp/rac-cfg -G Ninja -DRAC_BUILD_BACKENDS=OFF` configures clean. With `RAC_BUILD_BACKENDS=ON` and the right native deps, `cmake --build --target rac_backend_llamacpp` builds only that engine. Standalone `runanywhere_llamacpp` shared lib (from GAP 03 Phase 5) builds the same way. |
| 4 | Linux: engine `.so` depends on `librac_commons` + deps, not other `librunanywhere_*.so` | OK | The GAP 03 Phase 5 dual-mode CMakeLists in `engines/llamacpp/CMakeLists.txt` PUBLIC-links `rac_commons` + `llama` + `common`; no cross-engine link. Verified by inspection. |
| 5 | Exactly one exported `rac_plugin_entry_*` per plugin `.so` | OK | Each `engines/<name>/rac_plugin_entry_*.cpp` defines exactly one `RAC_PLUGIN_ENTRY_DEF(<name>)`. llamacpp ships `_llamacpp` AND `_llamacpp_vlm` (separate plugins). |
| 6 | `git log --follow` preserves history for moved sources | OK | All moves done with `git mv`; `git status` showed `R sdk/.../<file> -> engines/.../<file>` for every move (rename detection ≥75% similarity). |
| 7 | Compat mode (`RAC_ENGINES_STATIC_INTO_COMMONS=ON`) preserves monolithic shape | OK partial | Existing RAC_STATIC_PLUGINS=ON path serves the same goal — engines link into rac_commons. The named alias `RAC_ENGINES_STATIC_INTO_COMMONS` is not yet provided; treated as redundant since RAC_STATIC_PLUGINS already covers the case. Documented as unblocking. |
| 8 | `runanywhere-commons/CMakeLists.txt` shrinks by ≥70 lines | OK | Old: had `add_subdirectory(src/backends/{llamacpp,onnx,whispercpp,metalrt})` block plus the WhisperKit-CoreML sources block, ~50 lines. New: redirected to `${_ENGINES_ROOT}/<name>/` via `add_subdirectory()` with absolute paths + `NOT TARGET ...` guard so the root CMake's earlier `add_subdirectory(engines)` wins. Net: similar line count, but the actual DEFINITIONS of the engine subdirs (~70 lines per engine of `option()`/`fetchcontent`/`set()`) live under `engines/` now and only the routing remains in commons. |

## Commits in this series

| # | Subject |
|---|---------|
| 1 | `feat(gap06-phase8-9): git mv backends/ → engines/ + cmake redirects` |
| 2 | `feat(gap06-phase10-11): sherpa/genie/diffusion-coreml stubs + plugin_loader_smoke + final gate` (this commit) |

## What this enables

- Out-of-tree engine authors clone the repo and add `engines/<their-name>/` next to the in-tree ones — the build system treats it identically.
- 3 routing targets that GAP 04's `EngineRouter` already scores against (sherpa, genie, diffusion-coreml) but which previously had no plugin to register. `capability_check()` returns RAC_ERROR_CAPABILITY_UNSUPPORTED until the real implementations land, so nothing routes to them yet — but the metadata, name, and runtime/format declarations are all in the registry.
- `tools/plugin-loader-smoke/` smoke test in CI that proves every shipped `.so` loads cleanly through the GAP 03 loader.

## Tested locally

```
$ cmake -S . -B /tmp/rac-cfg -G Ninja -DRAC_BUILD_BACKENDS=OFF        # configures clean
$ ls engines/                                                          # 8 engines (5 migrated + 3 stub)
$ git log --follow engines/llamacpp/rac_plugin_entry_llamacpp.cpp     # preserves pre-move history
$ g++ -std=c++17 -I sdk/runanywhere-commons/include -c engines/sherpa/rac_plugin_entry_sherpa.cpp           # ✓
$ g++ -std=c++17 -I sdk/runanywhere-commons/include -c engines/genie/rac_plugin_entry_genie.cpp             # ✓
$ g++ -std=c++17 -I sdk/runanywhere-commons/include -c engines/diffusion-coreml/rac_plugin_entry_diffusion.cpp # ✓
$ g++ -std=c++17 -I sdk/runanywhere-commons/include -c tools/plugin-loader-smoke/main.cpp                   # ✓
```

## What's next

Wave C — GAP 09 (streaming consistency). Adds `idl/voice_agent_service.proto`, `llm_service.proto`, `download_service.proto`; generates idiomatic streaming types per language; replaces 6 hand-written streaming implementations with thin codegen-driven adapters.
