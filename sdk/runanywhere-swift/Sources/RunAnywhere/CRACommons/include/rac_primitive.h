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

/* ===========================================================================
 * GAP 04: Runtime identifier (which compute target an engine uses)
 *
 * Distinct from rac_primitive_t (which models WHAT the engine does) and from
 * idl/model_types.proto::ModelFormat (which models the file format). Plugins
 * declare which runtimes they can serve via the `runtimes[]` metadata field
 * (added in GAP 04 Phase 11). The router scores plugins higher when the
 * caller's `preferred_runtime` matches one of the plugin's declared runtimes.
 *
 * Order is wire-stable. Add new runtimes in the reserved range only and bump
 * RAC_PLUGIN_API_VERSION when promoting a reserved value.
 * =========================================================================== */
typedef enum rac_runtime_id {
    RAC_RUNTIME_UNSPECIFIED = 0,

    RAC_RUNTIME_CPU         = 1,   /**< Plain CPU (SIMD ok). */
    RAC_RUNTIME_METAL       = 2,   /**< Apple Metal compute shaders. */
    RAC_RUNTIME_COREML      = 3,   /**< Apple Core ML (CPU/GPU/ANE chosen by CoreML). */
    RAC_RUNTIME_ANE         = 4,   /**< Apple Neural Engine (when explicitly requested). */
    RAC_RUNTIME_CUDA        = 5,   /**< NVIDIA CUDA. */
    RAC_RUNTIME_VULKAN      = 6,   /**< Vulkan compute. */
    RAC_RUNTIME_OPENCL      = 7,   /**< OpenCL. */
    RAC_RUNTIME_HIPBLAS     = 8,   /**< AMD HIP / ROCm. */
    RAC_RUNTIME_QNN         = 9,   /**< Qualcomm Hexagon (QNN). */
    RAC_RUNTIME_NNAPI       = 10,  /**< Android Neural Networks API. */
    RAC_RUNTIME_WEBGPU      = 11,  /**< Browser WebGPU. */
    RAC_RUNTIME_WASM_SIMD   = 12,  /**< Browser WebAssembly + SIMD. */

    /* Reserved slots — promote in order, never reorder. */
    RAC_RUNTIME_RESERVED_13 = 13,
    RAC_RUNTIME_RESERVED_14 = 14,
    RAC_RUNTIME_RESERVED_15 = 15,
    RAC_RUNTIME_RESERVED_16 = 16,
    RAC_RUNTIME_RESERVED_17 = 17,
    RAC_RUNTIME_RESERVED_18 = 18,
    RAC_RUNTIME_RESERVED_19 = 19,

    RAC_RUNTIME_LAST        = 31   /**< Sentinel; never assigned. */
} rac_runtime_id_t;

/**
 * Human-readable short name for a runtime. Never returns NULL.
 */
const char* rac_runtime_name(rac_runtime_id_t r);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_PRIMITIVE_H */
