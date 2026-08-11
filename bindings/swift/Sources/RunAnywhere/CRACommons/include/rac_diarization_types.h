/**
 * @file rac_diarization_types.h
 * @brief Backend-facing standalone speaker-diarization types.
 *
 * SDK callers use the generated-proto ABI. These structs are the internal
 * service boundary implemented by engine plugins.
 */

#ifndef RAC_FEATURES_DIARIZATION_RAC_DIARIZATION_TYPES_H
#define RAC_FEATURES_DIARIZATION_RAC_DIARIZATION_TYPES_H

#include <stddef.h>
#include <stdint.h>

#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rac_diarization_options {
    int32_t sample_rate_hz;
    int32_t channel_count;
    float threshold;
    int64_t minimum_duration_ms;
    int64_t merge_gap_ms;
} rac_diarization_options_t;

static const rac_diarization_options_t RAC_DIARIZATION_OPTIONS_DEFAULT = {
    .sample_rate_hz = 16000,
    .channel_count = 1,
    .threshold = 0.5f,
    .minimum_duration_ms = 0,
    .merge_gap_ms = 0,
};

typedef struct rac_diarization_segment {
    int64_t start_ms;
    int64_t end_ms;
    int32_t speaker_index;
    char* speaker_id;
} rac_diarization_segment_t;

typedef struct rac_diarization_result {
    rac_diarization_segment_t* segments;
    size_t segment_count;
    int32_t speaker_count;
    int64_t audio_duration_ms;
    int64_t processing_time_ms;
    char* model_id;
} rac_diarization_result_t;

/**
 * Free all malloc-owned fields in a success or partial-error backend result
 * and zero the struct. NULL is accepted; calling again after the first free is
 * safe because the first call clears every field.
 */
RAC_API void rac_diarization_result_free(rac_diarization_result_t* result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_FEATURES_DIARIZATION_RAC_DIARIZATION_TYPES_H */
