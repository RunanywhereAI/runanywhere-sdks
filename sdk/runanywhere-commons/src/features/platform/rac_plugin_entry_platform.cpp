/**
 * @file rac_plugin_entry_platform.cpp
 * @brief Unified-ABI entry point for Apple platform services.
 *
 * v3 Phase B7. Wraps the 3 platform primitives (LLM = Apple Foundation
 * Models, TTS = AVSpeechSynthesizer, Diffusion = CoreML Diffusion) into
 * a single rac_engine_vtable_t so the router can select them via
 * framework hints and model formats instead of the deleted legacy
 * rac_service_register_provider() path.
 *
 * The Swift-side callbacks (rac_platform_llm_get_callbacks etc.) are
 * still what actually performs work — this file only exposes the
 * vtable to the plugin registry.
 */
#if defined(__APPLE__)

#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

extern "C" {

/* Defined in rac_backend_platform_register.cpp as extern (v3 Phase B7). */
extern const rac_llm_service_ops_t g_platform_llm_ops;
extern const rac_tts_service_ops_t g_platform_tts_ops;
extern const rac_diffusion_service_ops_t g_platform_diffusion_ops;

/* Apple platform services run on the Apple Neural Engine (COREML) and
 * CPU fallback. Foundation Models + AVSpeechSynthesizer are OS-level and
 * don't care about a specific runtime — the COREML entry here is a
 * best-fit hint for the router. */
static const rac_runtime_id_t k_platform_runtimes[] = {
    RAC_RUNTIME_COREML,
    RAC_RUNTIME_CPU,
};

/* Built-in Foundation Models and System TTS do not have a filesystem format,
 * so they do not appear here; the router accepts builtin:// URIs without
 * format gating. */
static const uint32_t k_platform_formats[] = {
    RAC_MODEL_FORMAT_ID_COREML,
};

static const rac_primitive_t k_platform_primitives[] = {
    RAC_PRIMITIVE_GENERATE_TEXT,
    RAC_PRIMITIVE_SYNTHESIZE,
    RAC_PRIMITIVE_DIFFUSION,
};

static const rac_engine_manifest_t k_platform_manifest = {
    .name = "platform",
    .display_name = "Apple Platform Services",
    .version = nullptr,
    .package_owner = "runanywhere",
    .package_name = "runanywhere_platform",
    .availability = RAC_ENGINE_AVAILABILITY_PRIVATE, /* Apple-only. */
    /* Diffusion: high priority (100) — it's the sole CoreML diffusion
     * provider. LLM: lower priority (50) — llamacpp is preferred on
     * macOS when a GGUF model is available. TTS: system TTS is the
     * lowest-priority fallback (10). Per-primitive priority tweaking
     * isn't in the ABI yet; we use the router's format-match bonus
     * (e.g. COREML models hit this plugin naturally). */
    .priority = 50,
    .capability_flags = 0,
    .primitives = k_platform_primitives,
    .primitives_count = sizeof(k_platform_primitives) / sizeof(k_platform_primitives[0]),
    .runtimes = k_platform_runtimes,
    .runtimes_count = sizeof(k_platform_runtimes) / sizeof(k_platform_runtimes[0]),
    .formats = k_platform_formats,
    .formats_count = sizeof(k_platform_formats) / sizeof(k_platform_formats[0]),
    .reserved_0 = 0,
    .reserved_1 = 0,
};

static const rac_engine_vtable_t g_platform_engine_vtable = {
    /* metadata */ RAC_ENGINE_METADATA_FROM_MANIFEST(k_platform_manifest),
    /* capability_check */ nullptr,
    /* on_unload        */ nullptr,

    /* llm_ops          */ &g_platform_llm_ops,
    /* stt_ops          */ nullptr,
    /* tts_ops          */ &g_platform_tts_ops,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ &g_platform_diffusion_ops,

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

RAC_PLUGIN_ENTRY_DEF(platform) {
    return rac_engine_entry_with_manifest(&k_platform_manifest, &g_platform_engine_vtable);
}

}  // extern "C"

#endif  // __APPLE__
