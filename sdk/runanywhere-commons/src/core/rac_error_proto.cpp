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
#include "rac/foundation/rac_proto_adapters.h"
#include "rac/foundation/rac_proto_buffer.h"

#ifdef RAC_HAVE_PROTOBUF
#include "errors.pb.h"
#endif

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
    error.set_category(rac::foundation::rac_result_to_proto_category(code));

    const char* message = rac_error_message(code);
    error.set_message(message ? message : "");

    if (signed_code != 0) {
        error.set_c_abi_code(signed_code);
    }
    error.set_severity(::runanywhere::v1::ERROR_SEVERITY_ERROR);

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
