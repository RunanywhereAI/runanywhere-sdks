/**
 * @file rac_engine_vtable.h
 * @brief Unified engine plugin vtable.
 *
 * GAP 02 Phase 7 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * A single vtable type replaces the per-domain `rac_llm_service_ops_t`,
 * `rac_stt_service_ops_t`, `rac_tts_service_ops_t`, … structs. Every engine
 * backend (llama.cpp, ONNX, whispercpp, WhisperKit CoreML, MetalRT, …)
 * populates one of these. Primitives the engine does NOT serve leave the
 * corresponding op-struct pointer NULL; the registry treats NULL as "engine
 * does not support this primitive" and returns `RAC_ERROR_CAPABILITY_UNSUPPORTED`.
 *
 * ABI contract:
 *   - `metadata.abi_version` MUST equal `RAC_PLUGIN_API_VERSION` at load time.
 *     Mismatch rejects the plugin with `RAC_ERROR_ABI_VERSION_MISMATCH`.
 *   - Primitive slot pointers (llm_ops, stt_ops, …) are stable; new primitives
 *     go into one of the 10 reserved slots at the end of the struct (enforced
 *     by `RAC_PRIMITIVE_RESERVED_{9..18}` in `rac_primitive.h`).
 *   - `capability_check` is called once after ABI version validation but
 *     before the plugin is added to the registry; returning non-zero rejects
 *     the plugin without logging it as an error (e.g. for Metal-only engines
 *     on Linux).
 */

#ifndef RAC_PLUGIN_ENGINE_VTABLE_H
#define RAC_PLUGIN_ENGINE_VTABLE_H

#include <stddef.h>
#include <stdint.h>

#include "rac_error.h"
#include "rac_types.h"
#include "rac_primitive.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ===========================================================================
 * Forward declarations of existing per-domain ops structs.
 *
 * We intentionally do NOT include the per-domain headers here — those pull
 * in heavy service types (`rac_llm_options_t`, `rac_stt_config_t`, …) and
 * would force every plugin TU to compile all of them. Plugin authors include
 * the specific per-domain header for the primitive they implement.
 * =========================================================================== */

struct rac_llm_service_ops;              /* rac/features/llm/rac_llm_service.h */
struct rac_stt_service_ops;              /* rac/features/stt/rac_stt_service.h */
struct rac_tts_service_ops;              /* rac/features/tts/rac_tts_service.h */
struct rac_vad_service_ops;              /* rac/features/vad/rac_vad_service.h */
struct rac_embeddings_service_ops;       /* rac/features/embeddings/rac_embeddings_service.h */
struct rac_rerank_service_ops;           /* rac/features/rerank/rac_rerank_service.h (future) */
struct rac_vlm_service_ops;              /* rac/features/vlm/rac_vlm_service.h */
struct rac_diffusion_service_ops;        /* rac/features/diffusion/rac_diffusion_service.h */

/**
 * @brief Plugin metadata carried in every vtable.
 *
 * Layout note: bumped to ABI v2 in GAP 04 Phase 11 — the previous
 * `reserved_0/_1` (8 bytes) were promoted into the routing-extension fields
 * below. See `RAC_PLUGIN_API_VERSION` in `rac_plugin_entry.h` for the version
 * policy.
 */
typedef struct rac_engine_metadata {
    /** Must equal RAC_PLUGIN_API_VERSION. Mismatch = plugin rejected. */
    uint32_t abi_version;

    /** Stable short name (e.g. "llamacpp", "onnx", "whispercpp"). Used as
     * dedup key; registering a second plugin with the same name replaces the
     * first if-and-only-if the second's priority is >=.
     * MUST NOT be NULL. */
    const char* name;

    /** Human-readable display name for UI / logs ("llama.cpp 0.19", "ONNX
     * Runtime 1.19 CPU"). MAY be NULL. */
    const char* display_name;

    /** Semantic version string of the engine itself (not of the plugin
     * interface). MAY be NULL. */
    const char* engine_version;

    /** Priority — higher wins when multiple plugins serve the same primitive
     * for the same model. Defaults to 0 for hand-written registrations. */
    int32_t priority;

    /** Bitmask of `RAC_BACKEND_CAP_*` flags describing static engine
     * properties (supports streaming, supports LoRA, supports speculative
     * decoding, …). See rac_backend_caps.h. */
    uint64_t capability_flags;

    /* ─────── GAP 04 + T4.1 routing extension ─────── */

    /** L1 runtimes this engine can consume (CPU / Metal / CoreML / CUDA /
     *  QNN / NNAPI / WebGPU / …). MAY be NULL when the plugin doesn't care
     *  about hardware-aware routing — the router falls back to priority-only
     *  scoring. The pointer must reference plugin-owned .rodata; the
     *  registry does not copy.
     *
     *  T4.1: runtimes are now first-class
     *  plugins registered via `rac_runtime_register()`. The engine router
     *  gives plugins a small scoring bonus when at least one of their
     *  declared runtimes is *registered* in the runtime registry, on top of
     *  the existing preferred_runtime bonus. Engines that don't wire to the
     *  runtime registry (e.g. llama.cpp today, which bundles its own Metal
     *  shaders) simply continue to score off priority + hardware profile. */
    const rac_runtime_id_t* runtimes;
    size_t                  runtimes_count;

    /** Model file formats this engine accepts (proto-encoded
     *  `runanywhere.v1.ModelFormat` values cast to uint32_t). MAY be NULL.
     *  Frontends pass the proto enum value directly via `RouteRequest.format`. */
    const uint32_t*         formats;
    size_t                  formats_count;
} rac_engine_metadata_t;

