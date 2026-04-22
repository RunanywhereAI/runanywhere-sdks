/**
 * @file rac_plugin_entry_diffusion.cpp
 * @brief GAP 06 Phase 10 stub — Apple CoreML Stable Diffusion engine plugin.
 *
 * Scaffold only. The real diffusion code lives in
 * `sdk/runanywhere-commons/src/features/diffusion/` and is linked directly
 * into rac_commons on Apple builds. This plugin exists so the router can
 * score `RAC_PRIMITIVE_DIFFUSION` requests against a named engine. Wraps
 * the existing implementation in a follow-up commit (out-of-scope for
 * Phase 10).
 */

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

extern "C" {

static rac_result_t diffusion_coreml_capability_check(void) {
#if defined(__APPLE__)
    /* TODO: wrap g_diffusion_coreml_ops once the in-tree feature is exposed
     *       via the unified ops table. Until then, decline. */
    return RAC_ERROR_CAPABILITY_UNSUPPORTED;
#else
    return RAC_ERROR_CAPABILITY_UNSUPPORTED;
#endif
}

static const rac_runtime_id_t k_diff_runtimes[] = { RAC_RUNTIME_COREML, RAC_RUNTIME_ANE };
static const uint32_t         k_diff_formats[]  = { 6 /* COREML */, 8 /* MLPACKAGE */ };

static const rac_engine_vtable_t g_diffusion_coreml_engine_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,
        .name             = "diffusion-coreml",
        .display_name     = "Apple CoreML Diffusion (scaffold)",
        .engine_version   = nullptr,
        .priority         = 100,
        .capability_flags = 0,
        .runtimes         = k_diff_runtimes,
        .runtimes_count   = 2,
        .formats          = k_diff_formats,
        .formats_count    = 2,
    },
    /* capability_check */ diffusion_coreml_capability_check,
    /* on_unload        */ nullptr,
    /* llm_ops          */ nullptr,
    /* stt_ops          */ nullptr, /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr, /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr, /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ nullptr,  /* TODO: wrap existing diffusion impl */
    nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
};

RAC_PLUGIN_ENTRY_DEF(diffusion_coreml) { return &g_diffusion_coreml_engine_vtable; }

}  // extern "C"
