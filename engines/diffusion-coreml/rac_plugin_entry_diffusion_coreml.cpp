/**
 * @file rac_plugin_entry_diffusion_coreml.cpp
 * @brief Unified-ABI plugin entry for the CoreML diffusion engine.
 *
 * Apple-only Stable Diffusion plugin backed by
 * CoreML MLModel components.
 *
 * Declarative manifest publishes package ownership, Apple-only
 * (private) availability and the served primitive set alongside the routing
 * metadata. The manifest mirrors the conditional ops slot so registry
 * validation accepts both routable and stub builds.
 */

#include "diffusion_coreml_backend.h"

#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

#if defined(__APPLE__) && defined(RAC_DIFFUSION_COREML_GENERATE_AVAILABLE) && \
    RAC_DIFFUSION_COREML_GENERATE_AVAILABLE
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
    return rac_diffusion_coreml_initialize(static_cast<rac_diffusion_coreml_impl_t*>(impl),
                                           model_path, config);
}

rac_result_t ops_generate(void* impl, const rac_diffusion_options_t* options,
                          rac_diffusion_result_t* out_result) {
    return rac_diffusion_coreml_generate(static_cast<rac_diffusion_coreml_impl_t*>(impl), options,
                                         out_result);
}

rac_result_t ops_generate_with_progress(void* impl, const rac_diffusion_options_t* options,
                                        rac_diffusion_progress_callback_fn progress_cb,
                                        void* user_data, rac_diffusion_result_t* out_result) {
    return rac_diffusion_coreml_generate_with_progress(
        static_cast<rac_diffusion_coreml_impl_t*>(impl), options, progress_cb, user_data,
        out_result);
}

rac_result_t ops_get_info(void* impl, rac_diffusion_info_t* out_info) {
    return rac_diffusion_coreml_get_info(static_cast<rac_diffusion_coreml_impl_t*>(impl), out_info);
}

uint32_t ops_get_capabilities(void* impl) {
    return rac_diffusion_coreml_get_capabilities(static_cast<rac_diffusion_coreml_impl_t*>(impl));
}

rac_result_t ops_cancel(void* impl) {
    return rac_diffusion_coreml_cancel(static_cast<rac_diffusion_coreml_impl_t*>(impl));
}

rac_result_t ops_cleanup(void* impl) {
    return rac_diffusion_coreml_cleanup(static_cast<rac_diffusion_coreml_impl_t*>(impl));
}

void ops_destroy(void* impl) {
    rac_diffusion_coreml_destroy(static_cast<rac_diffusion_coreml_impl_t*>(impl));
}

rac_result_t ops_create(const char* model_id, const char* config_json, void** out_impl) {
    rac_diffusion_coreml_impl_t* impl = nullptr;
    rac_result_t rc = rac_diffusion_coreml_create(model_id, config_json, &impl);
    if (rc != RAC_SUCCESS) {
        if (out_impl)
            *out_impl = nullptr;
        return rc;
    }
    if (out_impl)
        *out_impl = impl;
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
    .initialize = ops_initialize,
    .generate = ops_generate,
    .generate_with_progress = ops_generate_with_progress,
    .get_info = ops_get_info,
    .get_capabilities = ops_get_capabilities,
    .cancel = ops_cancel,
    .cleanup = ops_cleanup,
    .destroy = ops_destroy,
    .create = ops_create,
};

extern "C" {

#if RAC_DIFFUSION_COREML_ROUTABLE
static const rac_runtime_id_t k_dcoreml_runtimes[] = {
    RAC_RUNTIME_COREML,
    RAC_RUNTIME_ANE,
};

static const uint32_t k_dcoreml_formats[] = {
    RAC_MODEL_FORMAT_ID_COREML,
};

static const rac_primitive_t k_dcoreml_primitives[] = {
    RAC_PRIMITIVE_DIFFUSION,
};
#endif

static const rac_engine_manifest_t k_diffusion_coreml_manifest = {
    /* snake_case to match the RAC_PLUGIN_ENTRY_DEF(diffusion_coreml) symbol
     * and the entry-name pattern derived by plugin_loader.cpp from the
     * library filename, so a future dlopen of
     * `librunanywhere_diffusion_coreml.{dylib,so}` resolves cleanly. */
    .name = "diffusion_coreml",
    .display_name =
#if RAC_DIFFUSION_COREML_ROUTABLE
        "Apple CoreML Diffusion",
#else
        "Apple CoreML Diffusion [generate unavailable]",
#endif
    .version = nullptr,
    .package_owner = "runanywhere",
    .package_name = "runanywhere_diffusion_coreml",
    .availability = RAC_ENGINE_AVAILABILITY_PRIVATE, /* Apple-only. */
    .priority =
#if RAC_DIFFUSION_COREML_ROUTABLE
        100,
#else
        0,
#endif
    .capability_flags = 0,
    .primitives =
#if RAC_DIFFUSION_COREML_ROUTABLE
        k_dcoreml_primitives,
#else
        nullptr,
#endif
    .primitives_count =
#if RAC_DIFFUSION_COREML_ROUTABLE
        sizeof(k_dcoreml_primitives) / sizeof(k_dcoreml_primitives[0]),
#else
        0,
#endif
    .runtimes =
#if RAC_DIFFUSION_COREML_ROUTABLE
        k_dcoreml_runtimes,
#else
        nullptr,
#endif
    .runtimes_count =
#if RAC_DIFFUSION_COREML_ROUTABLE
        sizeof(k_dcoreml_runtimes) / sizeof(k_dcoreml_runtimes[0]),
#else
        0,
#endif
    .formats =
#if RAC_DIFFUSION_COREML_ROUTABLE
        k_dcoreml_formats,
#else
        nullptr,
#endif
    .formats_count =
#if RAC_DIFFUSION_COREML_ROUTABLE
        sizeof(k_dcoreml_formats) / sizeof(k_dcoreml_formats[0]),
#else
        0,
#endif
    .reserved_0 = 0,
    .reserved_1 = 0,
};

static const rac_engine_vtable_t g_diffusion_coreml_engine_vtable = {
    /* metadata */ RAC_ENGINE_METADATA_FROM_MANIFEST(k_diffusion_coreml_manifest),
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

RAC_PLUGIN_ENTRY_DEF(diffusion_coreml) {
    return rac_engine_entry_with_manifest(&k_diffusion_coreml_manifest,
                                          &g_diffusion_coreml_engine_vtable);
}

}  // extern "C"
