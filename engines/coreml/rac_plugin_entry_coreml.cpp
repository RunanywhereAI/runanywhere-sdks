/**
 * @file rac_plugin_entry_coreml.cpp
 * @brief Unified-ABI plugin entry for the `coreml` engine.
 *
 * Apple-only engine that runs ON Apple CoreML. Its NAME is the FRAMEWORK it
 * targets (`coreml`), not the modality — exactly like the `cloud` engine is
 * named by its transport, not by STT. It serves the DIFFUSION modality today
 * (RAC_PRIMITIVE_DIFFUSION) via the diffusion-modality op-table
 * (`g_coreml_diffusion_ops`, a Stable-Diffusion pipeline backed by CoreML
 * MLModel components); future CoreML modalities (LLM / VLM / embeddings) attach
 * by filling more vtable op-tables (see the engine vtable below).
 *
 * Declarative manifest publishes package ownership, Apple-only
 * (private) availability and the served primitive set alongside the routing
 * metadata. The manifest mirrors the conditional ops slot so registry
 * validation accepts both routable and stub builds.
 */

#include "rac_diffusion_coreml.h"

#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

#if defined(__APPLE__) && defined(RAC_COREML_GENERATE_AVAILABLE) && \
    RAC_COREML_GENERATE_AVAILABLE
#define RAC_COREML_ROUTABLE 1
#else
#define RAC_COREML_ROUTABLE 0
#endif

namespace {

// -----------------------------------------------------------------------------
// Thin forwarders that map the rac_diffusion_service_ops_t void* contract
// onto the strongly-typed rac_diffusion_coreml_* API (the coreml engine's
// DIFFUSION-modality C ABI — the `diffusion` stays because these are the
// diffusion modality of the coreml engine, parallel to rac_stt_cloud_*).
// Keeping the forwarders visible as file-scope statics makes backtraces point
// at the primitive operation rather than into the .mm TU.
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

rac_result_t coreml_capability_check(void) {
#if !defined(__APPLE__)
    return RAC_ERROR_CAPABILITY_UNSUPPORTED;
#elif RAC_COREML_ROUTABLE
    return RAC_SUCCESS;
#else
    return RAC_ERROR_BACKEND_UNAVAILABLE;
#endif
}

}  // namespace

// The coreml engine's DIFFUSION-modality op-table (parallel to the cloud
// engine's g_cloud_stt_ops). `diffusion` is kept: this IS the diffusion
// modality of the coreml engine, wired into the vtable's diffusion_ops slot.
extern "C" const rac_diffusion_service_ops_t g_coreml_diffusion_ops = {
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

#if RAC_COREML_ROUTABLE
static const rac_runtime_id_t k_coreml_runtimes[] = {
    RAC_RUNTIME_COREML,
    RAC_RUNTIME_ANE,
};

static const uint32_t k_coreml_formats[] = {
    RAC_MODEL_FORMAT_ID_COREML,
};

static const rac_primitive_t k_coreml_primitives[] = {
    RAC_PRIMITIVE_DIFFUSION,
};
#endif

static const rac_engine_manifest_t k_coreml_manifest = {
    /* Engine identity is the FRAMEWORK (`coreml`), not the modality — mirrors
     * the `cloud` engine being named by its transport, not by STT. snake_case
     * matches the RAC_PLUGIN_ENTRY_DEF(coreml) symbol and the entry-name pattern
     * derived by plugin_loader.cpp from the library filename, so a future dlopen
     * of `librunanywhere_coreml.{dylib,so}` resolves cleanly. */
    .name = "coreml",
    .display_name =
#if RAC_COREML_ROUTABLE
        "Core ML (Apple on-device)",
#else
        "Core ML (Apple on-device) [generate unavailable]",
#endif
    .version = nullptr,
    .package_owner = "runanywhere",
    .package_name = "runanywhere_coreml",
    .availability = RAC_ENGINE_AVAILABILITY_PRIVATE, /* Apple-only. */
    .priority =
#if RAC_COREML_ROUTABLE
        100,
#else
        0,
#endif
    .capability_flags = 0,
    .primitives =
#if RAC_COREML_ROUTABLE
        k_coreml_primitives,
#else
        nullptr,
#endif
    .primitives_count =
#if RAC_COREML_ROUTABLE
        sizeof(k_coreml_primitives) / sizeof(k_coreml_primitives[0]),
#else
        0,
#endif
    .runtimes =
#if RAC_COREML_ROUTABLE
        k_coreml_runtimes,
#else
        nullptr,
#endif
    .runtimes_count =
#if RAC_COREML_ROUTABLE
        sizeof(k_coreml_runtimes) / sizeof(k_coreml_runtimes[0]),
#else
        0,
#endif
    .formats =
#if RAC_COREML_ROUTABLE
        k_coreml_formats,
#else
        nullptr,
#endif
    .formats_count =
#if RAC_COREML_ROUTABLE
        sizeof(k_coreml_formats) / sizeof(k_coreml_formats[0]),
#else
        0,
#endif
    .reserved_0 = 0,
    .reserved_1 = 0,
};

static const rac_engine_vtable_t g_coreml_engine_vtable = {
    /* metadata */ RAC_ENGINE_METADATA_FROM_MANIFEST(k_coreml_manifest),
    /* capability_check */ coreml_capability_check,
    /* on_unload        */ nullptr,

    // The coreml engine's DIFFUSION modality wires its op-table into the
    // diffusion_ops slot below. To add a CoreML LLM/VLM/embeddings modality:
    // fill `llm_ops`/`vlm_ops`/`embedding_ops` here (backed by that modality's
    // impl) and add its primitive to k_coreml_manifest.primitives.
    /* llm_ops          */ nullptr,
    /* stt_ops          */ nullptr,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* vlm_ops          */ nullptr,
/* diffusion_ops    */
#if RAC_COREML_ROUTABLE
    &g_coreml_diffusion_ops,  // DIFFUSION modality of the coreml engine
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

RAC_PLUGIN_ENTRY_DEF(coreml) {
    return rac_engine_entry_with_manifest(&k_coreml_manifest, &g_coreml_engine_vtable);
}

}  // extern "C"
