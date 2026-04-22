/**
 * @file rac_plugin_entry_genie.cpp
 * @brief GAP 06 Phase 10 stub — Qualcomm Genie LLM engine on Hexagon NPU.
 *
 * Today: scaffold returning RAC_ERROR_CAPABILITY_UNSUPPORTED until the real
 * QNN integration lands. The router still sees the metadata so future
 * `preferred_runtime = RAC_RUNTIME_QNN` requests can be scored against it
 * when an Android Snapdragon host detects QNN availability.
 */

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

extern "C" {

static rac_result_t genie_capability_check(void) {
#if defined(__ANDROID__)
    /* TODO: dlopen("libQnnHtp.so") + verify g_genie_llm_ops once wired. */
    return RAC_ERROR_CAPABILITY_UNSUPPORTED;
#else
    return RAC_ERROR_CAPABILITY_UNSUPPORTED;
#endif
}

static const rac_runtime_id_t k_genie_runtimes[] = { RAC_RUNTIME_QNN };
static const uint32_t         k_genie_formats[]  = { 11 /* MODEL_FORMAT_QNN_CONTEXT */ };

static const rac_engine_vtable_t g_genie_engine_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,
        .name             = "genie",
        .display_name     = "Qualcomm Genie (LLM scaffold, Hexagon NPU)",
        .engine_version   = nullptr,
        .priority         = 105,  /* between LlamaCPP (100) and WhisperKit-CoreML (110) */
        .capability_flags = 0,
        .runtimes         = k_genie_runtimes,
        .runtimes_count   = 1,
        .formats          = k_genie_formats,
        .formats_count    = 1,
    },
    /* capability_check */ genie_capability_check,
    /* on_unload        */ nullptr,
    /* llm_ops          */ nullptr,
    /* stt_ops          */ nullptr, /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr, /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr, /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
};

RAC_PLUGIN_ENTRY_DEF(genie) { return &g_genie_engine_vtable; }

}  // extern "C"
