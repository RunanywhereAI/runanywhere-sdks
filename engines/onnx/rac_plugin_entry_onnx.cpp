/**
 * @file rac_plugin_entry_onnx.cpp
 * @brief Unified-ABI entry point for the ONNX Runtime backend.
 *
 * GAP 02 Phase 9 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * A single vtable exposes ONNX-owned primitives. Sherpa-backed speech
 * primitives live in engines/sherpa; ONNX retains embeddings and generic
 * ONNX Runtime model services.
 */

#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/features/embeddings/rac_embeddings_service.h"

extern "C" {

/* v3 Phase B7: embeddings ops live in sdk/runanywhere-commons/src/features/rag/
 * rac_onnx_embeddings_register.cpp but are plugged into this engine's
 * vtable since onnx naturally owns the embedding primitive. */
extern const rac_embeddings_service_ops_t g_onnx_embeddings_ops;

static const rac_runtime_id_t k_onnx_runtimes[] = {
    RAC_RUNTIME_ONNXRT,
};

static const uint32_t k_onnx_formats[] = {
    3,  /* MODEL_FORMAT_ONNX */
    4,  /* MODEL_FORMAT_ORT  */
};

static const rac_engine_vtable_t g_onnx_engine_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,
        .name             = "onnx",
        .display_name     = "ONNX Runtime",
        .engine_version   = nullptr,
        .priority         = 80,
        .capability_flags = 0,
        .runtimes         = k_onnx_runtimes,
        .runtimes_count   = sizeof(k_onnx_runtimes) / sizeof(k_onnx_runtimes[0]),
        .formats          = k_onnx_formats,
        .formats_count    = sizeof(k_onnx_formats) / sizeof(k_onnx_formats[0]),
    },
    /* capability_check */ nullptr,
    /* on_unload        */ nullptr,

    /* llm_ops          */ nullptr,
    /* stt_ops          */ nullptr,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ &g_onnx_embeddings_ops,
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
