/**
 * @file rac_runtime_vtable.h
 * @brief L1 Runtime plugin vtable — compute-runtime ABI.
 *
 * Task T4.1.
 *
 * A "runtime" is the compute target an engine executes on: CPU, Apple Metal,
 * Core ML, NVIDIA CUDA, Vulkan, QNN, NNAPI, WebGPU, … Engines (llama.cpp,
 * ONNX Runtime, whispercpp, WhisperKit CoreML, MetalRT, …) are *clients* of
 * one or more runtimes. Promoting runtimes to first-class plugins lets
 * multiple engines share a single ORT `Ort::Env`, reuse the same CoreML
 * `MLModel` loader, and allocate GPU buffers through one allocator per
 * runtime instead of one per engine.
 *
 * This header is the ABI boundary. Runtime plugins populate a
 * `rac_runtime_vtable_t` whose storage lives in their `.rodata`, then call
 * `rac_runtime_register(vtable)` from `rac_runtime_registry.h` at load time
 * (statically via `RAC_STATIC_RUNTIME_REGISTER` or dynamically via the
 * loader, identical to the engine-plugin mechanism).
 */

#ifndef RAC_PLUGIN_RUNTIME_VTABLE_H
#define RAC_PLUGIN_RUNTIME_VTABLE_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/plugin/rac_primitive.h"   /* rac_runtime_id_t */

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Runtime ABI version.
 *
 * Independent of `RAC_PLUGIN_API_VERSION`. Bump when:
 *   - A non-reserved field is added to or removed from `rac_runtime_metadata_t`.
 *   - An op-slot is added to, removed from, or repurposed inside
 *     `rac_runtime_vtable_t` (reserved-slot promotions count as a bump).
 *   - Any struct passed through the vtable (`rac_runtime_session_desc_t`,
 *     `rac_runtime_io_t`, …) changes layout.
 *
 * Do NOT bump for additive capability flags or new `rac_runtime_id_t` values
 * — those are handled by `metadata.capability_flags` and the reserved slots
 * inside `rac_runtime_id_t`.
 *
 * Version history:
 *   1u — T4.1 initial release.
 */
#define RAC_RUNTIME_ABI_VERSION 1u

/* ===========================================================================
 * Device + capability descriptors (by-value POD, safe to include-only).
 * =========================================================================== */

/** Coarse device class the runtime targets. Mirrors `rac_runtime_id_t` but
 *  kept separate so a runtime can target multiple device classes (CoreML
 *  picks GPU/ANE/CPU at model-load time). */
typedef enum rac_device_class {
    RAC_DEVICE_CLASS_UNSPECIFIED = 0,
    RAC_DEVICE_CLASS_CPU         = 1,
    RAC_DEVICE_CLASS_GPU         = 2,
    RAC_DEVICE_CLASS_NPU         = 3,   /**< ANE, QNN HTP, NNAPI accelerator, … */
    RAC_DEVICE_CLASS_WEB_GPU     = 4,
} rac_device_class_t;

/** Information returned by `rac_runtime_vtable_t::device_info`. */
typedef struct rac_runtime_device_info {
    rac_device_class_t device_class;
    /** Short device identifier ("apple-m3", "nvidia-rtx-4090", "adreno-740",
     *  "cpu-generic"). Points into plugin-owned .rodata; lifetime == runtime. */
    const char*        device_id;
    /** Human-readable display name. MAY be NULL. */
    const char*        display_name;
    /** Reported memory bytes for the device. 0 = unknown. */
    uint64_t           memory_bytes;
    /** Reserved for future expansion (e.g. compute-unit count). */
    uint64_t           reserved_0;
    uint64_t           reserved_1;
} rac_runtime_device_info_t;

