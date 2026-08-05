/**
 * @file rac_plugin_entry_neurt.cpp
 * @brief Unified-ABI plugin entry for the `neurt` engine.
 *
 * Apple-only engine, named for the RUNTIME THAT IMPLEMENTS IT (NeuRT, the Apple
 * half of the sibling `neurun` repo) rather than for a modality or for Apple's
 * framework — exactly like the `cloud` engine is named by its transport, not by
 * STT. It serves TWO modalities:
 *
 *   * RAC_PRIMITIVE_DIFFUSION  via `g_coreml_diffusion_ops` — a Stable-Diffusion
 *     pipeline over CoreML MLModel components.
 *   * RAC_PRIMITIVE_GENERATE_TEXT via `g_neurt_llm_ops` — prebuilt Core ML LLM
 *     graphs executed on the Apple Neural Engine.
 *
 * Both implementations live in neurun under `NeuRT/src/sdk/`; this file only
 * publishes them. Further modalities (VLM / embeddings) attach by filling more
 * vtable op-tables (see the engine vtable below).
 *
 * The engine was renamed from `coreml` when NeuRT became its implementation.
 * `RAC_RUNTIME_COREML`, `RAC_RUNTIME_ANE` and `RAC_MODEL_FORMAT_ID_COREML`
 * below name Apple's FRAMEWORK, not this engine, and are deliberately unchanged
 * — as is the `rac_diffusion_coreml_*` C ABI, which is the CoreML-framework
 * implementation of the diffusion modality.
 *
 * Declarative manifest publishes package ownership, Apple-only (private)
 * availability and the served primitive set alongside the routing metadata. The
 * manifest mirrors the conditional ops slots so registry validation accepts
 * both routable and stub builds.
 */

#include "neurt_bundle_policy.h"
#include "rac/core/rac_logger.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
// `rac_llm_service_ops_t` lives here; the vtable header forward-declares the slot but not the
// type, so the entry file must include it to name the NeuRT op table.
#include "rac/features/llm/rac_llm_service.h"
#include "rac/plugin/rac_plugin_entry.h"

#if defined(__APPLE__) && defined(RAC_NEURT_GENERATE_AVAILABLE) && \
    RAC_NEURT_GENERATE_AVAILABLE
#define RAC_NEURT_ROUTABLE 1
#else
#define RAC_NEURT_ROUTABLE 0
#endif

// Both modalities are implemented in the sibling `neurun` checkout, so EVERY reference to them —
// the header, the forwarders and the op table — is confined to the routable build. Without this
// the stub still names `rac_diffusion_coreml_*` and fails to LINK, which is why a shell build was
// impossible before: the vtable slots were already conditional, but the symbols behind them were
// not. Mirrors the QHexRT engine, whose shell compiles in the public repo with no private header.
#if RAC_NEURT_ROUTABLE
#include "rac_diffusion_coreml.h"
#endif

namespace {

// -----------------------------------------------------------------------------
// Thin forwarders that map the rac_diffusion_service_ops_t void* contract
// onto the strongly-typed rac_diffusion_coreml_* API (this engine's
// DIFFUSION-modality C ABI — `coreml` stays because that ABI IS the CoreML
// -framework implementation of the modality, parallel to rac_stt_cloud_*).
// Keeping the forwarders visible as file-scope statics makes backtraces point
// at the primitive operation rather than into the .mm TU.
//
// Routable builds only: these are the sole users of the neurun-provided symbols.
// -----------------------------------------------------------------------------
#if RAC_NEURT_ROUTABLE

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

#endif  // RAC_NEURT_ROUTABLE

// Compiled in BOTH modes: the registry calls this before registration, and a stub build must be
// able to say "unavailable" rather than silently registering an engine that serves nothing.
rac_result_t neurt_capability_check(void) {
#if !defined(__APPLE__)
    return RAC_ERROR_CAPABILITY_UNSUPPORTED;
#elif RAC_NEURT_ROUTABLE
    return RAC_SUCCESS;
#else
    return RAC_ERROR_BACKEND_UNAVAILABLE;
#endif
}

}  // namespace

