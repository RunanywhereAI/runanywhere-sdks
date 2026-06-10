/**
 * @file rac_model_lifecycle.h
 * @brief Canonical model lifecycle C ABI over generated proto bytes.
 *
 * Platform SDKs call this surface with serialized generated protos and receive
 * serialized generated protos in rac_proto_buffer_t. Commons owns the loaded
 * model/component state behind this ABI.
 */

#ifndef RAC_CORE_MODEL_LIFECYCLE_H
#define RAC_CORE_MODEL_LIFECYCLE_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Load a model from serialized runanywhere.v1.ModelLoadRequest bytes.
 *
 * Returns serialized runanywhere.v1.ModelLoadResult bytes in out_result on
 * request-level success. Semantic failures such as missing models or no route
 * are represented as ModelLoadResult.success=false.
 */
RAC_API rac_result_t rac_model_lifecycle_load_proto(rac_model_registry_handle_t registry,
                                                    const uint8_t* request_proto_bytes,
                                                    size_t request_proto_size,
                                                    rac_proto_buffer_t* out_result);

/**
 * @brief Resolve on-disk artifact paths for a registered model WITHOUT loading
 *        an engine (and without auto-download).
 *
 * Same request/response shapes as load: consumes serialized
 * runanywhere.v1.ModelLoadRequest bytes (only model_id is used) and returns
 * serialized runanywhere.v1.ModelLoadResult bytes where `resolved_path` is the
 * primary artifact (e.g. the .gguf file inside the model folder, or the inner
 * sherpa archive directory) and `resolved_artifacts` carries companions with
 * roles (e.g. MODEL_FILE_ROLE_VISION_PROJECTOR for a VLM mmproj).
 * `success=false` with error_message when the model is unknown or has no
 * resolvable local artifacts (not downloaded).
 *
 * Consumers: desktop CLI speech commands and any SDK path that needs the
 * canonical artifact resolution (the same logic the lifecycle loader uses)
 * before driving a per-handle component directly.
 */
RAC_API rac_result_t rac_model_lifecycle_resolve_paths_proto(
    rac_model_registry_handle_t registry, const uint8_t* request_proto_bytes,
    size_t request_proto_size, rac_proto_buffer_t* out_result);

/**
 * @brief Unload model(s) from serialized runanywhere.v1.ModelUnloadRequest bytes.
 *
 * Returns serialized runanywhere.v1.ModelUnloadResult bytes in out_result.
 */
RAC_API rac_result_t rac_model_lifecycle_unload_proto(const uint8_t* request_proto_bytes,
                                                      size_t request_proto_size,
                                                      rac_proto_buffer_t* out_result);

/**
 * @brief Query current model from serialized runanywhere.v1.CurrentModelRequest bytes.
 *
 * Returns serialized runanywhere.v1.CurrentModelResult bytes in out_result.
 */
RAC_API rac_result_t rac_model_lifecycle_current_model_proto(const uint8_t* request_proto_bytes,
                                                             size_t request_proto_size,
                                                             rac_proto_buffer_t* out_result);

/**
 * @brief Snapshot a component lifecycle state as serialized
 *        runanywhere.v1.ComponentLifecycleSnapshot bytes.
 *
 * component is the numeric runanywhere.v1.SDKComponent value.
 */
RAC_API rac_result_t rac_component_lifecycle_snapshot_proto(uint32_t component,
                                                            rac_proto_buffer_t* out_snapshot);

/**
 * @brief Test helper: unload all tracked models and reset lifecycle state.
 */
RAC_API void rac_model_lifecycle_reset(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_CORE_MODEL_LIFECYCLE_H */
