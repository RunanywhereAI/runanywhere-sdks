/**
 * @file rac_structured_error.h
 * @brief RunAnywhere Commons - Error category taxonomy.
 *
 * The structured-error subsystem (rac_error_t, stack-trace capture,
 * thread-local last-error, rac_error_log_and_track) was retired once the
 * canonical proto SDKError path (rac_result_to_proto_error) became the sole
 * error surface across all SDKs. The error-category enum below is the only
 * survivor — the C-side taxonomy that rac_proto_adapters maps onto the proto
 * ErrorCategory.
 */

#ifndef RAC_STRUCTURED_ERROR_H
#define RAC_STRUCTURED_ERROR_H

#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// ERROR CATEGORIES

/**
 * @brief Error categories matching Swift's ErrorCategory.
 *
 * These define which component/modality an error belongs to.
 */
typedef enum rac_error_category {
    RAC_CATEGORY_GENERAL = 0,             /**< General SDK errors */
    RAC_CATEGORY_STT = 1,                 /**< Speech-to-Text errors */
    RAC_CATEGORY_TTS = 2,                 /**< Text-to-Speech errors */
    RAC_CATEGORY_LLM = 3,                 /**< Large Language Model errors */
    RAC_CATEGORY_VAD = 4,                 /**< Voice Activity Detection errors */
    RAC_CATEGORY_VLM = 5,                 /**< Vision Language Model errors */
    RAC_CATEGORY_SPEAKER_DIARIZATION = 6, /**< Speaker Diarization errors */
    RAC_CATEGORY_WAKE_WORD = 7,           /**< Wake Word Detection errors */
    RAC_CATEGORY_VOICE_AGENT = 8,         /**< Voice Agent errors */
    RAC_CATEGORY_DOWNLOAD = 9,            /**< Download errors */
    RAC_CATEGORY_FILE_MANAGEMENT = 10,    /**< File management errors */
    RAC_CATEGORY_NETWORK = 11,            /**< Network errors */
    RAC_CATEGORY_AUTHENTICATION = 12,     /**< Authentication errors */
    RAC_CATEGORY_SECURITY = 13,           /**< Security errors */
    RAC_CATEGORY_RUNTIME = 14,            /**< Runtime/backend errors */
} rac_error_category_t;

#ifdef __cplusplus
}
#endif

#endif /* RAC_STRUCTURED_ERROR_H */
