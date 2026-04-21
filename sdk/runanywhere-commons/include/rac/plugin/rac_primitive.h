/**
 * @file rac_primitive.h
 * @brief Canonical enumeration of runtime primitives exposed by engine plugins.
 *
 * GAP 02 Phase 7 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * Every engine plugin (llama.cpp, ONNX Runtime, whispercpp, WhisperKit CoreML,
 * MetalRT, …) declares which of these primitives it serves via the new unified
 * `rac_engine_vtable_t`. The pipeline runtime keys off this enum to dispatch
 * operators to engines.
 *
 * IMPORTANT: values are stable wire numbers. Do NOT reorder. Add new
 * primitives at the end and bump `RAC_PLUGIN_API_VERSION` in
 * `rac_plugin_entry.h`.
 */

#ifndef RAC_PLUGIN_PRIMITIVE_H
#define RAC_PLUGIN_PRIMITIVE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Runtime primitive identifiers.
 *
 * Order matches the per-primitive slot groups inside `rac_engine_vtable_t`:
 * each primitive's ops pointer lives at a known offset so the registry can
 * look up engines by primitive without reflection.
 */
typedef enum rac_primitive {
    RAC_PRIMITIVE_UNSPECIFIED = 0,
    RAC_PRIMITIVE_GENERATE_TEXT = 1,   /**< Large Language Models (text → text). */
    RAC_PRIMITIVE_TRANSCRIBE    = 2,   /**< Speech-to-Text. */
    RAC_PRIMITIVE_SYNTHESIZE    = 3,   /**< Text-to-Speech. */
    RAC_PRIMITIVE_DETECT_VOICE  = 4,   /**< Voice Activity Detection. */
    RAC_PRIMITIVE_EMBED         = 5,   /**< Embedding / vectorization. */
    RAC_PRIMITIVE_RERANK        = 6,   /**< Cross-encoder reranking for RAG. */
    RAC_PRIMITIVE_VLM           = 7,   /**< Vision-Language Models. */
    RAC_PRIMITIVE_DIFFUSION     = 8,   /**< Text-to-Image / Image-to-Image diffusion. */

    /* Reserved primitive slots — added to prevent struct re-layout when new
     * primitives land. Bump RAC_PLUGIN_API_VERSION when promoting any of
     * these. */
    RAC_PRIMITIVE_RESERVED_9    = 9,
    RAC_PRIMITIVE_RESERVED_10   = 10,
    RAC_PRIMITIVE_RESERVED_11   = 11,
    RAC_PRIMITIVE_RESERVED_12   = 12,
    RAC_PRIMITIVE_RESERVED_13   = 13,
    RAC_PRIMITIVE_RESERVED_14   = 14,
    RAC_PRIMITIVE_RESERVED_15   = 15,
    RAC_PRIMITIVE_RESERVED_16   = 16,
    RAC_PRIMITIVE_RESERVED_17   = 17,
    RAC_PRIMITIVE_RESERVED_18   = 18,

    RAC_PRIMITIVE_COUNT
} rac_primitive_t;

/**
 * Human-readable short name for a primitive. Never returns NULL; returns
 * "unknown" for out-of-range values. Safe to call from C or C++.
 */
const char* rac_primitive_name(rac_primitive_t p);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_PRIMITIVE_H */
