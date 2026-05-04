/**
 * @file rac_plugin_entry_genie.cpp
 * @brief Unified-ABI entry point for the Qualcomm Genie (NPU) backend.
 *
 * GAP 02 + GAP 06 T5.2. Shell plugin: the entry point remains inspectable,
 * but registration is rejected and no LLM/routing metadata is advertised
 * until real Genie LLM ops are wired. SDK discovery alone is not enough:
 * the current public implementation still returns
 * RAC_ERROR_BACKEND_UNAVAILABLE from every LLM op.
 *
 * The ABI surface intentionally stays identical in both modes so that
 * downstream SDKs (runanywhere_genie Flutter plugin, Kotlin Genie
 * module) can load the shell without platform-specific branches while the
 * router only sees Genie when the Qualcomm SDK-backed ops are real.
 */

#include "genie_backend.h"

#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/features/llm/rac_llm_service.h"

#if defined(RAC_GENIE_SDK_AVAILABLE) && RAC_GENIE_SDK_AVAILABLE && \
    defined(__ANDROID__) && \
    defined(RAC_GENIE_LLM_OPS_AVAILABLE) && RAC_GENIE_LLM_OPS_AVAILABLE
#define RAC_GENIE_ROUTABLE 1
#else
#define RAC_GENIE_ROUTABLE 0
#endif

namespace {

// -----------------------------------------------------------------------------
// Unavailable stubs
// -----------------------------------------------------------------------------
// Every llm_ops entry dispatches into these when the Genie SDK isn't
// linked. Explicitly named rather than a generic lambda so stack traces
// during debugging point at the primitive the caller tried to invoke.

rac_result_t genie_llm_create(const char* /*model_id*/,
                              const char* /*config_json*/,
                              void** out_impl) {
    if (out_impl) *out_impl = nullptr;
    return genie_backend_unavailable();
}

rac_result_t genie_llm_initialize(void* /*impl*/, const char* /*model_path*/) {
    return genie_backend_unavailable();
}

rac_result_t genie_llm_generate(void* /*impl*/, const char* /*prompt*/,
                                const rac_llm_options_t* /*opts*/,
                                rac_llm_result_t* /*out*/) {
    return genie_backend_unavailable();
}

rac_result_t genie_llm_generate_stream(void* /*impl*/, const char* /*prompt*/,
                                       const rac_llm_options_t* /*opts*/,
                                       rac_llm_stream_callback_fn /*cb*/,
                                       void* /*user_data*/) {
    return genie_backend_unavailable();
}

rac_result_t genie_llm_get_info(void* /*impl*/, rac_llm_info_t* /*out*/) {
    return genie_backend_unavailable();
}

rac_result_t genie_llm_cancel(void* /*impl*/) {
    return genie_backend_unavailable();
}

rac_result_t genie_llm_cleanup(void* /*impl*/) { return RAC_SUCCESS; }

void genie_llm_destroy(void* /*impl*/) {
    /* No-op: create always returned RAC_ERROR_BACKEND_UNAVAILABLE so impl
     * is NULL. Safe to call. */
}

// capability_check runs during rac_plugin_register. Reject the shell so the
// router never sees Genie as an eligible LLM backend in public/default builds.
// Non-Android hosts are rejected because the runtime targets Snapdragon Android.
rac_result_t genie_capability_check(void) {
#if !defined(RAC_GENIE_SDK_AVAILABLE) || !RAC_GENIE_SDK_AVAILABLE
    return RAC_ERROR_BACKEND_UNAVAILABLE;
#elif !defined(__ANDROID__)
    return RAC_ERROR_CAPABILITY_UNSUPPORTED;
#elif !defined(RAC_GENIE_LLM_OPS_AVAILABLE) || !RAC_GENIE_LLM_OPS_AVAILABLE
    return RAC_ERROR_BACKEND_UNAVAILABLE;
#else
    return RAC_SUCCESS;
#endif
}

}  // namespace

extern "C" const rac_llm_service_ops_t g_genie_llm_ops = {
    .initialize                   = genie_llm_initialize,
    .generate                     = genie_llm_generate,
    .generate_stream              = genie_llm_generate_stream,
    .generate_stream_with_timing  = nullptr,
    .get_info                     = genie_llm_get_info,
    .cancel                       = genie_llm_cancel,
    .cleanup                      = genie_llm_cleanup,
    .destroy                      = genie_llm_destroy,
    .load_lora                    = nullptr,
    .remove_lora                  = nullptr,
    .clear_lora                   = nullptr,
    .get_lora_info                = nullptr,
    .inject_system_prompt         = nullptr,
    .append_context               = nullptr,
    .generate_from_context        = nullptr,
    .clear_context                = nullptr,
    .create                       = genie_llm_create,
};

extern "C" {

#if RAC_GENIE_ROUTABLE
static const rac_runtime_id_t k_genie_runtimes[] = {
    RAC_RUNTIME_QNN,
    RAC_RUNTIME_CPU,
};

static const uint32_t k_genie_formats[] = {
    3,  /* MODEL_FORMAT_ONNX — Genie ingests QNN-compiled ONNX bundles */
};
#endif

static const rac_engine_vtable_t g_genie_engine_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,
        .name             = "genie",
        .display_name     =
#if RAC_GENIE_ROUTABLE
            "Qualcomm Genie (NPU)",
#else
            "Qualcomm Genie (NPU) [ops unavailable]",
#endif
        .engine_version   = nullptr,
        /* High priority only when the SDK-backed Android engine is eligible. */
        .priority         =
#if RAC_GENIE_ROUTABLE
            200,
#else
            0,
#endif
        .capability_flags = 0,
        .runtimes         =
#if RAC_GENIE_ROUTABLE
            k_genie_runtimes,
#else
            nullptr,
#endif
        .runtimes_count   =
#if RAC_GENIE_ROUTABLE
            sizeof(k_genie_runtimes) / sizeof(k_genie_runtimes[0]),
#else
            0,
#endif
        .formats          =
#if RAC_GENIE_ROUTABLE
            k_genie_formats,
#else
            nullptr,
#endif
        .formats_count    =
#if RAC_GENIE_ROUTABLE
            sizeof(k_genie_formats) / sizeof(k_genie_formats[0]),
#else
            0,
#endif
    },
    /* capability_check */ genie_capability_check,
    /* on_unload        */ nullptr,

    /* llm_ops          */
#if RAC_GENIE_ROUTABLE
    &g_genie_llm_ops,
#else
    nullptr,
#endif
    /* stt_ops          */ nullptr,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr,
    /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ nullptr,

    nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
};

RAC_PLUGIN_ENTRY_DEF(genie) {
    return &g_genie_engine_vtable;
}

}  // extern "C"
