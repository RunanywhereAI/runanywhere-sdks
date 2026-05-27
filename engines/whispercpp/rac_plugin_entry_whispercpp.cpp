/**
 * @file rac_plugin_entry_whispercpp.cpp
 * @brief Unified-ABI entry point for whisper.cpp STT backend.
 *
 * GAP 02 Phase 9 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * CPP-04: declarative manifest publishes package ownership, availability and
 * the served primitive set alongside the routing metadata.
 */

#include "rac/features/stt/rac_stt_service.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

extern "C" {

extern const rac_stt_service_ops_t g_whispercpp_stt_ops;

/**
 * whispercpp has no runtime gate beyond build-time presence — if the engine
 * binary is loaded the whisper.cpp library was linked in, so the primitives
 * are always dispatchable. Return RAC_SUCCESS to signal "available".
 */
static rac_result_t whispercpp_capability_check(void) {
    return RAC_SUCCESS;
}

static const rac_runtime_id_t k_whispercpp_runtimes[] = {
    RAC_RUNTIME_CPU,
#if defined(__APPLE__)
    RAC_RUNTIME_METAL,
#endif
};

static const uint32_t k_whispercpp_formats[] = {
    RAC_MODEL_FORMAT_ID_GGUF,
    RAC_MODEL_FORMAT_ID_GGML,
};

static const rac_primitive_t k_whispercpp_primitives[] = {
    RAC_PRIMITIVE_TRANSCRIBE,
};

static const rac_engine_manifest_t k_whispercpp_manifest = {
    .name = "whispercpp",
    .display_name = "whisper.cpp",
    .version = nullptr,
    .package_owner = "runanywhere",
    .package_name = "runanywhere_whispercpp",
    .availability = RAC_ENGINE_AVAILABILITY_PUBLIC,
    .priority = 80,
    .capability_flags = 0,
    .primitives = k_whispercpp_primitives,
    .primitives_count = sizeof(k_whispercpp_primitives) / sizeof(k_whispercpp_primitives[0]),
    .runtimes = k_whispercpp_runtimes,
    .runtimes_count = sizeof(k_whispercpp_runtimes) / sizeof(k_whispercpp_runtimes[0]),
    .formats = k_whispercpp_formats,
    .formats_count = sizeof(k_whispercpp_formats) / sizeof(k_whispercpp_formats[0]),
    .reserved_0 = 0,
    .reserved_1 = 0,
};

static const rac_engine_vtable_t g_whispercpp_engine_vtable = {
    /* metadata */ RAC_ENGINE_METADATA_FROM_MANIFEST(k_whispercpp_manifest),
    /* capability_check */ whispercpp_capability_check,
    /* on_unload        */ nullptr,

    /* llm_ops          */ nullptr,
    /* stt_ops          */ &g_whispercpp_stt_ops,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr,
    /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ nullptr,

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

RAC_PLUGIN_ENTRY_DEF(whispercpp) {
    return rac_engine_entry_with_manifest(&k_whispercpp_manifest, &g_whispercpp_engine_vtable);
}

}  // extern "C"
