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

namespace rac::foundation {

bool rac_vad_config_to_proto(const rac_vad_config_t* in, ::runanywhere::v1::VADConfiguration* out);
bool rac_vad_config_from_proto(const ::runanywhere::v1::VADConfiguration& in,
                               rac_vad_config_t* out);

bool rac_vad_input_to_proto_options(const rac_vad_input_t* in, ::runanywhere::v1::VADOptions* out);
bool rac_vad_input_from_proto_options(const ::runanywhere::v1::VADOptions& in,
                                      rac_vad_input_t* out);

bool rac_vad_output_to_proto(const rac_vad_output_t* in, ::runanywhere::v1::VADResult* out);
bool rac_vad_output_from_proto(const ::runanywhere::v1::VADResult& in, rac_vad_output_t* out);

bool rac_vad_statistics_to_proto(const rac_vad_statistics_t* in,
                                 ::runanywhere::v1::VADStatistics* out);
bool rac_vad_statistics_from_proto(const ::runanywhere::v1::VADStatistics& in,
                                   rac_vad_statistics_t* out);

bool rac_speech_activity_to_proto(rac_speech_activity_t in_kind, int64_t in_timestamp_ms,
                                  int32_t in_duration_ms,
                                  ::runanywhere::v1::SpeechActivityEvent* out);
bool rac_speech_activity_from_proto(const ::runanywhere::v1::SpeechActivityEvent& in,
                                    rac_speech_activity_t* out_kind, int64_t* out_timestamp_ms,
                                    int32_t* out_duration_ms);

}  // namespace rac::foundation

#endif  // __cplusplus

#endif  // RAC_VAD_PROTO_ADAPTERS_H
