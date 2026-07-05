/**
 * @file rac_runtime_vtable.h
 * @brief L1 Runtime plugin vtable — compute-runtime ABI.
 *
 * Task T4.1.
 *
 * A "runtime" is the compute target an engine executes on: CPU, Apple Metal,
 * Core ML, NVIDIA CUDA, Vulkan, QNN, NNAPI, WebGPU, … Engines (llama.cpp,
 * ONNX Runtime, sherpa, MetalRT, …) are *clients* of
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
 *
 * ABI v2 providers expose a `rac_runtime_vtable_v2_t` extension through
 * `rac_runtime_vtable_t::reserved_slot_0`. The v1-shaped op slots
 * (`run_session`, `alloc_buffer`, …) remain in the struct layout for
 * binary stability, but the registry now accepts ABI v2 only — v1-only
 * plugins (i.e. plugins that omit the `reserved_slot_0` v2 extension) are
 * hard-rejected with `RAC_ERROR_ABI_VERSION_MISMATCH`.
 */

#ifndef RAC_PLUGIN_RUNTIME_VTABLE_H
#define RAC_PLUGIN_RUNTIME_VTABLE_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/plugin/rac_model_format_ids.h"
#include "rac/plugin/rac_primitive.h" /* rac_runtime_id_t */

// NOLINTBEGIN(modernize-redundant-void-arg,modernize-use-nullptr)
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
 *   2u — CPP-RUNTIME-01 v2 extension via reserved_slot_0.
 */
#define RAC_RUNTIME_ABI_VERSION_V1 1u
#define RAC_RUNTIME_ABI_VERSION_V2 2u
#define RAC_RUNTIME_ABI_VERSION RAC_RUNTIME_ABI_VERSION_V2
/**
 * Lowest ABI version the registry will accept. Today MIN == current —
 * `rac_runtime_register` requires exact equality with `RAC_RUNTIME_ABI_VERSION`
 * and rejects v1-only plugins (no `reserved_slot_0` extension) with
 * `RAC_ERROR_ABI_VERSION_MISMATCH`. The macro is kept distinct so a future
 * release that adds a true compatibility shim can widen the accepted range
 * (e.g. `[MIN, RAC_RUNTIME_ABI_VERSION]`) without renaming the constant the
 * registry already logs in mismatch diagnostics.
 */
#define RAC_RUNTIME_ABI_VERSION_MIN RAC_RUNTIME_ABI_VERSION_V2

/* ===========================================================================
 * Device + capability descriptors (by-value POD, safe to include-only).
 * =========================================================================== */

/** Coarse device class the runtime targets. Mirrors `rac_runtime_id_t` but
 *  kept separate so a runtime can target multiple device classes (CoreML
 *  picks GPU/ANE/CPU at model-load time). */
typedef enum rac_device_class {
    RAC_DEVICE_CLASS_UNSPECIFIED = 0,
    RAC_DEVICE_CLASS_CPU = 1,
    RAC_DEVICE_CLASS_GPU = 2,
    RAC_DEVICE_CLASS_NPU = 3, /**< ANE, QNN HTP, NNAPI accelerator, … */
    RAC_DEVICE_CLASS_WEB_GPU = 4,
} rac_device_class_t;

/** Information returned by `rac_runtime_vtable_t::device_info`. */
typedef struct rac_runtime_device_info {
    rac_device_class_t device_class;
    /** Short device identifier ("apple-m3", "nvidia-rtx-4090", "adreno-740",
     *  "cpu-generic"). Points into plugin-owned .rodata; lifetime == runtime. */
    const char* device_id;
    /** Human-readable display name. MAY be NULL. */
    const char* display_name;
    /** Reported memory bytes for the device. 0 = unknown. */
    uint64_t memory_bytes;
    /** Reserved for future expansion (e.g. compute-unit count). */
    uint64_t reserved_0;
    uint64_t reserved_1;
} rac_runtime_device_info_t;

/** Capabilities returned by `rac_runtime_vtable_t::capabilities`. */
typedef struct rac_runtime_capabilities {
    /** Bitmask of `RAC_RUNTIME_CAP_*` flags. */
    uint64_t capability_flags;
    /** Supported model formats (`RAC_MODEL_FORMAT_ID_*` values mirroring
     *  proto `runanywhere.v1.ModelFormat`).
     *  Points into plugin-owned .rodata. MAY be NULL. */
    const uint32_t* supported_formats;
    size_t supported_formats_count;
    /** Supported primitives. MAY be NULL → runtime doesn't care. */
    const rac_primitive_t* supported_primitives;
    size_t supported_primitives_count;
} rac_runtime_capabilities_t;

