/**
 * @file rac_plugin_entry_llamacpp_vlm.cpp
 * @brief Unified-ABI entry point for the llama.cpp Vision-Language Model
 * engine.
 *
 * GAP 02 Phase 8 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * Exposes `rac_plugin_entry_llamacpp_vlm()` filling only the VLM slot with
 * the existing `g_llamacpp_vlm_ops`. Separate from the LLM entry point so the
 * two can be independently gated in builds that only want one.
 *
 * CPP-04: declarative manifest publishes package ownership, availability and
 * the served primitive set alongside the routing metadata.
 */

#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

extern "C" {

/* Defined in rac_backend_llamacpp_vlm_register.cpp (non-static since Phase 8).
 */
extern const rac_vlm_service_ops_t g_llamacpp_vlm_ops;

static const rac_runtime_id_t k_llamacpp_vlm_runtimes[] = {
    RAC_RUNTIME_CPU,
#if defined(__APPLE__)
    RAC_RUNTIME_METAL,
#endif
};

static const uint32_t k_llamacpp_vlm_formats[] = {
    RAC_MODEL_FORMAT_ID_GGUF,
    RAC_MODEL_FORMAT_ID_BIN, /* vision projector / mmproj files */
};

static const rac_primitive_t k_llamacpp_vlm_primitives[] = {
    RAC_PRIMITIVE_VLM,
};

static const rac_engine_manifest_t k_llamacpp_vlm_manifest = {
    .name = "llamacpp_vlm",
    .display_name = "llama.cpp (VLM)",
    .version = nullptr,
    .package_owner = "runanywhere",
    .package_name = "runanywhere_llamacpp",
    .availability = RAC_ENGINE_AVAILABILITY_PUBLIC,
    .priority = 100,
    .capability_flags = 0,
    .primitives = k_llamacpp_vlm_primitives,
    .primitives_count = sizeof(k_llamacpp_vlm_primitives) /
                        sizeof(k_llamacpp_vlm_primitives[0]),
    .runtimes = k_llamacpp_vlm_runtimes,
    .runtimes_count =
        sizeof(k_llamacpp_vlm_runtimes) / sizeof(k_llamacpp_vlm_runtimes[0]),
    .formats = k_llamacpp_vlm_formats,
    .formats_count =
        sizeof(k_llamacpp_vlm_formats) / sizeof(k_llamacpp_vlm_formats[0]),
    .reserved_0 = 0,
    .reserved_1 = 0,
};

static const rac_engine_vtable_t g_llamacpp_vlm_engine_vtable = {
    /* metadata */ RAC_ENGINE_METADATA_FROM_MANIFEST(k_llamacpp_vlm_manifest),
    /* capability_check */ nullptr,
    /* on_unload        */ nullptr,

    /* llm_ops          */ nullptr,
    /* stt_ops          */ nullptr,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr,
    /* vlm_ops          */ &g_llamacpp_vlm_ops,
    /* diffusion_ops    */ nullptr,

    /* reserved_slot_0..9 */
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
};

RAC_PLUGIN_ENTRY_DEF(llamacpp_vlm) {
  return rac_engine_entry_with_manifest(&k_llamacpp_vlm_manifest,
                                        &g_llamacpp_vlm_engine_vtable);
}

} // extern "C"
