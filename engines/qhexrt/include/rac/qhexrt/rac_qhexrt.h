/**
 * @file rac_qhexrt.h
 * @brief Public C ABI for QHexRT device capability and model catalog policy.
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

/** Return whether @p model_id is in QHexRT's native product catalog. */
RAC_API rac_bool_t rac_qhexrt_catalog_model_is_known(const char* model_id);

/** Return whether QHexRT's native catalog allows @p model_id on @p arch. */
RAC_API rac_bool_t rac_qhexrt_catalog_model_supports_arch(const char* model_id,
                                                          rac_qhexrt_hexagon_arch_t arch);

/** Return whether QHexRT's native catalog marks @p model_id as HF-authenticated. */
RAC_API rac_bool_t rac_qhexrt_catalog_model_requires_hf_auth(const char* model_id);

/**
 * Return the total number of rows in QHexRT's native product catalog. Lets
 * tests assert their enumerated coverage against the real policy array instead
 * of a hand-copied literal, so a new catalog row cannot silently go unverified.
 */
RAC_API size_t rac_qhexrt_catalog_model_count(void);

/**
 * Register a QHexRT catalog definition only when it is eligible on this
 * device. The request is an existing serialized
 * runanywhere.v1.RegisterModelFromUrlRequest. It carries a stable native
 * catalog id while URLs and presentation metadata remain in example apps.
 *
 * The request must carry an explicit id present in QHexRT's native product
 * catalog and the QHEXRT framework. The native policy owns per-model
 * v75/v79/v81 applicability and HF-auth requirements. It skips private rows
 * before network access when no token is configured, probes the chip, selects
 * the matching HNPU folder, then delegates normalized registration and all
 * later model lifecycle work to backend-neutral commons primitives.
 *
 * Inputs are borrowed for the call. The caller initializes @p out_model with
 * rac_proto_buffer_init() and frees it with rac_proto_buffer_free(). A normal
 * unsupported/ineligible outcome returns RAC_SUCCESS, sets
 * @p out_registered to RAC_FALSE, and writes an empty success buffer.
 */
RAC_API rac_result_t rac_qhexrt_catalog_register_model_proto(const uint8_t* request_bytes,
                                                             size_t request_size,
                                                             rac_bool_t* out_registered,
                                                             rac_proto_buffer_t* out_model);

#ifdef __cplusplus
}
#endif

#endif  // RAC_QHEXRT_H
