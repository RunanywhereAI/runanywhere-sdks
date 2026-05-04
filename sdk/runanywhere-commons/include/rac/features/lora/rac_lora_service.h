/**
 * @file rac_lora_service.h
 * @brief RunAnywhere Commons - LoRA proto-byte service ABI.
 */

#ifndef RAC_LORA_SERVICE_H
#define RAC_LORA_SERVICE_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_lora_registry.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Register a LoRA catalog entry from serialized
 *        runanywhere.v1.LoraAdapterCatalogEntry bytes.
 *
 * out_entry receives the canonical serialized entry bytes on success.
 */
RAC_API rac_result_t rac_lora_register_proto(rac_lora_registry_handle_t registry,
                                             const uint8_t* entry_proto_bytes,
                                             size_t entry_proto_size,
                                             rac_proto_buffer_t* out_entry);

/**
 * @brief Check LoRA compatibility from serialized runanywhere.v1.LoRAAdapterConfig bytes.
 *
 * llm_component must be a lifecycle-owned LLM component handle. out_result
 * receives serialized runanywhere.v1.LoraCompatibilityResult bytes.
 */
RAC_API rac_result_t rac_lora_compatibility_proto(rac_handle_t llm_component,
                                                  const uint8_t* config_proto_bytes,
                                                  size_t config_proto_size,
                                                  rac_proto_buffer_t* out_result);

/**
 * @brief Load a LoRA adapter from serialized runanywhere.v1.LoRAAdapterConfig bytes.
 *
 * out_info receives serialized runanywhere.v1.LoRAAdapterInfo bytes on success.
 */
RAC_API rac_result_t rac_lora_load_proto(rac_handle_t llm_component,
                                         const uint8_t* config_proto_bytes,
                                         size_t config_proto_size,
                                         rac_proto_buffer_t* out_info);

/**
 * @brief Remove a LoRA adapter from serialized runanywhere.v1.LoRAAdapterConfig bytes.
 *
 * out_info receives serialized runanywhere.v1.LoRAAdapterInfo bytes describing
 * the detached adapter.
 */
RAC_API rac_result_t rac_lora_remove_proto(rac_handle_t llm_component,
                                           const uint8_t* config_proto_bytes,
                                           size_t config_proto_size,
                                           rac_proto_buffer_t* out_info);

/**
 * @brief Clear all LoRA adapters from the lifecycle-owned LLM component.
 *
 * out_info receives an empty runanywhere.v1.LoRAAdapterInfo snapshot.
 */
RAC_API rac_result_t rac_lora_clear_proto(rac_handle_t llm_component,
                                          rac_proto_buffer_t* out_info);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LORA_SERVICE_H */
