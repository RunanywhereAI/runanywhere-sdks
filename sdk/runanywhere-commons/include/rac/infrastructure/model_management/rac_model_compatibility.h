/**
 * @file rac_model_compatibility.h
 * @brief Model Compatibility Check - Checks device RAM/storage against model requirements
 *
 * Minimalist check: compares the model's memory_required and download_size
 * against the device's available RAM and free storage.
 */

#ifndef RAC_MODEL_COMPATIBILITY_H
#define RAC_MODEL_COMPATIBILITY_H

#include "rac/core/rac_types.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Result of a model compatibility check
 */
typedef struct rac_model_compatibility_result {
    /** Overall compatibility (canRun AND canFit) */
    rac_bool_t is_compatible;

    /** Whether the device has enough RAM to run the model */
    rac_bool_t can_run;

    /** Whether the device has enough free storage to download/store the model */
    rac_bool_t can_fit;

    /** Model's required RAM in bytes (from model registry) */
    int64_t required_memory;

    /** Device's available RAM in bytes */
    int64_t available_memory;

    /** Model's download/storage size in bytes (from model registry) */
    int64_t required_storage;

    /** Device's available storage in bytes */
    int64_t available_storage;
} rac_model_compatibility_result_t;

/**
 * @brief Check if a model is compatible with the current device
 *
 * Looks up the model in the registry, reads its memory_required and download_size,
 * then compares against the provided available RAM and storage values.
 *
 * @param registry_handle    Model registry handle (to look up model metadata)
 * @param model_id          Model identifier string
 * @param available_ram     Available RAM in bytes (provided by caller)
 * @param available_storage Available storage in bytes (provided by caller)
 * @param out_result        Output: compatibility result
 * @return RAC_SUCCESS, RAC_ERROR_NOT_FOUND if model not in registry, or other error
 */
RAC_API rac_result_t rac_model_check_compatibility(
    rac_model_registry_handle_t registry_handle,
    const char* model_id,
    int64_t available_ram,
    int64_t available_storage,
    rac_model_compatibility_result_t* out_result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_MODEL_COMPATIBILITY_H */