/** Capability-flag bits — extend additively, do NOT reorder. */
#define RAC_RUNTIME_CAP_QUANTIZED_INT8 (1ull << 0)
#define RAC_RUNTIME_CAP_QUANTIZED_INT4 (1ull << 1)
#define RAC_RUNTIME_CAP_FP16 (1ull << 2)
#define RAC_RUNTIME_CAP_BF16 (1ull << 3)
#define RAC_RUNTIME_CAP_DYNAMIC_SHAPES (1ull << 4)
#define RAC_RUNTIME_CAP_ZERO_COPY (1ull << 5)
#define RAC_RUNTIME_CAP_BUFFER_MAPPING (1ull << 6)
#define RAC_RUNTIME_CAP_BUFFER_COPY (1ull << 7)
#define RAC_RUNTIME_CAP_DEVICE_ALLOC (1ull << 8)
#define RAC_RUNTIME_CAP_OWNED_OUTPUTS (1ull << 9)
/** The runtime provides the OPTIONAL session-execution role: it implements
 *  `create_session` / `run_session` / `destroy_session` (+ buffer ops) and can
 *  actually run inference, not merely describe hardware. Runtimes that fill
 *  those vtable slots MUST set this bit in `capabilities()`; capability-only
 *  runtimes (which leave the session slots NULL) MUST NOT. The engine router
 *  uses this flag to tell "can this runtime host a session?" apart from "this
 *  runtime exists and reports device_info/capabilities". See the two-role note
 *  on `rac_runtime_vtable` below. */
#define RAC_RUNTIME_CAP_SESSION_EXECUTION (1ull << 10)

/* ===========================================================================
 * Opaque session + buffer handles.
 *
 * Runtimes define the concrete struct privately; callers pass the pointer
 * back unchanged through run_session / destroy_session.
 * =========================================================================== */

typedef struct rac_runtime_session rac_runtime_session_t;
typedef struct rac_runtime_buffer rac_runtime_buffer_t;

/* ===========================================================================
 * ABI v2 tensor and buffer descriptors.
 *
 * These types are runtime-only: generic tensor execution, buffer ownership,
 * device memory selection, and buffer transfer. Platform services such as OS
 * permissions, file pickers, HTTP, secure storage, battery/thermal, and app
 * lifecycle APIs intentionally do not belong here.
 * =========================================================================== */

/** Stable tensor element type. Values 0-16 intentionally match ONNX tensor
 *  element enum values where there is overlap, preserving existing Float32=1
 *  and Int64=7 users of `rac_runtime_io_t::dtype`. */
typedef enum rac_runtime_dtype {
    RAC_RUNTIME_DTYPE_UNDEFINED = 0,
    RAC_RUNTIME_DTYPE_F32 = 1,
    RAC_RUNTIME_DTYPE_U8 = 2,
    RAC_RUNTIME_DTYPE_I8 = 3,
    RAC_RUNTIME_DTYPE_U16 = 4,
    RAC_RUNTIME_DTYPE_I16 = 5,
    RAC_RUNTIME_DTYPE_I32 = 6,
    RAC_RUNTIME_DTYPE_I64 = 7,
    RAC_RUNTIME_DTYPE_STRING = 8,
    RAC_RUNTIME_DTYPE_BOOL = 9,
    RAC_RUNTIME_DTYPE_F16 = 10,
    RAC_RUNTIME_DTYPE_F64 = 11,
    RAC_RUNTIME_DTYPE_U32 = 12,
    RAC_RUNTIME_DTYPE_U64 = 13,
    RAC_RUNTIME_DTYPE_BF16 = 16,
    RAC_RUNTIME_DTYPE_U4 = 21,
    RAC_RUNTIME_DTYPE_I4 = 22,
} rac_runtime_dtype_t;

/** Memory space for tensor data and runtime buffers. */
typedef enum rac_runtime_memory_space {
    RAC_RUNTIME_MEMORY_SPACE_UNSPECIFIED = 0,
    RAC_RUNTIME_MEMORY_SPACE_HOST = 1,
    RAC_RUNTIME_MEMORY_SPACE_HOST_PINNED = 2,
    RAC_RUNTIME_MEMORY_SPACE_DEVICE = 3,
    RAC_RUNTIME_MEMORY_SPACE_SHARED = 4,
    RAC_RUNTIME_MEMORY_SPACE_MANAGED = 5,
} rac_runtime_memory_space_t;

