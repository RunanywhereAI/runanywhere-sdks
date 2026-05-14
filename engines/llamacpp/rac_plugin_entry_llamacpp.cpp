/**
 * @file rac_plugin_entry_llamacpp.cpp
 * @brief Unified-ABI entry point for the llama.cpp LLM engine.
 *
 * GAP 02 Phase 8 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * Exposes `rac_plugin_entry_llamacpp()` returning a `const
 * rac_engine_vtable_t*` filled with the existing `g_llamacpp_ops` (non-static
 * since Phase 8) as the LLM slot. All other primitive slots remain NULL.
 *
 * v3.0.0: this is the SOLE llama.cpp registration path. The legacy
 * `rac_backend_llamacpp_register()` function now only does
 * `rac_module_register(...)`; it no longer calls
 * `rac_service_register_provider(...)` (removed in Phase B1). Plugin
 * registration flows through `RAC_STATIC_PLUGIN_REGISTER(llamacpp)`
 * (see `rac_static_register_llamacpp.cpp`) or through `dlopen` +
 * `rac_plugin_entry_llamacpp` symbol lookup.
 */

#include "rac/features/llm/rac_llm_service.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

extern "C" {

/* Defined in rac_backend_llamacpp_register.cpp (non-static since Phase 8). */
extern const rac_llm_service_ops_t g_llamacpp_ops;
rac_result_t rac_llamacpp_cpu_runtime_register(void);
void rac_llamacpp_cpu_runtime_unregister(void);

/* GAP 04 Phase 11: declare which runtimes + model formats this plugin serves
 * so the EngineRouter can score it against the caller's preferred_runtime
 * and model format. Apple-only entries are gated by __APPLE__ at the array
 * level so the table actually shrinks on non-Apple builds. */
static const rac_runtime_id_t k_llamacpp_runtimes[] = {
    RAC_RUNTIME_CPU,
#if defined(__APPLE__)
    RAC_RUNTIME_METAL,
#endif
#if !defined(__APPLE__) && !defined(__ANDROID__) && !defined(__EMSCRIPTEN__)
    /* Linux / Windows desktop builds may have CUDA. */
    RAC_RUNTIME_CUDA,
    RAC_RUNTIME_VULKAN,
#endif
};

/* Model formats use RAC_MODEL_FORMAT_ID_* values mirrored from
 * runanywhere.v1.ModelFormat. */
static const uint32_t k_llamacpp_formats[] = {
    RAC_MODEL_FORMAT_ID_GGUF,
    RAC_MODEL_FORMAT_ID_GGML,
    RAC_MODEL_FORMAT_ID_BIN,
};

static const rac_primitive_t k_llamacpp_primitives[] = {
    RAC_PRIMITIVE_GENERATE_TEXT,
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
    .primitives_count =
        sizeof(k_llamacpp_primitives) / sizeof(k_llamacpp_primitives[0]),
    .runtimes = k_llamacpp_runtimes,
    .runtimes_count =
        sizeof(k_llamacpp_runtimes) / sizeof(k_llamacpp_runtimes[0]),
    .formats = k_llamacpp_formats,
    .formats_count = sizeof(k_llamacpp_formats) / sizeof(k_llamacpp_formats[0]),
    .reserved_0 = 0,
    .reserved_1 = 0,
};

/* Static vtable in .rodata — registry records the pointer, does not copy. */
static void llamacpp_on_unload(void) { rac_llamacpp_cpu_runtime_unregister(); }

static const rac_engine_vtable_t g_llamacpp_engine_vtable = {
    /* metadata */ RAC_ENGINE_METADATA_FROM_MANIFEST(k_llamacpp_manifest),
    /* capability_check */ nullptr,
    /* on_unload        */ llamacpp_on_unload,

    /* llm_ops          */ &g_llamacpp_ops,
    /* stt_ops          */ nullptr,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr,
    /* vlm_ops          */ nullptr,
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

RAC_PLUGIN_ENTRY_DEF(llamacpp) {
  const rac_engine_vtable_t *vt = rac_engine_entry_with_manifest(
      &k_llamacpp_manifest, &g_llamacpp_engine_vtable);
  if (vt != nullptr) {
    (void)rac_llamacpp_cpu_runtime_register();
  }
  return vt;
}

} // extern "C"
