/**
 * @file rac_npu_capability.h
 * @brief Compatibility C ABI for Qualcomm Hexagon NPU capability probing.
 *
 * These declarations shipped from commons before the QHexRT engine introduced
 * its engine-scoped API. They remain available for source and binary
 * compatibility in the current SDK version. New QHexRT integrations should
 * prefer <rac/qhexrt/rac_qhexrt.h>.
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
    /** SoC model string (for example "SM8750"); empty when unknown. */
    char soc_model[64];
    /** /sys/devices/soc0/soc_id value; -1 when unavailable. */
    int32_t soc_id;
    /** Detected Hexagon architecture, or RAC_HEXAGON_ARCH_UNKNOWN. */
    rac_hexagon_arch_t hexagon_arch;
    /** RAC_TRUE iff the architecture is supported by QHexRT. */
    rac_bool_t qhexrt_supported;
} rac_npu_info_t;

/**
 * Probe the device's Hexagon NPU capability without loading QNN. Unknown and
 * unsupported devices are successful probe results.
 */
RAC_API rac_result_t rac_npu_probe(rac_npu_info_t* out);

/** Return a stable lowercase arch name ("v68" through "v81", or "unknown"). */
RAC_API const char* rac_hexagon_arch_name(rac_hexagon_arch_t arch);

/** Serialize rac_npu_probe() as runanywhere.v1.NpuCapability bytes. */
RAC_API rac_result_t rac_npu_probe_proto(rac_proto_buffer_t* out_capability);

#ifdef __cplusplus
}
#endif

#endif  // RAC_NPU_CAPABILITY_H
