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
RAC_API rac_result_t rac_lora_registry_create(rac_lora_registry_handle_t* out_handle);
RAC_API void rac_lora_registry_destroy(rac_lora_registry_handle_t handle);

// REGISTRATION
RAC_API rac_result_t rac_lora_registry_register(rac_lora_registry_handle_t handle,
                                                 const rac_lora_entry_t* entry);
RAC_API rac_result_t rac_lora_registry_remove(rac_lora_registry_handle_t handle,
                                               const char* adapter_id);

// QUERIES
RAC_API rac_result_t rac_lora_registry_get_all(rac_lora_registry_handle_t handle,
                                                rac_lora_entry_t*** out_entries,
                                                size_t* out_count);
RAC_API rac_result_t rac_lora_registry_get_for_model(rac_lora_registry_handle_t handle,
                                                      const char* model_id,
                                                      rac_lora_entry_t*** out_entries,
                                                      size_t* out_count);
RAC_API rac_result_t rac_lora_registry_get(rac_lora_registry_handle_t handle,
                                            const char* adapter_id,
                                            rac_lora_entry_t** out_entry);

// MEMORY
RAC_API void rac_lora_entry_free(rac_lora_entry_t* entry);
RAC_API void rac_lora_entry_array_free(rac_lora_entry_t** entries, size_t count);
RAC_API rac_lora_entry_t* rac_lora_entry_copy(const rac_lora_entry_t* entry);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LORA_REGISTRY_H */
