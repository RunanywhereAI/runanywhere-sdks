# Engines (Backend Plugins) — Current Inconsistencies

Updated: 2026-05-06
Branch: feat/v2-architecture @ bb63158d6

## Scope

Active engines only: **`engines/llamacpp/`**, **`engines/sherpa/`**, **`engines/onnx/`**. All other backends are deferred — see bottom section.

## Deferred backends (stubbed or excluded — do not file bugs here)

- `engines/genie/` — Qualcomm Snapdragon NPU LLM. Deferred; not needed for ship.
- `engines/metalrt/` — Custom Metal GPU kernels (Apple). Deferred; not needed for ship.
- `engines/whispercpp/` — whisper.cpp STT. Deferred; sherpa covers STT in active set.
- `engines/whisperkit_coreml/` — Apple Neural Engine STT. Deferred; sherpa covers STT.
- `engines/diffusion-coreml/` — CoreML image diffusion. Deferred; not in scope for current product cut.

## Cross-SDK alignment expectations (active backends)

### ENG-CROSS-MANIFEST-01: onnx `package_name` manifest value is the outlier
`engines/onnx/rac_plugin_entry_onnx.cpp:51` declares `.package_name = "rac_backend_onnx"` (the CMake target name). llamacpp and sherpa use the `runanywhere_<name>` convention: `engines/llamacpp/rac_plugin_entry_llamacpp.cpp:65` uses `runanywhere_llamacpp`; `engines/sherpa/rac_plugin_entry_sherpa.cpp:69` uses `runanywhere_sherpa`. Standardize onnx to `runanywhere_onnx`.

### ENG-CROSS-PRIORITY-01: onnx priority missing from CLAUDE.md
`engines/onnx/rac_plugin_entry_onnx.cpp:53` declares `.priority = 50`, but `CLAUDE.md:439` only lists `metalrt=120 (highest, Apple-only), llamacpp=100, sherpa=90`. Add an onnx=50 entry so the documented router-priority ladder matches what the registry actually scores.

### ENG-BACKEND-EXCLUSION: deferred backends must be excluded or stubbed by default
Goal: product-ship build must compile cleanly with only llamacpp + sherpa + onnx while genie/metalrt/whispercpp/whisperkit_coreml/diffusion-coreml remain unimplemented. Current defaults in `engines/<name>/CMakeLists.txt`: `RAC_BACKEND_GENIE=OFF`, `RAC_BACKEND_METALRT=OFF`, `RAC_BACKEND_WHISPERCPP=OFF`, `RAC_BACKEND_DIFFUSION_COREML` gated, but **`RAC_BACKEND_WHISPERKIT_COREML=ON` by default** (`engines/whisperkit_coreml/CMakeLists.txt:15`) — outlier. Next action: flip whisperkit_coreml default to OFF, or wire a top-level `RAC_DEFERRED_BACKENDS=OFF` umbrella option in the root `CMakeLists.txt` that forces all five deferred flags OFF unless explicitly overridden; audit each `engines/<name>/CMakeLists.txt` for a consistent self-gating `return()` so a stub-only build succeeds.
