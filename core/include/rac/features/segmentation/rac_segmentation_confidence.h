/** @file rac_segmentation_confidence.h @brief Optional ABI-14 confidence extension. */
#ifndef RAC_FEATURES_SEGMENTATION_RAC_SEGMENTATION_CONFIDENCE_H
#define RAC_FEATURES_SEGMENTATION_RAC_SEGMENTATION_CONFIDENCE_H

#include "rac/features/segmentation/rac_segmentation_service.h"
#include "rac/plugin/rac_engine_manifest.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Engine capability bit 40 is reserved for this manifest extension. Both the
 * manifest and vtable metadata MUST advertise it. An engine setting this bit
 * MUST allocate rac_segmentation_confidence_manifest_v1_t, with the unchanged
 * legacy manifest as its first member. Older hosts ignore this additive flag.
 * No existing options, result, service, ops table, or engine slot is extended.
 */
#define RAC_ENGINE_CAP_SEGMENTATION_CONFIDENCE_V1 (UINT64_C(1) << 40)
#define RAC_SEGMENTATION_CONFIDENCE_VERSION_1 1u

/** Independently owned, malloc/free-compatible confidence output. Initialize
 * with RAC_SEGMENTATION_CONFIDENCE_MASK_DEFAULT before calling. One byte per
 * source pixel, row-major, round(255 * winning-class softmax probability).
 * Callers must release this output separately from the legacy result.
 */
typedef struct rac_segmentation_confidence_mask_v1 {
    uint32_t struct_size;
    uint32_t version;
    uint8_t* data;
    size_t size;
} rac_segmentation_confidence_mask_v1_t;

static const rac_segmentation_confidence_mask_v1_t RAC_SEGMENTATION_CONFIDENCE_MASK_DEFAULT = {
    .struct_size = sizeof(rac_segmentation_confidence_mask_v1_t),
    .version = RAC_SEGMENTATION_CONFIDENCE_VERSION_1,
    .data = RAC_NULL,
    .size = 0,
};

typedef struct rac_segmentation_confidence_ops_v1 {
    uint32_t struct_size;
    uint32_t version;
    /** Uses the SAME impl as the legacy segmentation table. All partial output
     * fields remain caller-owned on failure, including exceptions translated by
     * the engine. The host validates dimensions and frees both outputs on error.
     * Engines must not import new host symbols to support older ABI-14 hosts.
     */
    rac_result_t (*segment)(void* impl, const rac_segmentation_image_t* image,
                            const rac_segmentation_options_t* options,
                            rac_segmentation_result_t* out_result,
                            rac_segmentation_confidence_mask_v1_t* out_confidence);
} rac_segmentation_confidence_ops_v1_t;

typedef struct rac_segmentation_confidence_manifest_v1 {
    rac_engine_manifest_t manifest;
    uint32_t struct_size;
    uint32_t version;
    const rac_segmentation_confidence_ops_v1_t* confidence_ops;
} rac_segmentation_confidence_manifest_v1_t;

/** Opt-in operation on a handle returned by rac_segmentation_create. Returns
 * RAC_ERROR_NOT_SUPPORTED if its selected engine has no confidence extension;
 * never retries on another engine. Output must be empty on entry. On inference
 * or payload errors, both outputs are released and reset. Invalid version/size
 * headers are rejected before any plugin callback or output-payload access.
 */
RAC_API rac_result_t rac_segmentation_segment_with_confidence(
    rac_handle_t handle, const rac_segmentation_image_t* image,
    const rac_segmentation_options_t* options, rac_segmentation_result_t* out_result,
    rac_segmentation_confidence_mask_v1_t* out_confidence);

/** Release a valid V1 output and reset it for reuse; safe on NULL. */
RAC_API void
rac_segmentation_confidence_mask_free(rac_segmentation_confidence_mask_v1_t* confidence);

#ifdef __cplusplus
}
#endif
#endif /* RAC_FEATURES_SEGMENTATION_RAC_SEGMENTATION_CONFIDENCE_H */