// This engine's DIFFUSION-modality op-table (parallel to the cloud engine's
// g_cloud_stt_ops). The `coreml` in the name is the Apple FRAMEWORK the
// modality is implemented over, not the engine identity; it is wired into the
// vtable's diffusion_ops slot below.
#if RAC_NEURT_ROUTABLE
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
#endif  // RAC_NEURT_ROUTABLE

extern "C" {

#if RAC_NEURT_ROUTABLE
static const rac_runtime_id_t k_neurt_runtimes[] = {
    RAC_RUNTIME_COREML,
    RAC_RUNTIME_ANE,
};

static const uint32_t k_neurt_formats[] = {
    RAC_MODEL_FORMAT_ID_COREML,
};

static const rac_primitive_t k_neurt_primitives[] = {
    RAC_PRIMITIVE_DIFFUSION,
    // NOTE: the text-generation primitive is RAC_PRIMITIVE_GENERATE_TEXT. There is no
    // RAC_PRIMITIVE_LLM — SDK_PATCH.md's diff names one and the enum has never had it.
    RAC_PRIMITIVE_GENERATE_TEXT,
};
#endif

static const rac_engine_manifest_t k_neurt_manifest = {
    /* Engine identity is the IMPLEMENTING RUNTIME (`neurt`), not the modality
     * and not Apple's framework — mirrors the `cloud` engine being named by its
     * transport, not by STT. snake_case matches the RAC_PLUGIN_ENTRY_DEF(neurt)
     * symbol and the entry-name pattern plugin_loader.cpp derives from the
     * library filename, so `librunanywhere_neurt.{dylib,so}` resolves cleanly.
     * The three move together — filename, symbol, and this name — or a dlopen
     * host silently fails to install the vtable. */
    .name = "neurt",
    .display_name =
#if RAC_NEURT_ROUTABLE
        "NeuRT (Apple Neural Engine)",
#else
        "NeuRT (Apple Neural Engine) [generate unavailable]",
#endif
    .version = nullptr,
    .package_owner = "runanywhere",
    .package_name = "runanywhere_neurt",
    .availability = RAC_ENGINE_AVAILABILITY_PRIVATE, /* Apple-only. */
    /* Priority stays at 100, DELIBERATELY BELOW mlx's 110, and that is not an
     * oversight. Selection is plain priority order, so raising this above mlx
     * would hand the ANE every unpinned GENERATE_TEXT request — including GGUF
     * and safetensors models this engine cannot open, which would then fail at
     * initialize() instead of routing to the engine that can serve them. An ANE
     * bundle reaches this engine by being PINNED, not by winning a priority
     * war: a model whose framework is INFERENCE_FRAMEWORK_COREML resolves
     * through engine_name_for_framework() -> RAC_ENGINE_ID_NEURT ->
     * rac_plugin_find_for_engine(), which bypasses priority entirely
     * (model_lifecycle.cpp). `rcli --engine neurt` drives exactly that path. */
    .priority =
#if RAC_NEURT_ROUTABLE
        100,
#else
        0,
#endif
    .capability_flags = 0,
    .primitives =
#if RAC_NEURT_ROUTABLE
        k_neurt_primitives,
#else
        nullptr,
#endif
    .primitives_count =
#if RAC_NEURT_ROUTABLE
        sizeof(k_neurt_primitives) / sizeof(k_neurt_primitives[0]),
#else
        0,
#endif
    .runtimes =
#if RAC_NEURT_ROUTABLE
        k_neurt_runtimes,
#else
        nullptr,
#endif
    .runtimes_count =
#if RAC_NEURT_ROUTABLE
        sizeof(k_neurt_runtimes) / sizeof(k_neurt_runtimes[0]),
#else
        0,
#endif
    .formats =
#if RAC_NEURT_ROUTABLE
        k_neurt_formats,
#else
        nullptr,
#endif
    .formats_count =
#if RAC_NEURT_ROUTABLE
        sizeof(k_neurt_formats) / sizeof(k_neurt_formats[0]),
#else
        0,
#endif
    .reserved_0 = 0,
    .reserved_1 = 0,
};

// The LLM modality, implemented in NeuRT (neurun/NeuRT/src/sdk/rac_llm_ops_neurt.cpp) and linked in
// via `rac_neurt_llm_ops` -> `rac_neurt_core`. NeuRT runs prebuilt Core ML graphs on the Apple
// Neural Engine; it never compiles a model.
//
// NEURT_ROOT is NOT a hard requirement: without the neurun checkout engines/neurt builds a
// non-routable shell rather than failing configure, so the engine can be compiled on a CI host
// that cannot clone the private repo. `RAC_NEURT_ROUTABLE` is what re-establishes the guarantee
// the old FATAL_ERROR was after — in the stub arm the vtable's llm_ops slot is NULL and
// capability_check refuses registration, so an engine advertising GENERATE_TEXT can never hand
// back a null op-table.
//
// This declaration is therefore only ODR-used from the routable arm of the vtable below; an
// `extern` declaration that is never referenced needs no definition, which is what lets the shell
// link with no neurun symbols at all.
//
// The definition must have EXTERNAL linkage on the NeuRT side. A `const` object at namespace scope
// is internal by default in C++ and `extern "C" { }` does not change that, so without an explicit
// `extern` there the symbol is never emitted and this declaration fails to resolve at the first
// real link (a static archive never resolves symbols, so the engine target alone builds green).
extern "C" const rac_llm_service_ops_t g_neurt_llm_ops;

static const rac_engine_vtable_t g_neurt_engine_vtable = {
    /* metadata */ RAC_ENGINE_METADATA_FROM_MANIFEST(k_neurt_manifest),
    /* capability_check */ neurt_capability_check,
    /* on_unload        */ nullptr,

    // The two served modalities wire their op-tables into the llm_ops and
    // diffusion_ops slots below. To add an Apple VLM/embeddings modality: fill
    // `vlm_ops`/`embedding_ops` here (backed by that modality's impl) and add its
    // primitive to k_neurt_manifest.primitives.
/* llm_ops          */
#if RAC_NEURT_ROUTABLE
    &g_neurt_llm_ops,  // GENERATE_TEXT on the Apple Neural Engine, backed by NeuRT
#else
    nullptr,
#endif
    /* stt_ops          */ nullptr,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* vlm_ops          */ nullptr,
/* diffusion_ops    */
#if RAC_NEURT_ROUTABLE
    &g_coreml_diffusion_ops,  // DIFFUSION over CoreML MLModel
#else
    nullptr,
#endif
    /* diarization_ops  */ nullptr,
    /* segmentation_ops */ nullptr,

    /* reserved_slot_2..9 */
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
};

RAC_PLUGIN_ENTRY_DEF(neurt) {
    // Bundle policy FIRST, and unconditionally. It is inert metadata that teaches commons how to
    // resolve an ANE folder bundle (which top-level .json is the manifest, which format to stamp),
    // which is what makes a one-line `registerModel(url: "hf.co/org/<m>_ANE/<precision>")` work at
    // all — exactly as the QHexRT engine does for HNPU bundles.
    //
    // MEASURED before this existed: a bare folder ref failed with "cannot choose a primary file",
    // and naming the manifest explicitly registered a 160-byte SINGLE FILE with the framework
    // unset. So the Apple catalog could not register a bundle by URL in either form.
    //
    // Registering it here rather than in a `rac_backend_neurt_register()` is deliberate: this
    // engine has no other bring-up and deliberately has no such carrier (see engines/AGENTS.md),
    // and on iOS the static shim calls this entry directly.
    const rac_result_t policy_rc = rac_bundle_policy_register(neurt_bundle_policy());
    if (policy_rc != RAC_SUCCESS) {
        RAC_LOG_WARNING("NeuRT", "NeuRT bundle policy registration failed: %d", policy_rc);
    }
    return rac_engine_entry_with_manifest(&k_neurt_manifest, &g_neurt_engine_vtable);
}

}  // extern "C"
