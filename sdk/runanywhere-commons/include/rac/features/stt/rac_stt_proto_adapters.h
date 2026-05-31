/**
 * @file rac_stt_proto_adapters.h
 * @brief STT C ABI <-> proto adapters (split out of foundation/rac_proto_adapters.h
 *        to restore commons header layering: foundation/ MUST NOT depend on features/).
 */

#ifndef RAC_STT_PROTO_ADAPTERS_H
#define RAC_STT_PROTO_ADAPTERS_H

#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
#include <cstddef>
#include <cstdint>
#endif

#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_types.h"

#ifdef __cplusplus

namespace runanywhere::v1 {
class STTConfiguration;
class STTOptions;
class STTOutput;
class WordTimestamp;
class TranscriptionMetadata;
class TranscriptionAlternative;
}  // namespace runanywhere::v1

namespace rac::foundation {

bool rac_stt_config_to_proto(const rac_stt_config_t* in, ::runanywhere::v1::STTConfiguration* out);
bool rac_stt_config_from_proto(const ::runanywhere::v1::STTConfiguration& in,
                               rac_stt_config_t* out);

bool rac_stt_options_to_proto(const rac_stt_options_t* in, ::runanywhere::v1::STTOptions* out);
bool rac_stt_options_from_proto(const ::runanywhere::v1::STTOptions& in, rac_stt_options_t* out);

bool rac_stt_word_to_proto(const rac_stt_word_t* in, ::runanywhere::v1::WordTimestamp* out);
bool rac_stt_word_from_proto(const ::runanywhere::v1::WordTimestamp& in, rac_stt_word_t* out);

bool rac_transcription_metadata_to_proto(const rac_transcription_metadata_t* in,
                                         ::runanywhere::v1::TranscriptionMetadata* out);
bool rac_transcription_metadata_from_proto(const ::runanywhere::v1::TranscriptionMetadata& in,
                                           rac_transcription_metadata_t* out);

bool rac_transcription_alternative_to_proto(const rac_transcription_alternative_t* in,
                                            ::runanywhere::v1::TranscriptionAlternative* out);
bool rac_transcription_alternative_from_proto(const ::runanywhere::v1::TranscriptionAlternative& in,
                                              rac_transcription_alternative_t* out);

bool rac_stt_output_to_proto(const rac_stt_output_t* in, ::runanywhere::v1::STTOutput* out);
bool rac_stt_output_from_proto(const ::runanywhere::v1::STTOutput& in, rac_stt_output_t* out);

bool rac_stt_result_to_proto(const rac_stt_result_t* in, ::runanywhere::v1::STTOutput* out);
bool rac_stt_result_from_proto(const ::runanywhere::v1::STTOutput& in, rac_stt_result_t* out);

}  // namespace rac::foundation

#endif  // __cplusplus

#endif  // RAC_STT_PROTO_ADAPTERS_H
