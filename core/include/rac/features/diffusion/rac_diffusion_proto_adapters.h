/**
 * @file rac_diffusion_proto_adapters.h
 * @brief Diffusion C ABI <-> proto adapters (split out of foundation/rac_proto_adapters.h
 *        to restore commons header layering: foundation/ MUST NOT depend on features/).
 */

#ifndef RAC_DIFFUSION_PROTO_ADAPTERS_H
#define RAC_DIFFUSION_PROTO_ADAPTERS_H

#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
#include <cstddef>
#include <cstdint>
#endif

#include "rac/core/rac_types.h"
#include "rac/features/diffusion/rac_diffusion_types.h"

#ifdef __cplusplus

namespace runanywhere::v1 {
class DiffusionConfiguration;
class DiffusionGenerationOptions;
class DiffusionProgress;
class DiffusionResult;
}  // namespace runanywhere::v1

namespace rac::foundation {

// Returns RAC_ERROR_NULL_POINTER for a null out, RAC_ERROR_OUT_OF_MEMORY when a
// string or image copy fails, and RAC_ERROR_DECODING_ERROR when the request is
// malformed (an image payload that is not PNG/JPEG, or an image/inpainting mode
// missing its image or mask). On failure with non-null out, every owned field is
// released and out is reset to RAC_DIFFUSION_OPTIONS_DEFAULT.
rac_result_t rac_diffusion_options_from_proto(
    const ::runanywhere::v1::DiffusionGenerationOptions& in, rac_diffusion_options_t* out);

bool rac_diffusion_progress_to_proto(const rac_diffusion_progress_t* in,
                                     ::runanywhere::v1::DiffusionProgress* out);
bool rac_diffusion_result_to_proto(const rac_diffusion_result_t* in,
                                   ::runanywhere::v1::DiffusionResult* out);
}  // namespace rac::foundation

#endif  // __cplusplus

#endif  // RAC_DIFFUSION_PROTO_ADAPTERS_H
