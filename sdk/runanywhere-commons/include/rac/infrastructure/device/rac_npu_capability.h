/**
 * @file rac_npu_capability.h
 * @brief Pre-flight Qualcomm Hexagon NPU capability probe.
 *
 * Detects the on-device Hexagon DSP architecture from the SoC identity WITHOUT
 * loading QNN or the QHexRT engine, so an SDK can decide up front whether the
 * QHexRT (Qualcomm NPU) backend will run and warn the user otherwise. The
 * QHexRT engine requires a Hexagon v75+ part; older parts
 * (v68/v69/v73) and non-Snapdragon devices fall back to CPU inference.
 *
 * Detection is best-effort and pre-flight only: it reads the Android SoC model
 * (`ro.soc.model`, API 31+) and the soc0 sysfs node. The authoritative arch is
 * still the one QHexRT reports from `QnnDevice_getPlatformInfo` once the engine
 * is created; this probe never loads QNN. On non-Android platforms it always
 * reports an unknown, unsupported part.
 */

#ifndef RAC_NPU_CAPABILITY_H
#define RAC_NPU_CAPABILITY_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Hexagon DSP (HTP) architecture generation. */
typedef enum rac_hexagon_arch {
    RAC_HEXAGON_ARCH_UNKNOWN = 0,
    RAC_HEXAGON_ARCH_V68 = 68,
    RAC_HEXAGON_ARCH_V69 = 69,
    RAC_HEXAGON_ARCH_V73 = 73,
    RAC_HEXAGON_ARCH_V75 = 75,
    RAC_HEXAGON_ARCH_V79 = 79,
    RAC_HEXAGON_ARCH_V81 = 81,
} rac_hexagon_arch_t;

/** Result of rac_npu_probe(). All fields are populated on RAC_SUCCESS. */
typedef struct rac_npu_info {
    /** SoC model string (e.g. "SM8750"); empty when unknown. NUL-terminated. */
    char soc_model[64];
    /** /sys/devices/soc0/soc_id value; -1 when unavailable. */
    int32_t soc_id;
    /** Detected Hexagon architecture, or RAC_HEXAGON_ARCH_UNKNOWN. */
    rac_hexagon_arch_t hexagon_arch;
    /** RAC_TRUE iff hexagon_arch is one the QHexRT engine supports (v75+). */
    rac_bool_t qhexrt_supported;
} rac_npu_info_t;

/**
 * @brief Probe the device's Hexagon NPU capability.
 * @param out Receives the detected SoC/arch info. MUST NOT be NULL.
 * @return RAC_SUCCESS once @p out is populated (even when the part is unknown
 *         or unsupported); RAC_ERROR_NULL_POINTER if @p out is NULL.
 */
RAC_API rac_result_t rac_npu_probe(rac_npu_info_t* out);

/** @return Lowercase arch name ("v79", "v81", ..., "unknown"). Never NULL. */
RAC_API const char* rac_hexagon_arch_name(rac_hexagon_arch_t arch);

/**
 * @brief Probe the NPU and serialize the result as
 *        `runanywhere.v1.NpuCapability` proto bytes — the single wire shape
 *        every SDK bridge decodes with its generated types (no hand-rolled
 *        JSON/struct mirrors). Never fails on unknown/unsupported parts.
 * @param out_capability Receives the serialized bytes; release with
 *        rac_proto_buffer_free(). MUST NOT be NULL.
 */
RAC_API rac_result_t rac_npu_probe_proto(rac_proto_buffer_t* out_capability);

#ifdef __cplusplus
}
#endif

#endif /* RAC_NPU_CAPABILITY_H */
