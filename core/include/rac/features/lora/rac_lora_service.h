/**
 * @file rac_lora_service.h
 * @brief RunAnywhere Commons - LoRA proto-byte service ABI.
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md): `SDK-facing default`.
 * Every entry point in this header takes/returns serialized
 * runanywhere.v1.LoraAdapterCatalogEntry / LoraAdapterCatalogQuery /
 * LoraAdapterCatalogListResult / LoraAdapterCatalogGetResult /
 * LoraAdapterDownloadCompletedRequest / LoRAAdapterConfig /
 * LoraCompatibilityResult / LoRAApplyRequest / LoRAApplyResult /
 * LoRARemoveRequest / LoRAState bytes.
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
 * @brief List LoRA catalog entries from serialized
 *        runanywhere.v1.LoraAdapterCatalogListRequest bytes.
 *
 * out_result receives serialized runanywhere.v1.LoraAdapterCatalogListResult bytes.
 */
RAC_API rac_result_t rac_lora_catalog_list_proto(rac_lora_registry_handle_t registry,
                                                 const uint8_t* request_proto_bytes,
                                                 size_t request_proto_size,
                                                 rac_proto_buffer_t* out_result);

/**
 * @brief Query LoRA catalog entries from serialized
 *        runanywhere.v1.LoraAdapterCatalogQuery bytes.
 *
 * out_result receives serialized runanywhere.v1.LoraAdapterCatalogListResult bytes.
 */
RAC_API rac_result_t rac_lora_catalog_query_proto(rac_lora_registry_handle_t registry,
                                                  const uint8_t* query_proto_bytes,
                                                  size_t query_proto_size,
                                                  rac_proto_buffer_t* out_result);

/**
 * @brief Fetch one LoRA catalog entry from serialized
 *        runanywhere.v1.LoraAdapterCatalogGetRequest bytes.
 *
 * out_result receives serialized runanywhere.v1.LoraAdapterCatalogGetResult bytes.
 */
RAC_API rac_result_t rac_lora_catalog_get_proto(rac_lora_registry_handle_t registry,
                                                const uint8_t* request_proto_bytes,
                                                size_t request_proto_size,
                                                rac_proto_buffer_t* out_result);

/**
 * @brief Persist native/Web-reported LoRA artifact completion state from serialized
 *        runanywhere.v1.LoraAdapterDownloadCompletedRequest bytes.
 *
 * Commons records canonical catalog metadata and stable local_path state only.
 * Native/Web remains responsible for HTTP bytes, platform file handles, and
 * permission-gated storage operations. out_result receives serialized
 * runanywhere.v1.LoraAdapterDownloadCompletedResult bytes.
 */
RAC_API rac_result_t rac_lora_catalog_mark_download_completed_proto(
    rac_lora_registry_handle_t registry, const uint8_t* request_proto_bytes,
    size_t request_proto_size, rac_proto_buffer_t* out_result);

/**
 * @brief Import a user-picked local LoRA adapter file from serialized
 *        runanywhere.v1.LoraAdapterImportRequest bytes.
 *
 * Commons owns everything past the platform-readable source path:
 * deterministic catalog matching (exact local-path match, else an unambiguous
 * filename match), canonical placement under
 * {Models}/{framework}/lora-adapter:{id}/, artifact model-registry record +
 * manifest persistence, and catalog completion (imported=true) for matched
 * entries. Platforms only resolve OS-specific access (security-scoped URLs,
 * content URIs, Blob-to-FS staging) before calling. out_result receives
 * serialized runanywhere.v1.LoraAdapterImportResult bytes.
 */
RAC_API rac_result_t rac_lora_adapter_import_proto(rac_lora_registry_handle_t registry,
                                                   const uint8_t* request_proto_bytes,
                                                   size_t request_proto_size,
                                                   rac_proto_buffer_t* out_result);

/**
 * @brief Check LoRA compatibility from serialized runanywhere.v1.LoRAAdapterConfig bytes.
 *
 * The target LLM is resolved through the model-lifecycle service
 * (rac_model_lifecycle_acquire_proto). When no LLM is loaded the call returns
 * a typed runanywhere.v1.LoraCompatibilityResult with is_compatible=false and
 * an error_code of RAC_ERROR_COMPONENT_NOT_READY. out_result receives
 * serialized runanywhere.v1.LoraCompatibilityResult bytes.
 */
RAC_API rac_result_t rac_lora_compatibility_proto(const uint8_t* config_proto_bytes,
                                                  size_t config_proto_size,
                                                  rac_proto_buffer_t* out_result);

/**
 * @brief Apply LoRA adapters from serialized runanywhere.v1.LoRAApplyRequest bytes.
 *
 * The target LLM is resolved through the model-lifecycle service
 * (rac_model_lifecycle_acquire_proto) so callers no longer pass a legacy
 * component handle. When no LLM is loaded a typed
 * runanywhere.v1.LoRAApplyResult with success=false and error_code
 * RAC_ERROR_COMPONENT_NOT_READY is returned. out_result receives serialized
 * runanywhere.v1.LoRAApplyResult bytes. Runtime failures that the generated
 * result message can represent are returned as a result with success=false
 * and populated error fields.
 */
RAC_API rac_result_t rac_lora_apply_proto(const uint8_t* request_proto_bytes,
                                          size_t request_proto_size,
                                          rac_proto_buffer_t* out_result);

/**
 * @brief Remove LoRA adapters from serialized runanywhere.v1.LoRARemoveRequest bytes.
 *
 * The target LLM is resolved through the model-lifecycle service. out_state
 * receives serialized runanywhere.v1.LoRAState bytes. The generated state is
 * tracked per lifecycle backend instance and updated only after successful
 * backend apply/remove/clear operations.
 */
RAC_API rac_result_t rac_lora_remove_proto(const uint8_t* request_proto_bytes,
                                           size_t request_proto_size,
                                           rac_proto_buffer_t* out_state);

/**
 * @brief List loaded LoRA adapters from serialized runanywhere.v1.LoRAState bytes.
 *
 * The target LLM is resolved through the model-lifecycle service. out_state
 * receives the generated per-backend runanywhere.v1.LoRAState snapshot
 * maintained by the C++ LoRA proto ABI.
 */
RAC_API rac_result_t rac_lora_list_proto(const uint8_t* state_proto_bytes, size_t state_proto_size,
                                         rac_proto_buffer_t* out_state);

/**
 * @brief Return LoRA service state from serialized runanywhere.v1.LoRAState bytes.
 *
 * The target LLM is resolved through the model-lifecycle service. out_state
 * receives the generated per-backend runanywhere.v1.LoRAState snapshot
 * maintained by the C++ LoRA proto ABI.
 */
RAC_API rac_result_t rac_lora_state_proto(const uint8_t* state_proto_bytes, size_t state_proto_size,
                                          rac_proto_buffer_t* out_state);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LORA_SERVICE_H */
