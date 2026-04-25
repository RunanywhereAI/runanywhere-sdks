/**
 * @file rac_plugin_entry_diffusion_coreml.cpp
 * @brief Unified-ABI plugin entry for the CoreML diffusion engine.
 *
 * GAP 02 + GAP 06 T5.3. Apple-only Stable Diffusion plugin backed by
 * CoreML MLModel components.
 */

#include "diffusion_coreml_backend.h"

#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/features/diffusion/rac_diffusion_service.h"

#if defined(__APPLE__) && \
    defined(RAC_DIFFUSION_COREML_GENERATE_AVAILABLE) && RAC_DIFFUSION_COREML_GENERATE_AVAILABLE
#define RAC_DIFFUSION_COREML_ROUTABLE 1
#else
#define RAC_DIFFUSION_COREML_ROUTABLE 0
#endif

namespace {

// -----------------------------------------------------------------------------
// Thin forwarders that map the rac_diffusion_service_ops_t void* contract
// onto the strongly-typed rac_diffusion_coreml_* API. Keeping the forwarders
// visible as file-scope statics makes backtraces point at the primitive
// operation rather than into the .mm TU.
// -----------------------------------------------------------------------------

rac_result_t ops_initialize(void* impl, const char* model_path,
                            const rac_diffusion_config_t* config) {
    return rac_diffusion_coreml_initialize(
        static_cast<rac_diffusion_coreml_impl_t*>(impl), model_path, config);
}

rac_result_t ops_generate(void* impl, const rac_diffusion_options_t* options,
                          rac_diffusion_result_t* out_result) {
    return rac_diffusion_coreml_generate(
        static_cast<rac_diffusion_coreml_impl_t*>(impl), options, out_result);
}

rac_result_t ops_generate_with_progress(
    void* impl, const rac_diffusion_options_t* options,
    rac_diffusion_progress_callback_fn progress_cb, void* user_data,
    rac_diffusion_result_t* out_result) {
    return rac_diffusion_coreml_generate_with_progress(
        static_cast<rac_diffusion_coreml_impl_t*>(impl), options, progress_cb,
        user_data, out_result);
}

rac_result_t ops_get_info(void* impl, rac_diffusion_info_t* out_info) {
    return rac_diffusion_coreml_get_info(
        static_cast<rac_diffusion_coreml_impl_t*>(impl), out_info);
}

uint32_t ops_get_capabilities(void* impl) {
    return rac_diffusion_coreml_get_capabilities(
        static_cast<rac_diffusion_coreml_impl_t*>(impl));
}

rac_result_t ops_cancel(void* impl) {
    return rac_diffusion_coreml_cancel(
        static_cast<rac_diffusion_coreml_impl_t*>(impl));
}

rac_result_t ops_cleanup(void* impl) {
    return rac_diffusion_coreml_cleanup(
        static_cast<rac_diffusion_coreml_impl_t*>(impl));
}

void ops_destroy(void* impl) {
    rac_diffusion_coreml_destroy(
        static_cast<rac_diffusion_coreml_impl_t*>(impl));
}

rac_result_t ops_create(const char* model_id, const char* config_json,
                        void** out_impl) {
    rac_diffusion_coreml_impl_t* impl = nullptr;
    rac_result_t rc =
        rac_diffusion_coreml_create(model_id, config_json, &impl);
    if (rc != RAC_SUCCESS) {
        if (out_impl) *out_impl = nullptr;
        return rc;
    }
    if (out_impl) *out_impl = impl;
    return RAC_SUCCESS;
}

rac_result_t diffusion_coreml_capability_check(void) {
#if !defined(__APPLE__)
    return RAC_ERROR_CAPABILITY_UNSUPPORTED;
#elif RAC_DIFFUSION_COREML_ROUTABLE
    return RAC_SUCCESS;
#else
    return RAC_ERROR_BACKEND_UNAVAILABLE;
#endif
}

}  // namespace

extern "C" const rac_diffusion_service_ops_t g_diffusion_coreml_ops = {
    .initialize             = ops_initialize,
    .generate               = ops_generate,
    .generate_with_progress = ops_generate_with_progress,
    .get_info               = ops_get_info,
    .get_capabilities       = ops_get_capabilities,
    .cancel                 = ops_cancel,
    .cleanup                = ops_cleanup,
    .destroy                = ops_destroy,
    .create                 = ops_create,
};

extern "C" {

#if RAC_DIFFUSION_COREML_ROUTABLE
static const rac_runtime_id_t k_dcoreml_runtimes[] = {
    RAC_RUNTIME_COREML,
    RAC_RUNTIME_ANE,
};

static const uint32_t k_dcoreml_formats[] = {
    5,  /* MODEL_FORMAT_COREML */
};
#endif

static const rac_engine_vtable_t g_diffusion_coreml_engine_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,
        /* The plugin name is kept distinct ("diffusion-coreml") so tooling
         * can refer to it unambiguously. */
        .name             = "diffusion-coreml",
        .display_name     =
#if RAC_DIFFUSION_COREML_ROUTABLE
            "Apple CoreML Diffusion",
#else
            "Apple CoreML Diffusion [generate unavailable]",
#endif
        .engine_version   = nullptr,
        .priority         =
#if RAC_DIFFUSION_COREML_ROUTABLE
            100,
#else
            0,
#endif
        .capability_flags = 0,
        .runtimes         =
#if RAC_DIFFUSION_COREML_ROUTABLE
            k_dcoreml_runtimes,
#else
            nullptr,
#endif
        .runtimes_count   =
#if RAC_DIFFUSION_COREML_ROUTABLE
            sizeof(k_dcoreml_runtimes) / sizeof(k_dcoreml_runtimes[0]),
#else
            0,
#endif
        .formats          =
#if RAC_DIFFUSION_COREML_ROUTABLE
            k_dcoreml_formats,
#else
            nullptr,
#endif
        .formats_count    =
#if RAC_DIFFUSION_COREML_ROUTABLE
            sizeof(k_dcoreml_formats) / sizeof(k_dcoreml_formats[0]),
#else
            0,
#endif
    },
    /* capability_check */ diffusion_coreml_capability_check,
    /* on_unload        */ nullptr,

    /* llm_ops          */ nullptr,
    /* stt_ops          */ nullptr,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr,
    /* vlm_ops          */ nullptr,
    /* diffusion_ops    */
#if RAC_DIFFUSION_COREML_ROUTABLE
    &g_diffusion_coreml_ops,
#else
    nullptr,
#endif

    nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
};

RAC_PLUGIN_ENTRY_DEF(diffusion_coreml) {
    return &g_diffusion_coreml_engine_vtable;
}

}  // extern "C"
