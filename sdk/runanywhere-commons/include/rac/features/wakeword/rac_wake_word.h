/**
 * @file rac_wake_word.h
 * @brief Wake Word C ABI stubs (§9).
 *
 * The full wake-word model pipeline is not yet integrated.  These stubs let
 * all SDK frontends link without crashing.  All functions return
 * RAC_ERROR_FEATURE_NOT_AVAILABLE until implemented.
 *
 * Note: rac_wakeword_types.h already exists and defines rac_wakeword_handle_t.
 * This file adds the canonical § 9 function shape expected by the frontends.
 */

#ifndef RAC_WAKE_WORD_H
#define RAC_WAKE_WORD_H

#include <stddef.h>
#include <stdbool.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/wakeword/rac_wakeword_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Opaque handle for a wake-word detector session.
 */
typedef struct rac_wake_word* rac_wake_word_handle_t;

/**
 * @brief Initialise a wake-word detector.
 *
 * @param model_path  Path to the wake-word model file.
 * @return RAC_SUCCESS or RAC_ERROR_FEATURE_NOT_AVAILABLE (stub).
 */
RAC_API rac_result_t rac_wake_word_init(const char* model_path);

/**
 * @brief Process audio samples and detect a wake word.
 *
 * @param samples       PCM float samples.
 * @param count         Number of samples.
 * @param detected_out  Output: true if wake word detected.
 * @return RAC_SUCCESS or error code.
 */
RAC_API rac_result_t rac_wake_word_process(const float* samples, size_t count,
                                           bool* detected_out);

/**
 * @brief Destroy the wake-word detector and free all resources.
 *
 * @param handle  Handle to destroy (may be NULL — no-op).
 */
RAC_API void rac_wake_word_destroy(rac_wake_word_handle_t* handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_WAKE_WORD_H */
