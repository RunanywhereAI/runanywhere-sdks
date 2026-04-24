#ifndef RUNANYWHERE_SHERPA_BACKEND_H
#define RUNANYWHERE_SHERPA_BACKEND_H

/**
 * @file sherpa_backend.h
 * @brief Shell header for the Sherpa-ONNX engine plugin.
 *
 * GAP 06 T5.1 — see v2_gap_specs/GAP_06_ENGINES_TOPLEVEL_REORG.md.
 *
 * The physical CMake split from engines/onnx/ landed as part of T5.1.
 * Phase 2 of the split will migrate the `ONNXSTT`, `ONNXTTS`, `ONNXVAD`
 * classes from engines/onnx/onnx_backend.{cpp,h} into this directory
 * as `SherpaSTT`, `SherpaTTS`, `SherpaVAD` and wire them into
 * `g_sherpa_stt_ops` / `g_sherpa_tts_ops` / `g_sherpa_vad_ops` on the
 * plugin vtable declared in `rac_plugin_entry_sherpa.cpp`.
 *
 * Until that migration lands the sherpa plugin registers with NULL
 * primitive slots — the real STT/TTS/VAD service continues to flow
 * through the `"onnx"` engine, which links against the same
 * `sherpa_onnx` IMPORTED target this directory declares.
 */

namespace runanywhere {
namespace sherpa {

/**
 * @brief Compile-time probe for the Sherpa-ONNX prebuilt availability
 *        (mirrors the SHERPA_ONNX_AVAILABLE CMake define).
 */
constexpr bool kSherpaOnnxAvailable =
#if SHERPA_ONNX_AVAILABLE
    true;
#else
    false;
#endif

}  // namespace sherpa
}  // namespace runanywhere

#endif  // RUNANYWHERE_SHERPA_BACKEND_H
