/**
 * @file rac_hardware.h
 * @brief RunAnywhere Commons - Hardware capability detection
 *
 * Public C API for querying which inference accelerators are available at
 * runtime on the current device. Used by backend selection logic and by
 * SDK consumers that want to surface device-aware UI (e.g. "GPU acceleration
 * enabled").
 *
 * Detection is compile-time-honest: features gated by a build flag are
 * reported absent on binaries that don't include them, even if the hardware
 * itself is present. For example, an arm64 iOS build without
 * -DGGML_USE_METAL will report has_metal = RAC_FALSE.
 *
 * Thread safety:
 *   rac_hardware_query_capabilities() is safe to call from any thread.
 *   Results are cached inside rac_commons after the first call; repeated
 *   calls are cheap (one atomic load).
 */

#ifndef RAC_HARDWARE_H
#define RAC_HARDWARE_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Snapshot of detected hardware + accelerator capabilities.
 *
 * Every field carries a rac_bool_t (not std::optional) so C consumers can
 * use the struct directly. Numeric fields like total_gpu_memory_mb are 0
 * when unknown or inapplicable.
 *
 * ABI-stable: this struct has a leading `version` field and a trailing
 * reserved block so new capabilities can be added without breaking
 * existing C consumers. Current schema version is RAC_HARDWARE_REPORT_V1.
 */
typedef struct rac_hardware_report {
    /** Must equal RAC_HARDWARE_REPORT_V1. Checked at every query. */
    uint32_t version;

    /* -- CPU SIMD ---------------------------------------------------- */
    rac_bool_t has_neon;       /* ARM NEON (Android arm64, iOS arm64, Apple Silicon) */
    rac_bool_t has_sse42;      /* Intel SSE4.2 */
    rac_bool_t has_avx;        /* Intel AVX */
    rac_bool_t has_avx2;       /* Intel AVX2 */
    rac_bool_t has_avx512;     /* Intel AVX-512 family */
    int32_t    num_logical_cpus;
    int32_t    num_physical_cpus;

    /* -- GPU --------------------------------------------------------- */
    rac_bool_t has_metal;      /* Apple Metal available AND commons built with it */
    rac_bool_t has_cuda;       /* NVIDIA CUDA */
    rac_bool_t has_vulkan;     /* Vulkan (Linux/Android/Windows) */
    rac_bool_t has_opencl;     /* OpenCL (Android Adreno etc.) */
    rac_bool_t has_webgpu;     /* WebGPU (WASM/Emscripten builds) */
    int64_t    total_gpu_memory_mb;  /* 0 if unknown */

    /* -- NPU / Neural accelerator ------------------------------------ */
    rac_bool_t has_ane;        /* Apple Neural Engine (via Core ML) */
    rac_bool_t has_qnn;        /* Qualcomm Hexagon via QNN SDK */
    rac_bool_t has_genio;      /* MediaTek Genio NPU */

    /* -- OS / platform info ------------------------------------------ */
    rac_bool_t is_apple_silicon;
    rac_bool_t is_ios_simulator;
    rac_bool_t is_android_emulator;

    /** Reserved for future fields. Must be initialized to zero. */
    void* _reserved[4];
} rac_hardware_report_t;

/** Current schema version. Bump when adding fields in a breaking way. */
#define RAC_HARDWARE_REPORT_V1 ((uint32_t)1)

/**
 * @brief Populate `out_report` with current hardware capabilities.
 *
 * The caller sets `out_report->version = RAC_HARDWARE_REPORT_V1` before
 * calling; a mismatch returns RAC_ERROR_BACKEND_INCOMPATIBLE_VERSION.
 *
 * @param out_report Caller-owned struct. Required.
 * @return RAC_SUCCESS, or RAC_ERROR_INVALID_ARGUMENT / _INCOMPATIBLE_VERSION.
 */
RAC_API RAC_NODISCARD rac_result_t rac_hardware_query_capabilities(
    rac_hardware_report_t* out_report);

/**
 * @brief Return a pretty multi-line string summarising the report.
 *
 * The string is newly allocated by rac_strdup; caller must free it with
 * rac_free. Intended for logging / diagnostics, not machine parsing.
 */
RAC_API char* rac_hardware_format_report(const rac_hardware_report_t* report);

#ifdef __cplusplus
}
#endif

#endif  // RAC_HARDWARE_H
