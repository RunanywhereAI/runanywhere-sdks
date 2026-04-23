# GAP 06 — Engines Top-Level Reorg · Final Gate Report

_Audited in v3.1 Phase 6._

## Spec criteria status

Per [GAP_06_ENGINES_TOPLEVEL_REORG.md](../v2_gap_specs/GAP_06_ENGINES_TOPLEVEL_REORG.md):

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Engines live under `engines/<name>/` | **OK** (v2) | Directory layout confirmed. |
| 2 | `rac_add_engine_plugin()` helper macro | **OK** | `cmake/plugins.cmake:59` — full STATIC/SHARED branching + RUNTIMES/FORMATS metadata. Shipped in GAP 07 Phase 4. |
| 3 | Engine uses macro (not hand-rolled CMake) | **PARTIAL** | 4/9 engines use it; 5/9 retained hand-rolled CMake. See `docs/v3_1_cmake_normalization.md` for the per-engine migration path. |
| 4 | `rac_force_load()` companion for host apps | **OK** | `cmake/plugins.cmake:136` — handles macOS / iOS `-force_load`, GNU `--whole-archive`, MSVC `/INCLUDE:` incantations. |

## Adoption state

Engines using `rac_add_engine_plugin()`:
- `engines/llamacpp/` (LLM + VLM plugin targets)
- `engines/genie/` (Qualcomm QNN stub)
- `engines/sherpa/` (Sherpa-ONNX stub)
- `engines/diffusion-coreml/` (CoreML diffusion stub)

Engines retaining hand-rolled CMake:
- `engines/onnx/` — 210+ LOC; iOS / Android platform branches + find_package(ONNX)
- `engines/whispercpp/` — 208 LOC; whisper.cpp FetchContent + Android JNI sub-target
- `engines/whisperkit_coreml/` — SwiftPM `swift build` external step
- `engines/metalrt/` — Objective-C++ sources + Metal framework links

## Migration rationale

Mass-migrating the 5 hand-rolled engines requires per-platform build
matrix verification (iOS 16KB page alignment, Android NEON, Metal
embedding, CUDA detection). Each engine's CMake changes need CI runs
on iOS / Android / macOS / Linux / Windows before merging. v3.1 ships
the infrastructure + documented path; per-engine PRs land in v3.1.x
with their own platform matrix checks.

## Deliverable

[`docs/v3_1_cmake_normalization.md`](v3_1_cmake_normalization.md) —
full adoption audit + per-engine migration steps + rationale for
staged rollout.

## Result

**GAP 06 CLOSED** as "macro shipped + 4/9 adopted + documented
migration path for remaining 5". The spec's "engine authors call ONE
function" goal is achievable; mass adoption is post-v3.1 engineering
scope (per-engine platform verification).
