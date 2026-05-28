/**
 * @file rac_error_proto.cpp
 * @brief Implementation of `rac_result_to_proto_error()` — the canonical
 *        rac_result_t → serialized RASDKError mapping shared by every SDK.
 *
 * Reuses:
 *   - `rac_error_message()` (rac_error.cpp)         for the message string.
 *   - `rac_proto_buffer_*()` (rac_proto_buffer.cpp) for output ownership.
 *
 * The ErrorCategory mapping mirrors the canonical 9-bucket scheme already
 * used by the event publisher (event_publisher.cpp::error_category_for_code).
 * Keeping the mapping local to this TU avoids leaking proto types into the
 * `rac_error.h` public surface; the function is still available across the
 * library because both this TU and the event publisher live inside
 * `rac_commons`.
 */

#include "rac/core/rac_error_proto.h"

#include <cstddef>
#include <cstdint>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_structured_error.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef RAC_HAVE_PROTOBUF
#include "errors.pb.h"
#endif

#ifdef RAC_HAVE_PROTOBUF
namespace {

// Canonical 9-bucket category mapping. Mirrors event_publisher.cpp's
// error_category_for_code() so SDKError envelopes emitted via different
// surfaces always classify the same code identically.
::runanywhere::v1::ErrorCategory category_for_code(rac_result_t code) {
    if (code <= -100 && code >= -109)
        return ::runanywhere::v1::ERROR_CATEGORY_CONFIGURATION;
    if (code <= -110 && code >= -129)
        return ::runanywhere::v1::ERROR_CATEGORY_MODEL;
    if (code <= -130 && code >= -149)
        return ::runanywhere::v1::ERROR_CATEGORY_COMPONENT;
    if (code <= -150 && code >= -179)
        return ::runanywhere::v1::ERROR_CATEGORY_NETWORK;
    if ((code <= -180 && code >= -219) || (code <= -280 && code >= -299)) {
        return ::runanywhere::v1::ERROR_CATEGORY_IO;
    }
    if (code <= -220 && code >= -229)
        return ::runanywhere::v1::ERROR_CATEGORY_INTERNAL;
    if (code <= -230 && code >= -249)
        return ::runanywhere::v1::ERROR_CATEGORY_COMPONENT;
    if (code <= -250 && code >= -279)
        return ::runanywhere::v1::ERROR_CATEGORY_VALIDATION;
    if (code <= -300 && code >= -319)
        return ::runanywhere::v1::ERROR_CATEGORY_COMPONENT;
    if (code <= -320 && code >= -329)
        return ::runanywhere::v1::ERROR_CATEGORY_AUTH;
    if (code <= -330 && code >= -349)
        return ::runanywhere::v1::ERROR_CATEGORY_AUTH;
    if (code <= -350 && code >= -369)
        return ::runanywhere::v1::ERROR_CATEGORY_IO;
    if (code <= -370 && code >= -379)
        return ::runanywhere::v1::ERROR_CATEGORY_VALIDATION;
    if (code <= -380 && code >= -389)
        return ::runanywhere::v1::ERROR_CATEGORY_INTERNAL;
    if (code <= -400 && code >= -499)
        return ::runanywhere::v1::ERROR_CATEGORY_COMPONENT;
    if (code <= -500 && code >= -599)
        return ::runanywhere::v1::ERROR_CATEGORY_CONFIGURATION;
    if (code <= -600 && code >= -699)
        return ::runanywhere::v1::ERROR_CATEGORY_COMPONENT;
    if (code <= -700 && code >= -799)
        return ::runanywhere::v1::ERROR_CATEGORY_INTERNAL;
    if (code <= -800 && code >= -899)
        return ::runanywhere::v1::ERROR_CATEGORY_INTERNAL;
    if (code <= -900 && code >= -999)
        return ::runanywhere::v1::ERROR_CATEGORY_INTERNAL;
    return ::runanywhere::v1::ERROR_CATEGORY_UNSPECIFIED;
}

// Copies model_id / framework / session_id / source location / custom k-v pairs
// from a structured `rac_error_t` into the proto SDKError's ErrorContext, plus
// timestamp_ms and nested_message at the SDKError top level. Used when the
// caller has set a thread-local last error with the same code as the one being
// serialized, so telemetry pipelines can group failures by model/framework
// instead of parsing them out of the freeform message string.
void populate_from_structured_error(const rac_error_t* src, ::runanywhere::v1::SDKError& out) {
    if (src == nullptr) {
        return;
    }

    ::runanywhere::v1::ErrorContext* ctx = out.mutable_context();
    auto* metadata = ctx->mutable_metadata();

    if (src->model_id[0] != '\0') {
        (*metadata)["model_id"] = src->model_id;
    }
    if (src->framework[0] != '\0') {
        (*metadata)["framework"] = src->framework;
    }
    if (src->session_id[0] != '\0') {
        (*metadata)["session_id"] = src->session_id;
    }
    if (src->custom_key1[0] != '\0' && src->custom_value1[0] != '\0') {
        (*metadata)[src->custom_key1] = src->custom_value1;
    }
    if (src->custom_key2[0] != '\0' && src->custom_value2[0] != '\0') {
        (*metadata)[src->custom_key2] = src->custom_value2;
    }
    if (src->custom_key3[0] != '\0' && src->custom_value3[0] != '\0') {
        (*metadata)[src->custom_key3] = src->custom_value3;
    }

    if (src->source_file[0] != '\0') {
        ctx->set_source_file(src->source_file);
    }
    if (src->source_line > 0) {
        ctx->set_source_line(src->source_line);
    }
    if (src->source_function[0] != '\0') {
        ctx->set_operation(src->source_function);
    }

    if (src->timestamp_ms != 0) {
        out.set_timestamp_ms(src->timestamp_ms);
    }
    if (src->underlying_message[0] != '\0') {
        out.set_nested_message(src->underlying_message);
    }
}

}  // namespace
#endif  // RAC_HAVE_PROTOBUF

