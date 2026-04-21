/**
 * @file rac_plugin_entry_onnx.cpp
 * @brief Unified-ABI entry point for the ONNX Runtime backend.
 *
 * GAP 02 Phase 9 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * A single vtable exposes the three primitives ONNX currently serves:
 * STT (transcribe), TTS (synthesize), VAD (detect_voice). Embedding support
 * will plug into the embedding_ops slot when it lands; the slot is left
 * NULL for now and can be filled without an ABI bump.
 */

#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_service.h"

extern "C" {

/* Non-static since Phase 9. */
extern const rac_stt_service_ops_t g_onnx_stt_ops;
extern const rac_tts_service_ops_t g_onnx_tts_ops;
extern const rac_vad_service_ops_t g_onnx_vad_ops;

static const rac_engine_vtable_t g_onnx_engine_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,
        .name             = "onnx",
        .display_name     = "ONNX Runtime",
        .engine_version   = nullptr,
        .priority         = 80,          /* STT/TTS second-choice after hardware-accelerated engines */
        .capability_flags = 0,
        .reserved_0       = 0,
        .reserved_1       = 0,
    },
    /* capability_check */ nullptr,
    /* on_unload        */ nullptr,

    /* llm_ops          */ nullptr,
    /* stt_ops          */ &g_onnx_stt_ops,
    /* tts_ops          */ &g_onnx_tts_ops,
    /* vad_ops          */ &g_onnx_vad_ops,
    /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr,
    /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ nullptr,

    /* reserved_slot_0..9 */
    nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
};

RAC_PLUGIN_ENTRY_DEF(onnx) {
    return &g_onnx_engine_vtable;
}

}  // extern "C"
