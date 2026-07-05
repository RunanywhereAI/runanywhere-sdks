/**
 * @file rac_tts_config_defaults.cpp
 * @brief Canonical TTSConfiguration defaults helper.
 *
 * Commons-owned port of Swift's `RATTSConfiguration.defaults()`
 * (sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/TTS/
 * RATTSConfiguration+Helpers.swift) so every platform SDK consumes the same
 * default-population logic via a single C ABI.
 *
 * Canonical defaults (mirrored from Swift):
 *   model_id              = ""
 *   voice                 = "default"
 *   language_code         = "en-US"
 *   speaking_rate         = 1.0
 *   pitch                 = 1.0
 *   volume                = 1.0
 *   audio_format          = AUDIO_FORMAT_PCM
 *   sample_rate           = 22050
 *   enable_neural_voice   = true
 *   enable_ssml           = false
 *
 * Lives in a NEW source file rather than appending to rac_tts_service.cpp to
 * stay merge-safe while concurrent agents edit feature subtrees.
 */

#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/foundation/rac_proto_buffer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "model_types.pb.h"
#include "tts_options.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#endif

namespace {

#if defined(RAC_HAVE_PROTOBUF)

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    return rac::proto::copy_message(message, out, "failed to serialize TTSConfiguration defaults");
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

// PUBLIC API

extern "C" rac_result_t
rac_tts_configuration_defaults_proto(rac_proto_buffer_t* out_RATTSConfiguration) {
    if (!out_RATTSConfiguration) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    return rac_proto_buffer_set_error(out_RATTSConfiguration, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    runanywhere::v1::TTSConfiguration cfg;
    // model_id defaults to empty string (proto zero value).
    cfg.set_voice(std::string("default"));
    cfg.set_language_code(std::string("en-US"));
    cfg.set_speaking_rate(1.0f);
    cfg.set_pitch(1.0f);
    cfg.set_volume(1.0f);
    cfg.set_audio_format(runanywhere::v1::AUDIO_FORMAT_PCM);
    cfg.set_sample_rate(22050);
    cfg.set_enable_neural_voice(true);
    cfg.set_enable_ssml(false);
    return copy_proto(cfg, out_RATTSConfiguration);
#endif
}
