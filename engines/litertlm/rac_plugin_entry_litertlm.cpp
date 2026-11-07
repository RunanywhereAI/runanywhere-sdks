/**
 * @file rac_plugin_entry_litertlm.cpp
 * @brief Unified-ABI entry point of the LiteRT-LM engine.
 *
 * Two compile modes, selected by RAC_LITERTLM_ENGINE_AVAILABLE from
 * CMakeLists.txt (USAGE B in engines/common/rac_engine_unavailable.h):
 *
 *   - ROUTABLE (library linked): a manifest and vtable that serve
 *     RAC_PRIMITIVE_GENERATE_TEXT through g_litertlm_llm_ops.
 *   - STUB (library absent): the shared not-routable shell, whose
 *     capability_check rejects registration.
 */

#include "common/rac_engine_unavailable.h"
#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

#if defined(RAC_LITERTLM_ENGINE_AVAILABLE) && RAC_LITERTLM_ENGINE_AVAILABLE
#define RAC_LITERTLM_ROUTABLE 1
#include "c/engine.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/plugin/rac_model_format_ids.h"
#include "rac/plugin/rac_primitive.h"
#else
#define RAC_LITERTLM_ROUTABLE 0
#endif

namespace {

rac_result_t litertlm_capability_check(void) {
#if RAC_LITERTLM_ROUTABLE
    // The library can be replaced independently of this code, so compare it with
    // the headers as engine.h prescribes before any other call.
    int major = 0;
    int minor = 0;
    int patch = 0;
    if (litert_lm_get_api_version(&major, &minor, &patch) != kLiteRtLmStatusOk ||
        major != LITERT_LM_C_API_VERSION_MAJOR || minor < LITERT_LM_C_API_VERSION_MINOR) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
#endif
    return rac_engine_unavailable_capability(/* platform_supported */ 1, RAC_LITERTLM_ROUTABLE);
}

}  // namespace

extern "C" {

#if RAC_LITERTLM_ROUTABLE

extern const rac_llm_service_ops_t g_litertlm_llm_ops;

static const rac_primitive_t k_litertlm_primitives[] = {RAC_PRIMITIVE_GENERATE_TEXT};

static const uint32_t k_litertlm_formats[] = {RAC_MODEL_FORMAT_ID_LITERTLM};

static const rac_engine_manifest_t k_litertlm_manifest = {
    .name = "litertlm",
    .display_name = "LiteRT-LM",
    .version = nullptr,
    .package_owner = "runanywhere",
    .package_name = "runanywhere_litertlm",
    .availability = RAC_ENGINE_AVAILABILITY_PUBLIC,
    // Below llamacpp (100): the lifecycle pins .litertlm models to this engine
    // by framework, so it never needs to win plain priority selection.
    .priority = 80,
    .capability_flags = 0,
    .primitives = k_litertlm_primitives,
    .primitives_count = sizeof(k_litertlm_primitives) / sizeof(k_litertlm_primitives[0]),
    // None declared: the device is chosen at load, so a fixed one would be reported for every
    // model. Commons reports "unknown" instead, as for llama.cpp.
    .runtimes = nullptr,
    .runtimes_count = 0,
    .formats = k_litertlm_formats,
    .formats_count = sizeof(k_litertlm_formats) / sizeof(k_litertlm_formats[0]),
    .reserved_0 = 0,
    .reserved_1 = 0,
};

static const rac_engine_vtable_t g_litertlm_engine_vtable = {
    /* metadata         */ RAC_ENGINE_METADATA_FROM_MANIFEST(k_litertlm_manifest),
    /* capability_check */ litertlm_capability_check,
    /* on_unload        */ nullptr,

    /* llm_ops          */ &g_litertlm_llm_ops,
    /* stt_ops          */ nullptr,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ nullptr,
    /* diarization_ops  */ nullptr,
    /* segmentation_ops */ nullptr,

    /* rerank_ops       */ nullptr,
    /* image_embedding_ops */ nullptr,
    /* ocr_ops          */ nullptr,
    /* decision_ops     */ nullptr,
    /* reserved_slot_6..9 */
    nullptr,
    nullptr,
    nullptr,
    nullptr,
};

RAC_PLUGIN_ENTRY_DEF(litertlm) {
    return rac_engine_entry_with_manifest(&k_litertlm_manifest, &g_litertlm_engine_vtable);
}

#else  // !RAC_LITERTLM_ROUTABLE

RAC_ENGINE_UNAVAILABLE_PLUGIN(litertlm, "LiteRT-LM", litertlm_capability_check)

#endif  // RAC_LITERTLM_ROUTABLE

}  // extern "C"
