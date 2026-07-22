/** @file rac_segmentation_types.h @brief Backend-facing semantic segmentation types. */

#ifndef RAC_FEATURES_SEGMENTATION_RAC_SEGMENTATION_TYPES_H
#define RAC_FEATURES_SEGMENTATION_RAC_SEGMENTATION_TYPES_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum rac_segmentation_pixel_format {
    RAC_SEGMENTATION_PIXEL_FORMAT_UNSPECIFIED = 0,
    RAC_SEGMENTATION_PIXEL_FORMAT_RGB8 = 1,
    RAC_SEGMENTATION_PIXEL_FORMAT_RGBA8 = 2,
    RAC_SEGMENTATION_PIXEL_FORMAT_BGRA8 = 3,
} rac_segmentation_pixel_format_t;

typedef struct rac_segmentation_image {
    const uint8_t* data;
    size_t data_size;
    uint32_t width;
    uint32_t height;
    size_t stride_bytes;
    rac_segmentation_pixel_format_t pixel_format;
} rac_segmentation_image_t;

typedef struct rac_segmentation_options {
    rac_bool_t include_diagnostic_rgba;
} rac_segmentation_options_t;

static const rac_segmentation_options_t RAC_SEGMENTATION_OPTIONS_DEFAULT = {
    .include_diagnostic_rgba = RAC_FALSE,
};

typedef struct rac_segmentation_class_summary {
    uint32_t class_id;
    uint64_t pixel_count;
    float fraction;
    char* label;
} rac_segmentation_class_summary_t;

typedef struct rac_segmentation_result {
    uint32_t width;
    uint32_t height;
    uint16_t* class_mask;
    size_t class_mask_count;
    uint8_t* diagnostic_rgba;
    size_t diagnostic_rgba_size;
    rac_segmentation_class_summary_t* class_summaries;
    size_t class_summary_count;
    int64_t processing_time_ms;
    char* model_id;
} rac_segmentation_result_t;

/** Free every malloc-owned result field and zero the struct. */
RAC_API void rac_segmentation_result_free(rac_segmentation_result_t* result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_FEATURES_SEGMENTATION_RAC_SEGMENTATION_TYPES_H */
