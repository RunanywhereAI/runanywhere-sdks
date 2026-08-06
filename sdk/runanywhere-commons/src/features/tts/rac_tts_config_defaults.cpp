/**
 * @file rac_tts_config_defaults.cpp
 * @brief Canonical TTSOptions defaults helper.
 *
 * TTSConfiguration was deleted from tts_options.proto entirely (it was
 * write-only: engine pinning already resolves off ModelLoadRequest, and
 * "which voice" is TTSOptions.model). The canonical per-call default surface
 * is now TTSOptions itself, so this helper serializes the same-shaped
 * defaults onto that message instead.
 *
 * Canonical defaults:
 *   voice                 = "default"
 *   language_code         = "en-US"
 *   speed                 = 1.0
 *   pitch                 = 1.0
 *   volume                = 1.0
 *   audio_format          = AUDIO_FORMAT_PCM
 *   sample_rate           = 0   (0 = the voice's native rate)
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
    return rac::proto::copy_message(message, out, "failed to serialize TTSOptions defaults");
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

// =============================================================================
// PUBLIC API
// =============================================================================

extern "C" rac_result_t
rac_tts_configuration_defaults_proto(rac_proto_buffer_t* out_RATTSConfiguration) {
    if (!out_RATTSConfiguration) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    return rac_proto_buffer_set_error(out_RATTSConfiguration, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    runanywhere::v1::TTSOptions opts;
    opts.set_voice(std::string("default"));
    opts.set_language_code(std::string("en-US"));
    opts.set_speed(1.0f);
    opts.set_pitch(1.0f);
    opts.set_volume(1.0f);
    opts.set_audio_format(runanywhere::v1::AUDIO_FORMAT_PCM);
    opts.set_sample_rate(0);
    return copy_proto(opts, out_RATTSConfiguration);
#endif
}
