/**
 * @file rac_tts_proto_adapters.h
 * @brief TTS C ABI <-> proto adapters (split out of foundation/rac_proto_adapters.h
 *        to restore commons header layering: foundation/ MUST NOT depend on features/).
 */

#ifndef RAC_TTS_PROTO_ADAPTERS_H
#define RAC_TTS_PROTO_ADAPTERS_H

#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
#include <cstddef>
#include <cstdint>
#endif

#include "rac/core/rac_types.h"
#include "rac/features/tts/rac_tts_types.h"

#ifdef __cplusplus

namespace runanywhere::v1 {
class TTSConfiguration;
class TTSOptions;
class TTSOutput;
class TTSPhonemeTimestamp;
class TTSSynthesisMetadata;
class TTSSpeakResult;
}  // namespace runanywhere::v1

namespace rac::foundation {

bool rac_tts_options_from_proto(const ::runanywhere::v1::TTSOptions& in, rac_tts_options_t* out);

bool rac_tts_phoneme_timestamp_to_proto(const rac_tts_phoneme_timestamp_t* in,
                                        ::runanywhere::v1::TTSPhonemeTimestamp* out);
bool rac_tts_phoneme_timestamp_from_proto(const ::runanywhere::v1::TTSPhonemeTimestamp& in,
                                          rac_tts_phoneme_timestamp_t* out);

bool rac_tts_synthesis_metadata_to_proto(const rac_tts_synthesis_metadata_t* in,
                                         ::runanywhere::v1::TTSSynthesisMetadata* out);
bool rac_tts_synthesis_metadata_from_proto(const ::runanywhere::v1::TTSSynthesisMetadata& in,
                                           rac_tts_synthesis_metadata_t* out);

bool rac_tts_result_to_proto(const rac_tts_result_t* in, ::runanywhere::v1::TTSOutput* out);
}  // namespace rac::foundation

#endif  // __cplusplus

#endif  // RAC_TTS_PROTO_ADAPTERS_H