/** Capabilities returned by `rac_runtime_vtable_t::capabilities`. */
typedef struct rac_runtime_capabilities {
    /** Bitmask of `RAC_RUNTIME_CAP_*` flags. */
    uint64_t        capability_flags;
    /** Supported model formats (proto `runanywhere.v1.ModelFormat` values).
     *  Points into plugin-owned .rodata. MAY be NULL. */
    const uint32_t* supported_formats;
    size_t          supported_formats_count;
    /** Supported primitives. MAY be NULL → runtime doesn't care. */
    const rac_primitive_t* supported_primitives;
    size_t                 supported_primitives_count;
} rac_runtime_capabilities_t;

/** Capability-flag bits — extend additively, do NOT reorder. */
#define RAC_RUNTIME_CAP_QUANTIZED_INT8   (1ull << 0)
#define RAC_RUNTIME_CAP_QUANTIZED_INT4   (1ull << 1)
#define RAC_RUNTIME_CAP_FP16             (1ull << 2)
#define RAC_RUNTIME_CAP_BF16             (1ull << 3)
#define RAC_RUNTIME_CAP_DYNAMIC_SHAPES   (1ull << 4)
#define RAC_RUNTIME_CAP_ZERO_COPY        (1ull << 5)

/* ===========================================================================
 * Opaque session + buffer handles.
 *
 * Runtimes define the concrete struct privately; callers pass the pointer
 * back unchanged through run_session / destroy_session.
 * =========================================================================== */

typedef struct rac_runtime_session rac_runtime_session_t;
typedef struct rac_runtime_buffer  rac_runtime_buffer_t;

/** Parameters for `create_session`. Stable by-value POD. */
typedef struct rac_runtime_session_desc {
    /** Which service primitive the session serves (llm, stt, …). */
    rac_primitive_t primitive;
    /** `runanywhere.v1.ModelFormat` enum value, or 0 when unspecified. */
    uint32_t        model_format;
    /** Absolute path to a model file on disk. NULL when model is in memory. */
    const char*     model_path;
    /** In-memory model blob; used only when `model_path == NULL`. */
    const void*     model_blob;
    size_t          model_blob_bytes;
    /** Runtime-specific options, JSON-encoded. NULL → runtime defaults. */
    const char*     options_json;
} rac_runtime_session_desc_t;

/** A single input/output tensor for `run_session`. */
typedef struct rac_runtime_io {
    /** Tensor name as expected by the loaded model. */
    const char* name;
    /** Packed host-side buffer. Ownership stays with the caller; the runtime
     *  MAY copy into a device buffer internally. */
    void*       data;
    size_t      data_bytes;
    /** Element-type enum reserved for future use (0 → runtime-defined). */
    uint32_t    dtype;
    /** Shape, NULL-terminated-NOT; pair with `rank`. */
    const int64_t* shape;
    size_t         rank;
} rac_runtime_io_t;

/* ===========================================================================
 * Metadata + vtable layout.
 * =========================================================================== */

/**
 * @brief Runtime plugin metadata — carried in every vtable.
 *
 * Every field is lifetime-stable: strings and arrays MUST live as long as
 * the runtime is registered (typically .rodata of the plugin library). The
 * registry does NOT copy.
 */
typedef struct rac_runtime_metadata {
    /** Must equal `RAC_RUNTIME_ABI_VERSION` at register time. Mismatch →
     *  `RAC_ERROR_ABI_VERSION_MISMATCH`. */
    uint32_t abi_version;

    /** Canonical runtime identifier (CPU / METAL / COREML / CUDA / …).
     *  Used as dedup key; see `rac_runtime_register` for replacement rules. */
    rac_runtime_id_t id;

    /** Stable short name ("cpu", "metal", "onnxrt", "coreml", "cuda"). Used
     *  for logging + the `dlopen` loader's symbol convention
     *  `rac_runtime_entry_<name>`. MUST NOT be NULL. */
    const char* name;

    /** Human-readable display name for UI / logs ("Core ML 6.0",
     *  "NVIDIA CUDA 12.3"). MAY be NULL. */
    const char* display_name;

    /** Semantic version string of the underlying runtime library
     *  (e.g. "1.19.0" for ONNX Runtime). MAY be NULL. */
    const char* version;

    /** Priority — higher wins when two plugins register the same id. */
    int32_t priority;

    /** Supported `runanywhere.v1.ModelFormat` values. MAY be NULL. */
    const uint32_t* supported_formats;
    size_t          supported_formats_count;

    /** Supported device classes. MAY be NULL. */
    const rac_device_class_t* supported_devices;
    size_t                    supported_devices_count;

    /** Reserved for future metadata; must be zero. */
    uint64_t reserved_0;
    uint64_t reserved_1;
} rac_runtime_metadata_t;

