/**
 * @file rac_stt_config_defaults.cpp
 * @brief Canonical STTConfiguration defaults helper.
 *
 * Commons-owned port of Swift's `RASTTConfiguration.defaults()`
 * (sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/STT/
 * RASTTConfiguration+Helpers.swift) so every platform SDK consumes the same
 * default-population logic via a single C ABI.
 *
 * Canonical defaults (mirrored from Swift):
 *   model_id      = ""
 *   language      = STT_LANGUAGE_EN
 *   sample_rate   = 16000
 *   enable_vad    = false
 *
 * Lives in a NEW source file rather than appending to rac_stt_service.cpp to
 * stay merge-safe while concurrent agents edit feature subtrees.
 */

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/foundation/rac_proto_buffer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "stt_options.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#endif

namespace {

#if defined(RAC_HAVE_PROTOBUF)

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    return rac::proto::copy_message(message, out, "failed to serialize STTConfiguration defaults");
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

// PUBLIC API

extern "C" rac_result_t
rac_stt_configuration_defaults_proto(rac_proto_buffer_t* out_RASTTConfiguration) {
    if (!out_RASTTConfiguration) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    return rac_proto_buffer_set_error(out_RASTTConfiguration, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    runanywhere::v1::STTConfiguration cfg;
    // model_id defaults to empty string (proto zero value).
    cfg.set_language(runanywhere::v1::STT_LANGUAGE_EN);
    cfg.set_sample_rate(16000);
    cfg.set_enable_vad(false);
    return copy_proto(cfg, out_RASTTConfiguration);
#endif
}
