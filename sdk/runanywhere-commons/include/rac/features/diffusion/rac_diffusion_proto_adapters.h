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

bool rac_diffusion_config_to_proto(const rac_diffusion_config_t* in,
                                   ::runanywhere::v1::DiffusionConfiguration* out);
bool rac_diffusion_config_from_proto(const ::runanywhere::v1::DiffusionConfiguration& in,
                                     rac_diffusion_config_t* out);

bool rac_diffusion_options_to_proto(const rac_diffusion_options_t* in,
                                    ::runanywhere::v1::DiffusionGenerationOptions* out);
bool rac_diffusion_options_from_proto(const ::runanywhere::v1::DiffusionGenerationOptions& in,
                                      rac_diffusion_options_t* out);

bool rac_diffusion_progress_to_proto(const rac_diffusion_progress_t* in,
                                     ::runanywhere::v1::DiffusionProgress* out);
bool rac_diffusion_progress_from_proto(const ::runanywhere::v1::DiffusionProgress& in,
                                       rac_diffusion_progress_t* out);

bool rac_diffusion_result_to_proto(const rac_diffusion_result_t* in,
                                   ::runanywhere::v1::DiffusionResult* out);
bool rac_diffusion_result_from_proto(const ::runanywhere::v1::DiffusionResult& in,
                                     rac_diffusion_result_t* out);

}  // namespace rac::foundation

#endif  // __cplusplus

#endif  // RAC_DIFFUSION_PROTO_ADAPTERS_H
