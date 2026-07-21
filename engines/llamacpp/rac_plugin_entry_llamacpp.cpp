/**
 * @file rac_plugin_entry_llamacpp.cpp
 * @brief Unified-ABI entry point for the llama.cpp engine.
 *
 * Exposes `rac_plugin_entry_llamacpp()` returning a `const
 * rac_engine_vtable_t*` with `llm_ops`, `embedding_ops`, and `vlm_ops` filled —
 * llama.cpp is one engine that supports text generation, text embeddings, and
 * vision-language inference as modalities of the same backend.
 *
 * Per the v3 ABI principle ("each backend publishes a single
 * `rac_engine_vtable_t`"), this is the SOLE llama.cpp plugin entry. The
 * earlier split into `llamacpp` + `llamacpp_vlm` entries existed for
 * compile-time gating of mtmd; that gating has been removed (mtmd always
 * compiles in) and the two entries have been unified.
 *
 * Plugin registration flows through `RAC_STATIC_PLUGIN_REGISTER(llamacpp)`
 * (see `rac_static_register_llamacpp.cpp`) or through `dlopen` +
 * `rac_plugin_entry_llamacpp` symbol lookup.
 */

#include <cstddef>
#include <mutex>

#include "rac/core/rac_error.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

extern "C" {

/* Defined in rac_backend_llamacpp_register.cpp. */
extern const rac_llm_service_ops_t g_llamacpp_ops;
/* Defined in rac_embeddings_llamacpp.cpp. */
extern const rac_embeddings_service_ops_t g_llamacpp_embeddings_ops;
/* Defined in rac_llamacpp_vlm_ops.cpp. */
extern const rac_vlm_service_ops_t g_llamacpp_vlm_ops;

rac_result_t rac_llamacpp_cpu_runtime_register(void);
void rac_llamacpp_cpu_runtime_unregister(void);

}  // extern "C"

namespace {

std::mutex g_llamacpp_runtime_mutex;
std::size_t g_llamacpp_runtime_refcount = 0;

void retain_llamacpp_cpu_runtime() {
    std::lock_guard<std::mutex> lock(g_llamacpp_runtime_mutex);
    if (g_llamacpp_runtime_refcount == 0) {
        rac_result_t rc = rac_llamacpp_cpu_runtime_register();
        if (rc != RAC_SUCCESS) {
            return;
        }
    }
    ++g_llamacpp_runtime_refcount;
}

void release_llamacpp_cpu_runtime() {
    std::lock_guard<std::mutex> lock(g_llamacpp_runtime_mutex);
    if (g_llamacpp_runtime_refcount == 0) {
        return;
    }
    --g_llamacpp_runtime_refcount;
    if (g_llamacpp_runtime_refcount == 0) {
        rac_llamacpp_cpu_runtime_unregister();
    }
}

}  // namespace

extern "C" {

/* Declares which runtimes + model formats this plugin serves. This is advisory
 * metadata: it is validated for consistency at registration but NOT used for
 * engine selection (selection is plain priority order via rac_plugin_find).
 * Each GPU runtime is still gated on the matching ggml backend macro that
 * llama.cpp's CMake actually defines for this build, so the advertised runtimes
 * honestly reflect the linked llama.cpp (advertising one it was not compiled
 * with would misinform tooling/telemetry). Cf. get_device_type() in
 * llamacpp_backend.cpp which checks the same macros. */
static const rac_runtime_id_t k_llamacpp_runtimes[] = {
    RAC_RUNTIME_CPU,
#if defined(GGML_USE_METAL)
    RAC_RUNTIME_METAL,
#endif
#if defined(GGML_USE_CUDA)
    RAC_RUNTIME_CUDA,
#endif
#if defined(GGML_USE_VULKAN)
    RAC_RUNTIME_VULKAN,
#endif
};

/* GGUF for LLM/VLM weights, GGML for legacy LLM, BIN for VLM mmproj files. */
static const uint32_t k_llamacpp_formats[] = {
    RAC_MODEL_FORMAT_ID_GGUF,
    RAC_MODEL_FORMAT_ID_GGML,
    RAC_MODEL_FORMAT_ID_BIN,
};

/* This single plugin serves text generation, embeddings, and VLM primitives. */
static const rac_primitive_t k_llamacpp_primitives[] = {
    RAC_PRIMITIVE_GENERATE_TEXT,
    RAC_PRIMITIVE_EMBED,
    RAC_PRIMITIVE_VLM,
};

static const rac_engine_manifest_t k_llamacpp_manifest = {
    .name = "llamacpp",
    .display_name = "llama.cpp",
    .version = nullptr,
    .package_owner = "runanywhere",
    .package_name = "runanywhere_llamacpp",
    .availability = RAC_ENGINE_AVAILABILITY_PUBLIC,
    .priority = 100,
    .capability_flags = 0,
    .primitives = k_llamacpp_primitives,
    .primitives_count = sizeof(k_llamacpp_primitives) / sizeof(k_llamacpp_primitives[0]),
    .runtimes = k_llamacpp_runtimes,
    .runtimes_count = sizeof(k_llamacpp_runtimes) / sizeof(k_llamacpp_runtimes[0]),
    .formats = k_llamacpp_formats,
    .formats_count = sizeof(k_llamacpp_formats) / sizeof(k_llamacpp_formats[0]),
    .reserved_0 = 0,
    .reserved_1 = 0,
};

/* Static vtable in .rodata — registry records the pointer, does not copy. */
static void llamacpp_on_unload(void) {
    release_llamacpp_cpu_runtime();
}

static const rac_engine_vtable_t g_llamacpp_engine_vtable = {
    /* metadata */ RAC_ENGINE_METADATA_FROM_MANIFEST(k_llamacpp_manifest),
    /* capability_check */ nullptr,
    /* on_unload        */ llamacpp_on_unload,

    /* llm_ops          */ &g_llamacpp_ops,
    /* stt_ops          */ nullptr,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ &g_llamacpp_embeddings_ops,
    /* vlm_ops          */ &g_llamacpp_vlm_ops,
    /* diffusion_ops    */ nullptr,
    /* diarization_ops  */ nullptr,
    /* segmentation_ops */ nullptr,
    /* vocoder_ops      */ nullptr,

    /* reserved_slot_3..9 */
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
};

RAC_PLUGIN_ENTRY_DEF(llamacpp) {
    const rac_engine_vtable_t* vt =
        rac_engine_entry_with_manifest(&k_llamacpp_manifest, &g_llamacpp_engine_vtable);
    if (vt != nullptr) {
        retain_llamacpp_cpu_runtime();
    }
    return vt;
}

/* The legacy "llamacpp_vlm" plugin alias was removed: the unified
 * "llamacpp" plugin already serves both LLM and VLM primitives, so it now
 * registers only under "llamacpp" and there is no alias to normalize.
 * Registering a second plugin only added registry noise. */

}  // extern "C"