/** Ownership contract for tensor fields returned by v2 execution. */
typedef enum rac_runtime_ownership {
    RAC_RUNTIME_OWNERSHIP_NONE = 0,
    RAC_RUNTIME_OWNERSHIP_CALLER = 1,
    RAC_RUNTIME_OWNERSHIP_RUNTIME = 2,
    RAC_RUNTIME_OWNERSHIP_EXTERNAL = 3,
} rac_runtime_ownership_t;

/** Buffer usage hints. Runtimes MAY ignore hints they do not understand. */
#define RAC_RUNTIME_BUFFER_USAGE_INPUT (1ull << 0)
#define RAC_RUNTIME_BUFFER_USAGE_OUTPUT (1ull << 1)
#define RAC_RUNTIME_BUFFER_USAGE_TEMPORARY (1ull << 2)
#define RAC_RUNTIME_BUFFER_USAGE_CONSTANT (1ull << 3)
#define RAC_RUNTIME_BUFFER_USAGE_MAP_READ (1ull << 4)
#define RAC_RUNTIME_BUFFER_USAGE_MAP_WRITE (1ull << 5)

/** Map access flags. */
#define RAC_RUNTIME_MAP_READ (1u << 0)
#define RAC_RUNTIME_MAP_WRITE (1u << 1)
#define RAC_RUNTIME_MAP_DISCARD_WRITE (1u << 2)

/** Device-aware allocation request for v2 `alloc_buffer`. */
typedef struct rac_runtime_buffer_desc {
    size_t bytes;
    rac_runtime_memory_space_t memory_space;
    rac_device_class_t device_class;
    /** Runtime-specific device ordinal. 0 means the default device. */
    uint32_t device_index;
    /** Requested byte alignment. 0 means runtime default. */
    uint32_t alignment;
    /** Bitmask of `RAC_RUNTIME_BUFFER_USAGE_*`. */
    uint64_t usage_flags;
    /** Optional stable device id matching `rac_runtime_device_info_t`. */
    const char* device_id;
    uint64_t reserved_0;
    uint64_t reserved_1;
} rac_runtime_buffer_desc_t;

/** Runtime-owned buffer metadata returned by v2 `buffer_info`. */
typedef struct rac_runtime_buffer_info {
    size_t bytes;
    rac_runtime_memory_space_t memory_space;
    rac_device_class_t device_class;
    uint32_t device_index;
    uint32_t alignment;
    uint64_t usage_flags;
    const char* device_id;
    /** Optional native handle (`MTLBuffer*`, CUDA pointer, etc.). MAY be NULL. */
    void* native_handle;
    uint64_t reserved_0;
    uint64_t reserved_1;
} rac_runtime_buffer_info_t;

/** Host mapping returned by v2 `map_buffer`. */
typedef struct rac_runtime_buffer_mapping {
    void* data;
    size_t bytes;
    rac_runtime_memory_space_t memory_space;
    uint32_t map_flags;
    uint32_t reserved_0;
    uint64_t reserved_1;
    uint64_t reserved_2;
} rac_runtime_buffer_mapping_t;

/** ABI v2 tensor descriptor used by `run_session_v2`. Inputs borrow all
 *  fields from the caller. Outputs may either use caller-supplied `data` and
 *  `shape` storage (`*_capacity` non-zero) or return runtime-owned data,
 *  shape, and/or buffer handles; callers release runtime-owned fields through
 *  `rac_runtime_vtable_v2_t::release_tensor`. */
typedef struct rac_runtime_tensor {
    const char* name;
    rac_runtime_buffer_t* buffer;
    void* data;
    size_t data_bytes;
    size_t data_capacity_bytes;
    rac_runtime_dtype_t dtype;
    rac_runtime_memory_space_t memory_space;
    int64_t* shape;
    size_t rank;
    size_t shape_capacity;
    rac_runtime_ownership_t buffer_ownership;
    rac_runtime_ownership_t data_ownership;
    rac_runtime_ownership_t shape_ownership;
    uint32_t reserved_0;
    void* user_data;
    uint64_t reserved_1;
    uint64_t reserved_2;
} rac_runtime_tensor_t;

/**
 * @brief ABI v2 extension. A v2 provider sets
 *        `rac_runtime_vtable_t::reserved_slot_0` to this struct.
 *
 * `abi_version` MUST be `RAC_RUNTIME_ABI_VERSION_V2`; `struct_size` MUST be at
 * least `RAC_RUNTIME_VTABLE_V2_MIN_SIZE`. All op slots are optional and are
 * probed independently.
 */