extern "C" {

rac_result_t rac_result_to_proto_error(rac_result_t code, rac_proto_buffer_t* out_proto) {
    if (!out_proto) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

#ifdef RAC_HAVE_PROTOBUF
    ::runanywhere::v1::SDKError error;

    const int32_t signed_code = static_cast<int32_t>(code);
    const int32_t abs_code = signed_code < 0 ? -signed_code : signed_code;
    error.set_code(static_cast<::runanywhere::v1::ErrorCode>(abs_code));
    error.set_category(category_for_code(code));

    const char* message = rac_error_message(code);
    error.set_message(message ? message : "");

    if (signed_code != 0) {
        error.set_c_abi_code(signed_code);
    }
    error.set_severity(::runanywhere::v1::ERROR_SEVERITY_ERROR);

    // If the caller threw a structured `rac_error_t` for this same code on the
    // current thread (the common path through `RAC_RETURN_TRACKED_ERROR_MODEL`
    // / `rac_error_log_and_track_model`), copy its model/framework/session
    // context into the serialized SDKError so consumers can aggregate failures
    // by model without re-parsing the message string. Codes that don't match
    // are ignored (stale / unrelated context).
    const rac_error_t* last = rac_get_last_error();
    if (last != nullptr && last->code == code) {
        populate_from_structured_error(last, error);
    }

    const size_t size = error.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !error.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        rac_proto_buffer_set_error(out_proto, RAC_ERROR_EVENT_PUBLISH_FAILED,
                                   "Failed to serialize SDKError proto");
        return RAC_ERROR_EVENT_PUBLISH_FAILED;
    }

    return rac_proto_buffer_copy(bytes.data(), size, out_proto);
#else
    rac_proto_buffer_set_error(out_proto, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                               "rac_result_to_proto_error requires RAC_HAVE_PROTOBUF");
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#endif
}

}  // extern "C"
