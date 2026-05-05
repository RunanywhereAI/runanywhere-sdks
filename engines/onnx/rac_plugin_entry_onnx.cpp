/**
 * @file rac_plugin_entry_onnx.cpp
 * @brief Unified-ABI entry point for the ONNX Runtime backend.
 *
 * GAP 02 Phase 9 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * A single vtable exposes ONNX-owned primitives. Sherpa-backed speech
 * primitives live in engines/sherpa; ONNX retains embeddings and generic
 * ONNX Runtime model services.
 */

#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/features/embeddings/rac_embeddings_service.h"

extern "C" {

/* v3 Phase B7: embeddings ops live in sdk/runanywhere-commons/src/features/rag/
 * rac_onnx_embeddings_register.cpp but are plugged into this engine's
 * vtable since onnx naturally owns the embedding primitive. */
extern const rac_embeddings_service_ops_t g_onnx_embeddings_ops;

static const rac_runtime_id_t k_onnx_runtimes[] = {
    RAC_RUNTIME_ONNXRT,
};

static const uint32_t k_onnx_formats[] = {
    RAC_MODEL_FORMAT_ID_ONNX,
    RAC_MODEL_FORMAT_ID_ORT,
};

static const rac_primitive_t k_onnx_primitives[] = {
    RAC_PRIMITIVE_EMBED,
};

// P0 regression fix (post FIX-AK17 autoregister): the onnx engine plugin
// only owns the embeddings primitive on this build (stt/tts/vad ops are
// nullptr and shipped by engines/sherpa). Keep priority below sherpa's 90.
static const rac_engine_manifest_t k_onnx_manifest = {
    .name             = "onnx",
    .display_name     = "ONNX Runtime",
    .version          = nullptr,
    .package_owner    = "runanywhere",
    .package_name     = "rac_backend_onnx",
    .availability     = RAC_ENGINE_AVAILABILITY_PUBLIC,
    .priority         = 50,
    .capability_flags = 0,
    .primitives       = k_onnx_primitives,
    .primitives_count = sizeof(k_onnx_primitives) / sizeof(k_onnx_primitives[0]),
    .runtimes         = k_onnx_runtimes,
    .runtimes_count   = sizeof(k_onnx_runtimes) / sizeof(k_onnx_runtimes[0]),
    .formats          = k_onnx_formats,
    .formats_count    = sizeof(k_onnx_formats) / sizeof(k_onnx_formats[0]),
    .reserved_0       = 0,
    .reserved_1       = 0,
};

static const rac_engine_vtable_t g_onnx_engine_vtable = {
    /* metadata */ RAC_ENGINE_METADATA_FROM_MANIFEST(k_onnx_manifest),
    /* capability_check */ nullptr,
    /* on_unload        */ nullptr,

    /* llm_ops          */ nullptr,
    /* stt_ops          */ nullptr,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ &g_onnx_embeddings_ops,
    /* rerank_ops       */ nullptr,
    /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ nullptr,

    /* reserved_slot_0..9 */
    nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
};

RAC_PLUGIN_ENTRY_DEF(onnx) {
    return rac_engine_entry_with_manifest(&k_onnx_manifest,
                                          &g_onnx_engine_vtable);
}

}  // extern "C"

// B-AK-17-002 fix: librac_backend_onnx.so is loaded via System.loadLibrary by
// the SDK example apps (Kotlin/Flutter/RN). Without an explicit caller that
// runs `rac_backend_onnx_register()` BEFORE RAG flow starts, the unified
// plugin registry never sees the ONNX engine vtable (and its embedding_ops
// slot), so `rac_plugin_route(RAC_PRIMITIVE_EMBED)` returns NOT_FOUND. This
// breaks RAG pipeline creation even when the .so ships in the APK.
//
// Mirror the Sherpa fix (engines/sherpa/rac_plugin_entry_sherpa.cpp): use the
// standard ELF constructor attribute so the engine plugin auto-registers when
// the dynamic linker loads this .so. The plugin registry deduplicates by name,
// so the explicit `rac_backend_onnx_register()` path remains safe.
#if defined(__GNUC__) || defined(__clang__)
extern "C" {
__attribute__((constructor))
static void rac_onnx_autoregister_on_load(void) {
    const rac_engine_vtable_t* vt = rac_plugin_entry_onnx();
    if (vt != nullptr) {
        (void)rac_plugin_register(vt);
    }
}
}  // extern "C"
#endif
