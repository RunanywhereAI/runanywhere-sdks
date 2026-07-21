/**
 * @file rac_plugin_entry_cloud.cpp
 * @brief Unified-ABI entry point for the generic cloud backend.
 *
 * The cloud engine fronts HTTP providers with no local compute substrate. Its
 * NAME is modality-agnostic: it serves STT today (RAC_PRIMITIVE_TRANSCRIBE)
 * backed by the shared `g_cloud_stt_ops` HTTP/STT vtable in rac_stt_cloud.cpp,
 * and future modalities (TTS / LLM / embeddings) attach by filling more ops
 * slots in the engine vtable below. Mirrors the sherpa plugin (manifest + engine
 * vtable + RAC_PLUGIN_ENTRY_DEF) so the engine is routable through the plugin
 * registry via `rac_plugin_find_for_engine(RAC_PRIMITIVE_TRANSCRIBE, "cloud")`. The
 * concrete provider is selected per-service from the create config
 * (`{"provider":"sarvam"}`), not at the manifest level.
 *
 * Cloud-specific manifest shape:
 *   - runtimes = NULL, runtimes_count = 0 — no local compute substrate. The
 *     router treats zero declared runtimes as "no runtime bonus, never
 *     runtime-rejected", i.e. always eligible, which is correct for a cloud
 *     engine.
 *   - formats = NULL, formats_count = 0 — there is no local MODEL FILE to
 *     match a RAC_MODEL_FORMAT_ID_* against (the manifest `formats` set is the
 *     model-file-format enum, which has no audio-container members). The audio
 *     container accepted (PCM/WAV/MP3/OPUS/AAC/FLAC) is selected per-request
 *     inside ops_transcribe via rac_stt_options_t::audio_format, not via this
 *     routing field. Zero formats = no format bonus, still eligible.
 *   - availability = PUBLIC.
 */

#include "rac/backends/rac_stt_cloud.h"  // extern const rac_stt_service_ops_t g_cloud_stt_ops
#include "rac/core/rac_error.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_cloud.h"

extern "C" {

// The cloud engine is always "available" at registration time — there is no
// local runtime / model file to probe. A missing/invalid API key or unknown
// provider surfaces per-call inside ops_create / ops_transcribe
// (RAC_ERROR_INVALID_CONFIGURATION / RAC_ERROR_HTTP_ERROR), not as a
// plugin-level capability rejection, so the engine stays routable and reports
// the failure at use time.
static rac_result_t cloud_capability_check(void) {
    return RAC_SUCCESS;
}

// STT is the only modality today. A future cloud TTS/LLM/embeddings modality
// adds its primitive here (and fills the matching ops slot below).
static const rac_primitive_t k_cloud_primitives[] = {
    RAC_PRIMITIVE_TRANSCRIBE,
};

static const rac_engine_manifest_t k_cloud_manifest = {
    .name = "cloud",
    .display_name = "Cloud (HTTP providers)",
    .version = nullptr,
    .package_owner = "runanywhere",
    .package_name = "runanywhere_cloud",
    .availability = RAC_ENGINE_AVAILABILITY_PUBLIC,
    .priority = 50,
    .capability_flags = 0,
    .primitives = k_cloud_primitives,
    .primitives_count = sizeof(k_cloud_primitives) / sizeof(k_cloud_primitives[0]),
    // Cloud engine: no local runtime substrate, no local model file format.
    .runtimes = nullptr,
    .runtimes_count = 0,
    .formats = nullptr,
    .formats_count = 0,
    .reserved_0 = 0,
    .reserved_1 = 0,
};

static const rac_engine_vtable_t g_cloud_engine_vtable = {
    /* metadata         */ RAC_ENGINE_METADATA_FROM_MANIFEST(k_cloud_manifest),
    /* capability_check */ cloud_capability_check,
    /* on_unload        */ nullptr,

    // The cloud engine's STT modality wires its op-table here. To add a cloud
    // TTS/LLM/embeddings modality: fill `tts_ops`/`llm_ops`/`embedding_ops`
    // here with that modality's ops (backed by per-modality provider adapters
    // under `providers/`), and add its primitive to k_cloud_manifest.primitives.
    /* llm_ops          */ nullptr,
    /* stt_ops          */ &g_cloud_stt_ops,  // STT modality of the cloud engine
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* vlm_ops          */ nullptr,
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

RAC_PLUGIN_ENTRY_DEF(cloud) {
    return rac_engine_entry_with_manifest(&k_cloud_manifest, &g_cloud_engine_vtable);
}

}  // extern "C"
