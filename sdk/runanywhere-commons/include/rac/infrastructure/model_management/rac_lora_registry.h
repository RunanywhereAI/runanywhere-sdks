/**
 * @file rac_lora_registry.h
 * @brief LoRA Adapter Registry - In-Memory LoRA Adapter Metadata Management
 *
 * Provides a centralized registry for LoRA adapter metadata across all SDKs.
 * Follows the same pattern as rac_model_registry.h.
 *
 * Apps register LoRA adapters at startup with explicit compatible model IDs.
 * SDKs can then query "which adapters work with this model" without
 * reinventing detection logic per platform.
 *
 * NOTE: This registry is metadata only. The runtime compat check
 * (rac_llm_component_check_lora_compat) remains the safety net at load time.
 */

#ifndef RAC_LORA_REGISTRY_H
#define RAC_LORA_REGISTRY_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// TYPES

typedef struct rac_lora_entry {
    char* id;                       // Unique adapter identifier
    char* name;                     // Human-readable display name
    char* description;              // Short description of what this adapter does
    char* download_url;             // Direct download URL (.gguf file)
    char* filename;                 // Filename to save as on disk
    char** compatible_model_ids;    // Explicit list of compatible base model IDs
    size_t compatible_model_count;
    int64_t file_size;              // File size in bytes (0 if unknown)
    float default_scale;            // Recommended LoRA scale (e.g. 0.3)
} rac_lora_entry_t;

typedef struct rac_lora_registry* rac_lora_registry_handle_t;

// LIFECYCLE

/**
 * @brief Create a new LoRA adapter registry
 * @param out_handle Output: handle to the newly created registry
 * @return RAC_SUCCESS, RAC_ERROR_INVALID_ARGUMENT (NULL out_handle),
 *         or RAC_ERROR_OUT_OF_MEMORY
 */
RAC_API rac_result_t rac_lora_registry_create(rac_lora_registry_handle_t* out_handle);

/**
 * @brief Destroy a LoRA adapter registry and free all entries
 * @param handle Registry handle (NULL is a no-op)
 */
RAC_API void rac_lora_registry_destroy(rac_lora_registry_handle_t handle);

// REGISTRATION

/**
 * @brief Register a LoRA adapter entry in the registry
 *
 * The entry is deep-copied; the caller retains ownership of the original.
 * If an entry with the same id already exists, it is replaced.
 *
 * @param handle Registry handle
 * @param entry Adapter entry to register (must have a non-NULL id)
 * @return RAC_SUCCESS, RAC_ERROR_INVALID_ARGUMENT (NULL handle/entry/id),
 *         or RAC_ERROR_OUT_OF_MEMORY
 */
RAC_API rac_result_t rac_lora_registry_register(rac_lora_registry_handle_t handle,
                                                 const rac_lora_entry_t* entry);

/**
 * @brief Remove a LoRA adapter entry from the registry by id
 * @param handle Registry handle
 * @param adapter_id ID of the adapter to remove
 * @return RAC_SUCCESS or RAC_ERROR_NOT_FOUND
 */
RAC_API rac_result_t rac_lora_registry_remove(rac_lora_registry_handle_t handle,
                                               const char* adapter_id);

// QUERIES

/**
 * @brief Get all registered LoRA adapter entries
 * @param handle Registry handle
 * @param out_entries Output: array of deep-copied entries (caller must free with rac_lora_entry_array_free)
 * @param out_count Output: number of entries
 * @return RAC_SUCCESS, RAC_ERROR_INVALID_ARGUMENT (NULL params),
 *         or RAC_ERROR_OUT_OF_MEMORY
 */
RAC_API rac_result_t rac_lora_registry_get_all(rac_lora_registry_handle_t handle,
                                                rac_lora_entry_t*** out_entries,
                                                size_t* out_count);

/**
 * @brief Get LoRA adapter entries compatible with a specific model
 * @param handle Registry handle
 * @param model_id Model ID to match against each entry's compatible_model_ids
 * @param out_entries Output: array of matching deep-copied entries (caller must free with rac_lora_entry_array_free)
 * @param out_count Output: number of matching entries
 * @return RAC_SUCCESS, RAC_ERROR_INVALID_ARGUMENT (NULL params),
 *         or RAC_ERROR_OUT_OF_MEMORY
 */
RAC_API rac_result_t rac_lora_registry_get_for_model(rac_lora_registry_handle_t handle,
                                                      const char* model_id,
                                                      rac_lora_entry_t*** out_entries,
                                                      size_t* out_count);

/**
 * @brief Get a single LoRA adapter entry by id
 * @param handle Registry handle
 * @param adapter_id ID of the adapter to look up
 * @param out_entry Output: deep-copied entry (caller must free with rac_lora_entry_free)
 * @return RAC_SUCCESS, RAC_ERROR_INVALID_ARGUMENT (NULL params),
 *         RAC_ERROR_NOT_FOUND, or RAC_ERROR_OUT_OF_MEMORY
 */
RAC_API rac_result_t rac_lora_registry_get(rac_lora_registry_handle_t handle,
                                            const char* adapter_id,
                                            rac_lora_entry_t** out_entry);

// MEMORY

/**
 * @brief Free a single LoRA entry and all its owned strings
 * @param entry Entry to free (NULL is a no-op)
 */
RAC_API void rac_lora_entry_free(rac_lora_entry_t* entry);

/**
 * @brief Free an array of LoRA entries returned by get_all / get_for_model
 * @param entries Array of entry pointers
 * @param count Number of entries in the array
 */
RAC_API void rac_lora_entry_array_free(rac_lora_entry_t** entries, size_t count);

/**
 * @brief Deep-copy a LoRA entry
 * @param entry Entry to copy
 * @return Newly allocated copy (caller must free with rac_lora_entry_free), or NULL on allocation failure
 */
RAC_API rac_lora_entry_t* rac_lora_entry_copy(const rac_lora_entry_t* entry);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LORA_REGISTRY_H */
