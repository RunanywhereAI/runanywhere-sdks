# Phase F — Stub-Engine / Wakeword Close-out Report

Working tree: `runanywhere-sdks-main/`
Verification preset: `macos-debug`

All four "implement-or-delete" decisions from Phase F resolved to DELETE
on the basis that no in-tree consumer was wired to the scaffold. See
`docs/v2_closeout_engine_decisions.md` for the full audit.

## Per-artifact decisions and LOC delta

| Artifact                                                                                     | Decision | Reason                                                                                                                     | LOC removed |
| -------------------------------------------------------------------------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------- | ----------- |
| `engines/sherpa/`                                                                            | DELETED  | `RAC_BACKEND_SHERPA` defaults OFF with no consumer; real Sherpa-ONNX already ships inside `engines/onnx/` via `RAC_USE_SHERPA_ONNX`. | 81          |
| `engines/genie/`                                                                             | DELETED  | `RAC_BACKEND_GENIE` defaults OFF with no consumer; real QNN integration is multi-week and will be reintroduced with real ops.      | 74          |
| `engines/diffusion-coreml/`                                                                  | DELETED  | `RAC_BACKEND_DIFFUSION_COREML` defaults OFF with no consumer; real CoreML diffusion lives in `sdk/runanywhere-commons/src/features/diffusion/`. | 83          |
| `sdk/runanywhere-commons/src/features/wakeword/wakeword_service.cpp`                         | DELETED  | 672-line stub with 7 TODO placeholders and zero real callers; all real consumers (Playground pipelines + `test_wakeword.cpp`) use `rac_wakeword_onnx_*` directly. | 672         |
| `sdk/runanywhere-commons/include/rac/features/wakeword/rac_wakeword_service.h`               | DELETED  | Header for the deleted stub.                                                                                               | 318         |
| `sdk/runanywhere-commons/include/rac/features/wakeword/rac_wakeword.h`                       | DELETED  | Umbrella header whose only job was to include the deleted service header.                                                   | 58          |
| `sdk/runanywhere-commons/include/rac/features/wakeword/rac_wakeword_types.h`                 | KEPT     | Provides `rac_wakeword_event_t`, `rac_wakeword_config_t`, `RAC_ERROR_WAKEWORD_*` — used by the real ONNX backend and `rac_voice_agent.h`. | 0           |

Net code deletion: **–1,286 lines** of dead C/C++ + 3 directories.

## Files touched (non-deletion edits)

| File                                                                                   | Change                                                                                         |
| -------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `engines/CMakeLists.txt`                                                               | Removed the `foreach(_stub sherpa genie diffusion-coreml)` block.                              |
| `CMakeLists.txt` (root)                                                                | Rewrote the "3 stubs" comment into a historical note pointing at the decisions doc.            |
| `docs/engine_plugin_authoring.md`                                                      | Dropped the three stub rows from the priority-ladder table and folded "Wakeword" into the onnx row so the new ladder reflects reality. |
| `sdk/runanywhere-commons/CMakeLists.txt`                                               | Removed `src/features/wakeword/wakeword_service.cpp` source entry; left a comment documenting the removal. |
| `sdk/runanywhere-commons/include/rac/backends/rac_wakeword_onnx.h`                     | Retargeted the include from the deleted umbrella (`rac_wakeword.h`) to the kept types header (`rac_wakeword_types.h`). |
| `sdk/runanywhere-commons/include/rac/features/wakeword/rac_wakeword_types.h`           | Removed a stale docstring that referred to the deleted `rac_wakeword_set_callback` function.   |
| `docs/v2_closeout_engine_decisions.md` (new)                                           | Phase F audit + decisions table with LOC estimates.                                            |
| `docs/v2_closeout_phase_f_report.md` (this file)                                       | Execution + verification report.                                                               |

### Pre-existing test-infrastructure fixes (opportunistic)

The final-verification build surfaced three test-infrastructure bugs
that pre-existed Phase F but masked the real state of the build. They
were trivial one-liners to repair and unblock `cmake --build --preset
macos-debug` as the mission demands; diffs live next to the Phase F work
so reviewers can split them out if desired.

