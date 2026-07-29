/**
 * @file rac_qhexrt.h
 * @brief Public C ABI for QHexRT device capability.
 *
 * QHexRT owns Qualcomm-specific SoC/Hexagon selection. Generic model registry,
 * HTTP, download, extraction, validation, and local-path workflows remain in
 * runanywhere-commons and are composed by this engine facade.
 */

#ifndef RAC_QHEXRT_H
#define RAC_QHEXRT_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Hexagon DSP (HTP) architecture generation used by QHexRT bundles. */
typedef enum rac_qhexrt_hexagon_arch {
    RAC_QHEXRT_HEXAGON_ARCH_UNKNOWN = 0,
    RAC_QHEXRT_HEXAGON_ARCH_V68 = 68,
    RAC_QHEXRT_HEXAGON_ARCH_V69 = 69,
    RAC_QHEXRT_HEXAGON_ARCH_V73 = 73,
    RAC_QHEXRT_HEXAGON_ARCH_V75 = 75,
    RAC_QHEXRT_HEXAGON_ARCH_V79 = 79,
    RAC_QHEXRT_HEXAGON_ARCH_V81 = 81,
} rac_qhexrt_hexagon_arch_t;

/** Result of rac_qhexrt_probe(). */
typedef struct rac_qhexrt_device_info {
    /** Android SoC model (for example "SM8850"); empty when unknown. */
    char soc_model[64];
    /** /sys/devices/soc0/soc_id; -1 when unavailable. */
    int32_t soc_id;
    /** Detected Hexagon architecture. */
    rac_qhexrt_hexagon_arch_t hexagon_arch;
    /** True only for QHexRT's device-validated v75/v79/v81 set. */
    rac_bool_t supported;
} rac_qhexrt_device_info_t;

/** Return whether @p arch is in QHexRT's device-validated v75/v79/v81 set. */
RAC_API rac_bool_t rac_qhexrt_arch_is_supported(rac_qhexrt_hexagon_arch_t arch);

/** Return a stable lowercase name ("v68" through "v81", or "unknown"). */
RAC_API const char* rac_qhexrt_arch_name(rac_qhexrt_hexagon_arch_t arch);

/**
 * Probe the Android SoC/Hexagon generation without loading QNN. Unknown and
 * unsupported devices are successful probe results with supported=false.
 */
RAC_API rac_result_t rac_qhexrt_probe(rac_qhexrt_device_info_t* out);

/**
 * Serialize rac_qhexrt_probe() as runanywhere.v1.NpuCapability bytes. The
 * generated HexagonArch values intentionally equal this C enum's numbers.
 */
RAC_API rac_result_t rac_qhexrt_probe_proto(rac_proto_buffer_t* out_capability);

#ifdef __cplusplus
}
#endif

#endif  // RAC_QHEXRT_H