/**
 * @brief Unified engine plugin vtable.
 *
 * Slot groups are stable. NULL op-struct means "does not serve this primitive".
 */
typedef struct rac_engine_vtable {
    /* ─────────── Identity + lifecycle ─────────── */
    rac_engine_metadata_t metadata;

    /**
     * Called exactly once by the registry after ABI version validation and
     * before the plugin is added to the primitive tables. Return 0 to accept,
     * non-zero (`RAC_ERROR_CAPABILITY_UNSUPPORTED`) to reject silently (no
     * error log). Useful for engines gated on runtime checks (e.g. Metal-only
     * on Linux).
     * MAY be NULL → equivalent to always returning 0.
     */
    rac_result_t (*capability_check)(void);

    /**
     * Called by the registry on unload. Engines with background threads
     * should join them here. MAY be NULL.
     */
    void (*on_unload)(void);

    /* ─────────── Primitive slot groups (8 active) ─────────── */

    /** LLM text generation (`RAC_PRIMITIVE_GENERATE_TEXT`). */
    const struct rac_llm_service_ops*       llm_ops;

    /** Speech-to-Text (`RAC_PRIMITIVE_TRANSCRIBE`). */
    const struct rac_stt_service_ops*       stt_ops;

    /** Text-to-Speech (`RAC_PRIMITIVE_SYNTHESIZE`). */
    const struct rac_tts_service_ops*       tts_ops;

    /** Voice Activity Detection (`RAC_PRIMITIVE_DETECT_VOICE`). */
    const struct rac_vad_service_ops*       vad_ops;

    /** Text / multimodal embeddings (`RAC_PRIMITIVE_EMBED`). */
    const struct rac_embeddings_service_ops* embedding_ops;

    /** Cross-encoder reranking (`RAC_PRIMITIVE_RERANK`). */
    const struct rac_rerank_service_ops*    rerank_ops;

    /** Vision-Language Model (`RAC_PRIMITIVE_VLM`). */
    const struct rac_vlm_service_ops*       vlm_ops;

    /** Diffusion / image generation (`RAC_PRIMITIVE_DIFFUSION`). */
    const struct rac_diffusion_service_ops* diffusion_ops;

    /* ─────────── Reserved slot pool (10 slots) ─────────── */
    /*
     * Keeps the struct layout binary-stable as new primitives land. Each
     * reserved slot is a `const void*` so the compiler can fill with NULL
     * without forcing plugin authors to type-cast. Promoting a reserved slot
     * to a real primitive requires:
     *   1. Changing its type to the new `const struct rac_<name>_service_ops*`.
     *   2. Renaming its field.
     *   3. Bumping RAC_PLUGIN_API_VERSION.
     * Old binaries will fail ABI version check and be rejected safely.
     */
    const void* reserved_slot_0;
    const void* reserved_slot_1;
    const void* reserved_slot_2;
    const void* reserved_slot_3;
    const void* reserved_slot_4;
    const void* reserved_slot_5;
    const void* reserved_slot_6;
    const void* reserved_slot_7;
    const void* reserved_slot_8;
    const void* reserved_slot_9;
} rac_engine_vtable_t;

/**
 * Lookup the per-primitive ops pointer inside a vtable at runtime, keyed by
 * `rac_primitive_t`. Returns NULL for primitives the engine does not serve,
 * or for primitives outside the 1..8 range. The returned pointer must be
 * cast to the primitive's per-domain ops struct type.
 */
const void* rac_engine_vtable_slot(const rac_engine_vtable_t* vt,
                                   rac_primitive_t primitive);

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_ENGINE_VTABLE_H */
