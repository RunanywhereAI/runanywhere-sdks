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

#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/diffusion/rac_diffusion_service.h"

extern "C" {

/* Defined in rac_backend_platform_register.cpp as extern (v3 Phase B7). */
extern const rac_llm_service_ops_t       g_platform_llm_ops;
extern const rac_tts_service_ops_t       g_platform_tts_ops;
extern const rac_diffusion_service_ops_t g_platform_diffusion_ops;

/* Apple platform services run on the Apple Neural Engine (COREML) and
 * CPU fallback. Foundation Models + AVSpeechSynthesizer are OS-level and
 * don't care about a specific runtime — the COREML entry here is a
 * best-fit hint for the router. */
static const rac_runtime_id_t k_platform_runtimes[] = {
    RAC_RUNTIME_COREML,
    RAC_RUNTIME_CPU,
};

/* Model formats we serve. COREML = 5 in runanywhere.v1.ModelFormat (see
 * sdk/runanywhere-commons/proto/runanywhere/v1/common.proto); the built-in
 * Foundation Models and System TTS don't have a filesystem format so they
 * won't appear here — the router accepts builtin:// URIs without format
 * gating. */
static const uint32_t k_platform_formats[] = {
    /* MODEL_FORMAT_COREML — Apple CoreML .mlmodelc / .mlpackage */
    5,
};

static const rac_engine_vtable_t g_platform_engine_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,
        .name             = "platform",
        .display_name     = "Apple Platform Services",
        .engine_version   = nullptr,
        /* Diffusion: high priority (100) — it's the sole CoreML diffusion
         * provider. LLM: lower priority (50) — llamacpp is preferred on
         * macOS when a GGUF model is available. TTS: system TTS is the
         * lowest-priority fallback (10). Per-primitive priority tweaking
         * isn't in the ABI yet; we use the router's format-match bonus
         * (e.g. COREML models hit this plugin naturally). */
        .priority         = 50,
        .capability_flags = 0,
        .runtimes         = k_platform_runtimes,
        .runtimes_count   = sizeof(k_platform_runtimes) / sizeof(k_platform_runtimes[0]),
        .formats          = k_platform_formats,
        .formats_count    = sizeof(k_platform_formats) / sizeof(k_platform_formats[0]),
    },
    /* capability_check */ nullptr,
    /* on_unload        */ nullptr,

    /* llm_ops          */ &g_platform_llm_ops,
    /* stt_ops          */ nullptr,
    /* tts_ops          */ &g_platform_tts_ops,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr,
    /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ &g_platform_diffusion_ops,

    /* reserved_slot_0..9 */
    nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
};

RAC_PLUGIN_ENTRY_DEF(platform) {
    return &g_platform_engine_vtable;
}

}  // extern "C"

#endif  // __APPLE__