typedef struct rac_runtime_vtable_v2 {
    uint32_t abi_version;
    uint32_t struct_size;

    rac_result_t (*run_session_v2)(rac_runtime_session_t* session,
                                   const rac_runtime_tensor_t* inputs, size_t n_in,
                                   rac_runtime_tensor_t* outputs, size_t n_out);

    rac_result_t (*alloc_buffer)(const rac_runtime_buffer_desc_t* desc, rac_runtime_buffer_t** out);
    rac_result_t (*buffer_info)(rac_runtime_buffer_t* buffer, rac_runtime_buffer_info_t* out);
    rac_result_t (*map_buffer)(rac_runtime_buffer_t* buffer, size_t offset, size_t bytes,
                               uint32_t map_flags, rac_runtime_buffer_mapping_t* out);
    rac_result_t (*unmap_buffer)(rac_runtime_buffer_t* buffer,
                                 rac_runtime_buffer_mapping_t* mapping);
    rac_result_t (*copy_buffer)(rac_runtime_buffer_t* dst, size_t dst_offset,
                                const rac_runtime_buffer_t* src, size_t src_offset, size_t bytes);

    void (*release_tensor)(rac_runtime_tensor_t* tensor);

    const void* reserved_0;
    const void* reserved_1;
    const void* reserved_2;
    const void* reserved_3;
    const void* reserved_4;
    const void* reserved_5;
    const void* reserved_6;
    const void* reserved_7;
} rac_runtime_vtable_v2_t;

#define RAC_RUNTIME_VTABLE_V2_MIN_SIZE ((uint32_t)offsetof(rac_runtime_vtable_v2_t, reserved_0))

/**
 * @brief Initializer for the v2 extension table of a capability-only runtime.
 *
 * Capability-only runtimes (Core ML, Metal) host no session and allocate no
 * device buffers, so every v2 op slot is NULL — only the ABI header is
 * populated. They still ship a v2 table on `reserved_slot_0` so the registry's
 * v2 probe succeeds; a runtime that offers no session role at all may instead
 * leave `reserved_slot_0` NULL (as onnxrt does). Use this to avoid hand-copying
 * the all-NULL body:
 *
 *     const rac_runtime_vtable_v2_t k_coreml_vtable_v2 =
 *         RAC_RUNTIME_VTABLE_V2_CAPABILITY_ONLY;
 */
#define RAC_RUNTIME_VTABLE_V2_CAPABILITY_ONLY                    \
    {                                                            \
        /* .abi_version    = */ RAC_RUNTIME_ABI_VERSION_V2,      \
        /* .struct_size    = */ sizeof(rac_runtime_vtable_v2_t), \
        /* .run_session_v2 = */ NULL,                            \
        /* .alloc_buffer   = */ NULL,                            \
        /* .buffer_info    = */ NULL,                            \
        /* .map_buffer     = */ NULL,                            \
        /* .unmap_buffer   = */ NULL,                            \
        /* .copy_buffer    = */ NULL,                            \
        /* .release_tensor = */ NULL,                            \
        /* .reserved_0     = */ NULL,                            \
        /* .reserved_1     = */ NULL,                            \
        /* .reserved_2     = */ NULL,                            \
        /* .reserved_3     = */ NULL,                            \
        /* .reserved_4     = */ NULL,                            \
        /* .reserved_5     = */ NULL,                            \
        /* .reserved_6     = */ NULL,                            \
        /* .reserved_7     = */ NULL,                            \
    }

/** Parameters for `create_session`. Stable by-value POD. */
typedef struct rac_runtime_session_desc {
    /** Which service primitive the session serves (llm, stt, …). */
    rac_primitive_t primitive;
    /** `RAC_MODEL_FORMAT_ID_*` / `runanywhere.v1.ModelFormat` value, or 0 when unspecified. */
    uint32_t model_format;
    /** Absolute path to a model file on disk. NULL when model is in memory. */
    const char* model_path;
    /** In-memory model blob; used only when `model_path == NULL`. */
    const void* model_blob;
    size_t model_blob_bytes;
    /** Runtime-specific options, JSON-encoded. NULL → runtime defaults. */
    const char* options_json;
} rac_runtime_session_desc_t;

