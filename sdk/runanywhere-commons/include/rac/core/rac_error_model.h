#ifndef RAC_ERROR_MODEL_H
#define RAC_ERROR_MODEL_H

#include "rac/core/rac_error.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Structured error model for RunAnywhere SDKs
 *
 * This wraps existing rac_result_t codes into a typed,
 * structured error representation for cross-SDK consistency.
 */
typedef struct {
    rac_result_t code;      /**< Numeric error code */
    const char* message;    /**< Human-readable error message */
    const char* category;   /**< Error category (e.g., Model, Network, Validation) */
} rac_error_model_t;

/**
 * @brief Create structured error model from error code
 */
rac_error_model_t rac_make_error_model(rac_result_t code);

/**
 * @brief Get error category string from error code
 */
const char* rac_error_category(rac_result_t code);

#ifdef __cplusplus
}
#endif

#endif // RAC_ERROR_MODEL_H