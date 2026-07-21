/**
 * @file rac_plugin_entry_qhexrt.cpp
 * @brief Unified-ABI entry point for the QHexRT (Qualcomm Hexagon NPU) engine.
 *
 * Two compile modes (USAGE B in engines/common/rac_engine_unavailable.h),
 * selected by RAC_QHEXRT_ENGINE_AVAILABLE from CMakeLists.txt:
 *
 *   - ROUTABLE (engine linked): a hand-written manifest + vtable exposing
 *     RAC_PRIMITIVE_GENERATE_TEXT via g_qhexrt_llm_ops (qhexrt_llm_ops.cpp).
 *   - STUB (engine absent, the public default): the shared all-NULL,
 *     not-routable shell whose capability_check rejects registration so the
 *     router can never select QHexRT.
 *
 * Both modes expose the SAME `rac_plugin_entry_qhexrt` symbol and the same
 * `.rodata` vtable contract, so downstream SDK bridges load either build with
 * no platform-specific branches.
 */

#include "qhexrt_backend.h"

#include "common/rac_engine_unavailable.h"
#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

#if defined(__ANDROID__) && defined(RAC_QHEXRT_ENGINE_AVAILABLE) && RAC_QHEXRT_ENGINE_AVAILABLE
#define RAC_QHEXRT_ROUTABLE 1
#else
#define RAC_QHEXRT_ROUTABLE 0
#endif

#if RAC_QHEXRT_ROUTABLE
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/plugin/rac_model_format_ids.h"
#include "rac/plugin/rac_primitive.h"
#endif

namespace {

// capability_check runs during rac_plugin_register, before the plugin enters
// the primitive tables. QHexRT targets Snapdragon Android only; off-platform
// builds report UNSUPPORTED (silent), Android builds without the linked engine
// report BACKEND_UNAVAILABLE. The 3-way decision is the shared helper.
rac_result_t qhexrt_capability_check(void) {
    return rac_engine_unavailable_capability(
#if defined(__ANDROID__)
        1, /* platform_supported: runtime targets Snapdragon Android */
#else
        0,
#endif
#if defined(RAC_QHEXRT_ENGINE_AVAILABLE) && RAC_QHEXRT_ENGINE_AVAILABLE
        1 /* backend_present: prebuilt QHexRT archive linked */
#else
        0
#endif
    );
}

}  // namespace

extern "C" {

// Build marker (both modes) — lets tests assert engine visibility without the
// private QHexRT header.
const char* qhexrt_backend_build_info(void) {
#if RAC_QHEXRT_ROUTABLE
    return "qhexrt:engine-available";
#else
    return "qhexrt:engine-unavailable";
#endif
}

#if RAC_QHEXRT_ROUTABLE

// Per-modality vtables defined in qhexrt_{llm,vlm,stt,tts}_ops.cpp.
extern const rac_llm_service_ops_t g_qhexrt_llm_ops;
extern const rac_vlm_service_ops_t g_qhexrt_vlm_ops;
extern const rac_stt_service_ops_t g_qhexrt_stt_ops;
extern const rac_tts_service_ops_t g_qhexrt_tts_ops;
extern const rac_embeddings_service_ops_t g_qhexrt_embeddings_ops;
extern const rac_diffusion_service_ops_t g_qhexrt_diffusion_ops;

// Advisory routing metadata (validated at register, NOT used for selection —
// selection is plain priority order via rac_plugin_find).
static const rac_runtime_id_t k_qhexrt_runtimes[] = {RAC_RUNTIME_QNN};

// QHexRT runs prebuilt QNN context binaries referenced by a JSON manifest.
static const uint32_t k_qhexrt_formats[] = {RAC_MODEL_FORMAT_ID_QNN_CONTEXT};

// One engine, six modalities. Diffusion is intentionally the existing image-generation
// primitive: LaMa serves only its inpainting mode, with host preprocessing around one QNN graph.
static const rac_primitive_t k_qhexrt_primitives[] = {
    RAC_PRIMITIVE_GENERATE_TEXT, RAC_PRIMITIVE_VLM,   RAC_PRIMITIVE_TRANSCRIBE,
    RAC_PRIMITIVE_SYNTHESIZE,    RAC_PRIMITIVE_EMBED, RAC_PRIMITIVE_DIFFUSION,
};

static const rac_engine_manifest_t k_qhexrt_manifest = {
    .name = "qhexrt",
    .display_name = "QHexRT (Qualcomm Hexagon NPU)",
    .version = nullptr,
    .package_owner = "runanywhere",
    .package_name = "runanywhere_qhexrt",
    .availability = RAC_ENGINE_AVAILABILITY_PRIVATE,
    // Above llamacpp (100). Safe only because lifecycle pins QNN-context models
    // to framework QHEXRT; generic primitive selection remains plain priority.
    .priority = 150,
    .capability_flags = 0,
    .primitives = k_qhexrt_primitives,
    .primitives_count = sizeof(k_qhexrt_primitives) / sizeof(k_qhexrt_primitives[0]),
    .runtimes = k_qhexrt_runtimes,
    .runtimes_count = sizeof(k_qhexrt_runtimes) / sizeof(k_qhexrt_runtimes[0]),
    .formats = k_qhexrt_formats,
    .formats_count = sizeof(k_qhexrt_formats) / sizeof(k_qhexrt_formats[0]),
    .reserved_0 = 0,
    .reserved_1 = 0,
};

static const rac_engine_vtable_t g_qhexrt_engine_vtable = {
    /* metadata         */ RAC_ENGINE_METADATA_FROM_MANIFEST(k_qhexrt_manifest),
    /* capability_check */ qhexrt_capability_check,
    /* on_unload        */ nullptr,

    /* llm_ops          */ &g_qhexrt_llm_ops,
    /* stt_ops          */ &g_qhexrt_stt_ops,
    /* tts_ops          */ &g_qhexrt_tts_ops,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ &g_qhexrt_embeddings_ops,
    /* vlm_ops          */ &g_qhexrt_vlm_ops,
    /* diffusion_ops    */ &g_qhexrt_diffusion_ops,
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

RAC_PLUGIN_ENTRY_DEF(qhexrt) {
    return rac_engine_entry_with_manifest(&k_qhexrt_manifest, &g_qhexrt_engine_vtable);
}

#else  // !RAC_QHEXRT_ROUTABLE — not-routable shell (public default)

RAC_ENGINE_UNAVAILABLE_PLUGIN(qhexrt, "QHexRT (Qualcomm Hexagon NPU)", qhexrt_capability_check)

#endif  // RAC_QHEXRT_ROUTABLE

}  // extern "C"
