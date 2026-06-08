/**
 * @file rac_vlm_proto_adapters.h
 * @brief VLM C ABI <-> proto adapters (split out of foundation/rac_proto_adapters.h
 *        to restore commons header layering: foundation/ MUST NOT depend on features/).
 */

#ifndef RAC_VLM_PROTO_ADAPTERS_H
#define RAC_VLM_PROTO_ADAPTERS_H

#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
#include <cstddef>
#include <cstdint>
#endif

#include "rac/core/rac_types.h"
#include "rac/features/vlm/rac_vlm_types.h"

#ifdef __cplusplus

namespace runanywhere::v1 {
class VLMConfiguration;
class VLMGenerationOptions;
class VLMResult;
class VLMImage;
}  // namespace runanywhere::v1

namespace rac::foundation {

bool rac_vlm_options_from_proto(const ::runanywhere::v1::VLMGenerationOptions& in,
                                rac_vlm_options_t* out, const char** out_prompt);

void rac_vlm_options_free_owned(rac_vlm_options_t* options);

bool rac_vlm_result_to_proto(const rac_vlm_result_t* in, ::runanywhere::v1::VLMResult* out);
bool rac_vlm_image_from_proto(const ::runanywhere::v1::VLMImage& in, rac_vlm_image_t* out);

}  // namespace rac::foundation

#endif  // __cplusplus

#endif  // RAC_VLM_PROTO_ADAPTERS_H