| File                                                                                   | Fix                                                                                                                  |
| -------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `sdk/runanywhere-commons/tests/CMakeLists.txt` (fixture include dir)                   | Replaced `${CMAKE_SOURCE_DIR}/include` with the commons include dir (the old path points to `runanywhere-sdks-main/include/` which doesn't exist when building via the top-level preset — the fixtures don't link rac_commons so they can't rely on transitive propagation). |
| `sdk/runanywhere-commons/tests/CMakeLists.txt` (benchmark gtest include order)         | Prepended the FetchContent-bundled gtest include dir to `rac_benchmark_tests` so it wins over Homebrew's `/opt/homebrew/include` (pulled in by transitive `libprotobuf`/`absl` dylibs). Without this, the bundled `libgtest.a` (`const char*` MakeAndRegisterTestInfo) link-fails against code compiled with Homebrew's newer `std::string` header. |
| `sdk/runanywhere-commons/tests/fixtures/rac_test_plugin.cpp`                           | For the `RAC_TEST_PLUGIN_FORCE_BAD_ABI` compile variant, declare the entry symbol as `rac_plugin_entry_test_plugin_bad_abi` to match what `entry_symbol_from_path()` derives from the fixture's filename `librunanywhere_test_plugin_bad_abi.dylib`. |

## Verification outputs

### 1. Configure

```
$ cmake --preset macos-debug
...
-- ============================================
-- RunAnywhere SDKs — root CMake configured
-- ============================================
-- Version          : 0.19.13
-- Build mode       : $<IF:$<BOOL:OFF>,SHARED,STATIC>
-- Plugin mode      : $<IF:$<BOOL:OFF>,STATIC (linked into commons),SHARED (dlopen-loaded)>
-- Tests            : ON
-- Server (HTTP)    : OFF
-- Platform backend : ON
-- ============================================
-- Configuring done (2.1s)
-- Generating done (0.1s)
```

### 2. `rac_commons` target (mission-critical)

```
$ cmake --build --preset macos-debug --target rac_commons
ninja: no work to do.
```

(Built earlier in the session; deltas here are zero because nothing
depends on the deleted wakeword service outside of this target.)

### 3. Full build

```
$ cmake --build --preset macos-debug
... (full build, 0 errors)
```

Exit code `0`. Full binary graph (commons, llamacpp, onnx, whispercpp,
whisperkit_coreml, metalrt, tests, fixtures) builds clean.

### 4. Remaining engines

```
$ ls engines/
CMakeLists.txt
llamacpp
metalrt
onnx
whispercpp
whisperkit_coreml
```

Five real backends remain. Down from eight (3 deleted stubs). All five
are production-integrated and used by at least one example or test.

### 5. Engine CMakeLists cleanliness

```
$ rg "sherpa|genie|diffusion-coreml" engines/CMakeLists.txt
(no matches)
```

### 6. ctest

```
$ ctest --preset macos-debug
...
96% tests passed, 2 tests failed out of 51

The following tests FAILED:
         49 - perf_aggregate (Failed)
         51 - cancel_aggregate (Failed)
```

49 / 51 pass (96%). The two failures are pre-existing test-runner CLI
wiring bugs in `tests/streaming/perf_bench/compute_percentiles.py` and
`tests/streaming/cancel_parity/compare_cancel_traces.py` — the CMake
`add_test(...)` invocations for those two aggregate stages pass the
wrong positional arguments (a directory path where a list of files is
expected; positional args where named flags are required). They were
broken before Phase F started and are unrelated to engine / wakeword
code. They meet the mission-statement exception:

> tests must pass (infrastructure failures documented, not blocking)

Documenting them here as out-of-scope for Phase F; they should be
picked up in a dedicated test-runner fix-up pass.

## MetalRT exception doc block (F-4)

Verified in place at `cmake/plugins.cmake` lines 34–52 (immediately
after `include_guard(GLOBAL)`). The comment explains why `metalrt` is
built as an OBJECT library folded into `rac_commons` rather than going
through `rac_add_engine_plugin()` (closed-source private vendor lib;
App-Store-safe static-init; OBJECT layout naturally folds). No
regression; no edit needed.

## Summary table

| Metric                                    | Before Phase F | After Phase F |
| ----------------------------------------- | -------------- | ------------- |
| In-tree engines                           | 8 (5 real + 3 stub) | 5 (all real)  |
| Engines with NULL ops slots               | 3                   | 0             |
| TODO markers in `wakeword_service.cpp`    | 7                   | 0 (file gone) |
| Plugin-registry dead-weight candidates     | 3 stub vtables declaring runtimes/formats but serving `RAC_ERROR_CAPABILITY_UNSUPPORTED` | 0 |
| Full-build status (`cmake --build`)       | failing (pre-existing fixture compile break) | passing |
| Test pass rate (`ctest`)                  | n/a (build failed) | 49 / 51 (96%) |

Phase F is closed.
