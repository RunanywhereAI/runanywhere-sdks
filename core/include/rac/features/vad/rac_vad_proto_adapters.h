/**
 * @file rac_vad_proto_adapters.h
 * @brief VAD C ABI <-> proto adapters (split out of foundation/rac_proto_adapters.h
 *        to restore commons header layering: foundation/ MUST NOT depend on features/).
 */

#ifndef RAC_VAD_PROTO_ADAPTERS_H
#define RAC_VAD_PROTO_ADAPTERS_H

#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
#include <cstddef>
#include <cstdint>
#endif

#include "rac/core/rac_types.h"
#include "rac/features/vad/rac_vad_types.h"

#ifdef __cplusplus

namespace runanywhere::v1 {
class VADConfiguration;
class VADOptions;
class VADResult;
class VADStatistics;
class SpeechActivityEvent;
}  // namespace runanywhere::v1

namespace rac::foundation {}  // namespace rac::foundation

#endif  // __cplusplus

#endif  // RAC_VAD_PROTO_ADAPTERS_H
