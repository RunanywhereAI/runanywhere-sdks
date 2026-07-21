/**
 * @file rac_plugin_entry_onnx.cpp
 * @brief Unified-ABI entry point for the ONNX Runtime backend.
 *
 * A single vtable exposes ONNX-owned primitives. Sherpa-backed speech
 * primitives live in engines/sherpa; ONNX retains embeddings and generic
 * ONNX Runtime model services.
 */

#include "rac_runtime_onnxrt.h"

#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/plugin/rac_engine_manifest.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

extern "C" {

/* Anchor the onnxrt runtime registrar translation unit at link
 * time. The onnx engine declares RAC_RUNTIME_ONNXRT in its manifest, so the
 * router hard-rejects it unless that runtime is in the registry. A file-scope
 * reference to rac_onnxrt_runtime_require_available — defined in the same TU as
 * RAC_STATIC_RUNTIME_REGISTER(onnxrt) — forces the linker to keep that TU on
 * RAG-off / hidden-visibility iOS builds where nothing else references the
 * onnxrt C++ Session symbols. `volatile` defeats dead-store elimination so the
 * reference survives optimization; we do NOT call it from capability_check
 * because the runtime registrar may fire after this engine registers (static
 * init order across TUs is unspecified), which would wrongly reject the
 * engine. Keeping the symbol live is sufficient — the router's
 * has_registered_declared_runtime gate validates availability at route time. */
void* const volatile rac_onnxrt_runtime_anchor =
    reinterpret_cast<void*>(&rac_onnxrt_runtime_require_available);

/* Embeddings ops live next to this file in
 * engines/onnx/rac_onnx_embeddings_register.cpp (engine-owned). When
 * RAC_BACKEND_RAG is off, onnx_embedding_provider.cpp is not compiled
 * and the symbol is unresolved — the vtable slot stays nullptr below
 * to match. */
#if defined(RAC_BACKEND_RAG)
extern const rac_embeddings_service_ops_t g_onnx_embeddings_ops;
#endif

static const rac_runtime_id_t k_onnx_runtimes[] = {
    RAC_RUNTIME_ONNXRT,
};

static const uint32_t k_onnx_formats[] = {
    RAC_MODEL_FORMAT_ID_ONNX,
    RAC_MODEL_FORMAT_ID_ORT,
};

#if defined(RAC_BACKEND_RAG)
static const rac_primitive_t k_onnx_primitives[] = {
    RAC_PRIMITIVE_EMBED,
};
#endif

// Autoregister regression fix: the onnx engine plugin
// only owns the embeddings primitive on this build (stt/tts/vad ops are
// nullptr and shipped by engines/sherpa). Keep priority below sherpa's 90.
static const rac_engine_manifest_t k_onnx_manifest = {
    .name = "onnx",
    .display_name = "ONNX Runtime",
    .version = nullptr,
    .package_owner = "runanywhere",
    .package_name = "rac_backend_onnx",
    .availability = RAC_ENGINE_AVAILABILITY_PUBLIC,
    .priority = 50,
    .capability_flags = 0,
#if defined(RAC_BACKEND_RAG)
    .primitives = k_onnx_primitives,
    .primitives_count = sizeof(k_onnx_primitives) / sizeof(k_onnx_primitives[0]),
#else
    .primitives = nullptr,
    .primitives_count = 0,
#endif
    .runtimes = k_onnx_runtimes,
    .runtimes_count = sizeof(k_onnx_runtimes) / sizeof(k_onnx_runtimes[0]),
    .formats = k_onnx_formats,
    .formats_count = sizeof(k_onnx_formats) / sizeof(k_onnx_formats[0]),
    .reserved_0 = 0,
    .reserved_1 = 0,
};

static const rac_engine_vtable_t g_onnx_engine_vtable = {
    /* metadata */ RAC_ENGINE_METADATA_FROM_MANIFEST(k_onnx_manifest),
    /* capability_check */ nullptr,
    /* on_unload        */ nullptr,

    /* llm_ops          */ nullptr,
    /* stt_ops          */ nullptr,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
#if defined(RAC_BACKEND_RAG)
    /* embedding_ops    */ &g_onnx_embeddings_ops,
#else
    /* embedding_ops    */ nullptr,
#endif
    /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ nullptr,
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

RAC_PLUGIN_ENTRY_DEF(onnx) {
    return rac_engine_entry_with_manifest(&k_onnx_manifest, &g_onnx_engine_vtable);
}

}  // extern "C"