/**
 * @brief L1 runtime vtable.
 *
 * Op slots are stable. A NULL pointer means the runtime does not implement
 * that op — callers probe before dispatch and fall back to engine-owned
 * behaviour. `init`/`destroy` MUST be non-NULL.
 */
typedef struct rac_runtime_vtable {
    rac_runtime_metadata_t metadata;

    /** Called exactly once by the registry on accept, before any other op.
     *  Return 0 to accept; non-zero silently rejects (e.g. Metal on Linux).
     *  MUST NOT be NULL. */
    rac_result_t (*init)(void);

    /** Called by the registry on `rac_runtime_unregister`. MUST NOT be NULL
     *  — pass a no-op if nothing to tear down. */
    void (*destroy)(void);

    /** Create a session bound to a model. MAY be NULL if the runtime only
     *  advertises metadata (see CPU default runtime). */
    rac_result_t (*create_session)(const rac_runtime_session_desc_t* desc,
                                   rac_runtime_session_t** out);

    /** Run a previously-created session. MAY be NULL when `create_session`
     *  is NULL. */
    rac_result_t (*run_session)(rac_runtime_session_t* session,
                                const rac_runtime_io_t* inputs,  size_t n_in,
                                      rac_runtime_io_t* outputs, size_t n_out);

    /** Destroy a session. MAY be NULL when `create_session` is NULL;
     *  otherwise MUST be non-NULL. */
    void (*destroy_session)(rac_runtime_session_t* session);

    /** Allocate a runtime-managed buffer of `bytes`. MAY be NULL → caller
     *  uses host `malloc` and passes the pointer through `rac_runtime_io_t`. */
    rac_result_t (*alloc_buffer)(size_t bytes, rac_runtime_buffer_t** out);

    /** Free a buffer returned by `alloc_buffer`. Paired; MAY be NULL only
     *  when `alloc_buffer` is NULL. */
    void (*free_buffer)(rac_runtime_buffer_t* buffer);

    /** Fill an info struct describing the first device the runtime reports.
     *  MAY be NULL → caller treats as "CPU-generic". */
    rac_result_t (*device_info)(rac_runtime_device_info_t* out);

    /** Fill a capabilities struct. MAY be NULL → `metadata.supported_formats`
     *  is the authoritative answer. */
    rac_result_t (*capabilities)(rac_runtime_capabilities_t* out);

    /* ─────────── Reserved slot pool (6 slots) ─────────── */
    /*
     * Keeps layout binary-stable as new runtime ops land. Promoting a
     * reserved slot bumps RAC_RUNTIME_ABI_VERSION.
     */
    const void* reserved_slot_0;
    const void* reserved_slot_1;
    const void* reserved_slot_2;
    const void* reserved_slot_3;
    const void* reserved_slot_4;
    const void* reserved_slot_5;
} rac_runtime_vtable_t;

/* ===========================================================================
 * Dynamic-loader symbol convention (parallel to rac_plugin_entry_<name>).
 * =========================================================================== */

typedef const rac_runtime_vtable_t* (*rac_runtime_entry_fn)(void);

#define RAC_RUNTIME_ENTRY_DECL(name) \
    const rac_runtime_vtable_t* rac_runtime_entry_##name(void)

#define RAC_RUNTIME_ENTRY_DEF(name) \
    RAC_RUNTIME_ENTRY_DECL(name)

#ifdef __cplusplus
}
#endif

#endif /* RAC_PLUGIN_RUNTIME_VTABLE_H */