/** A single input/output tensor for `run_session`. */
typedef struct rac_runtime_io {
    /** Tensor name as expected by the loaded model. */
    const char* name;
    /** Packed host-side buffer. Ownership stays with the caller; the runtime
     *  MAY copy into a device buffer internally. */
    void* data;
    size_t data_bytes;
    /** `rac_runtime_dtype_t`; 0 → runtime-defined/unspecified. */
    uint32_t dtype;
    /** Shape, NULL-terminated-NOT; pair with `rank`. */
    const int64_t* shape;
    size_t rank;
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

    /** Supported `RAC_MODEL_FORMAT_ID_*` / `runanywhere.v1.ModelFormat` values. MAY be NULL. */
    const uint32_t* supported_formats;
    size_t supported_formats_count;

    /** Supported device classes. MAY be NULL. */
    const rac_device_class_t* supported_devices;
    size_t supported_devices_count;

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
 *
 * A runtime fills two distinct roles:
 *
 *   1. Capability role (MANDATORY): identity (`metadata`) + `init` + `destroy`
 *      + `device_info` + `capabilities`. Every runtime MUST implement these so
 *      the engine router can do hardware-aware selection. A "capability-only"
 *      runtime stops here and leaves the session-execution slots NULL.
 *
 *   2. Session-execution role (OPTIONAL): `create_session` / `run_session` /
 *      `destroy_session` plus the buffer ops (`alloc_buffer`, `free_buffer`,
 *      and the v2 buffer extension). A runtime that actually runs inference
 *      fills these slots AND advertises `RAC_RUNTIME_CAP_SESSION_EXECUTION` in
 *      its `capabilities()`. Today only the built-in CPU runtime does this;
 *      Metal / Core ML / ONNX Runtime are capability-only and leave the
 *      session slots NULL. Session execution is all-or-nothing: a runtime that
 *      provides `create_session` MUST also provide `run_session` and
 *      `destroy_session`.
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
    rac_result_t (*run_session)(rac_runtime_session_t* session, const rac_runtime_io_t* inputs,
                                size_t n_in, rac_runtime_io_t* outputs, size_t n_out);

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
     * Keeps layout binary-stable as new runtime ops land. ABI v2 uses
     * reserved_slot_0 as `const rac_runtime_vtable_v2_t*`.
     */
    const void* reserved_slot_0;
    const void* reserved_slot_1;
    const void* reserved_slot_2;
    const void* reserved_slot_3;
    const void* reserved_slot_4;
    const void* reserved_slot_5;
} rac_runtime_vtable_t;

static inline const rac_runtime_vtable_v2_t*
rac_runtime_vtable_get_v2(const rac_runtime_vtable_t* vtable) {
    if (vtable == NULL || vtable->metadata.abi_version < RAC_RUNTIME_ABI_VERSION_V2 ||
        vtable->reserved_slot_0 == NULL) {
        return NULL;
    }
    const rac_runtime_vtable_v2_t* v2 = (const rac_runtime_vtable_v2_t*)vtable->reserved_slot_0;
    if (v2->abi_version != RAC_RUNTIME_ABI_VERSION_V2 ||
        v2->struct_size < RAC_RUNTIME_VTABLE_V2_MIN_SIZE) {
        return NULL;
    }
    return v2;
}

/* ===========================================================================
 * Dynamic-loader symbol convention (parallel to rac_plugin_entry_<name>).
 * =========================================================================== */

typedef const rac_runtime_vtable_t* (*rac_runtime_entry_fn)(void);

/**
 * @brief Declare a runtime entry point in a public header.
 *
 * The entry symbol is annotated with `RAC_API` (= default ELF/Mach-O
 * visibility, dllexport on Windows) for parity with `RAC_PLUGIN_ENTRY_DECL`.
 * `rac_runtime_load` → `dlsym(handle, "rac_runtime_entry_<name>")` MUST be
 * able to find this symbol regardless of how the host runtime library was
 * linked — notably, even when a SHARED carrier sets visibility=hidden
 * globally and the real definition lives in a sibling static archive.
 * Without an explicit annotation at declaration time, loadability depends
 * on transitive default visibility of the host runtime target — a brittle
 * invariant that a future visibility tightening would silently break
 * (mirrors the engine-plugin entry declaration).
 */
#define RAC_RUNTIME_ENTRY_DECL(name) \
    RAC_API const rac_runtime_vtable_t* rac_runtime_entry_##name(void)

#define RAC_RUNTIME_ENTRY_DEF(name) RAC_RUNTIME_ENTRY_DECL(name)

#ifdef __cplusplus
}
#endif
// NOLINTEND(modernize-redundant-void-arg,modernize-use-nullptr)

#endif /* RAC_PLUGIN_RUNTIME_VTABLE_H */
