/**
 * @file http_default_headers.cpp
 * @brief Single canonical default-header list shared across SDKs.
 *
 * The header values come from `rac_get_version()` (the canonical commons
 * version string defined in `src/core/rac_core.cpp`) plus a hard-coded
 * client brand. Returning a static array gives callers a stable pointer
 * across calls — tests assert pointer equality to confirm zero allocations.
 *
 * "X-Platform" is intentionally NOT in this list. Its value is
 * platform-specific ("ios", "android", "jvm", "web", ...) and must be
 * supplied per-request by the calling SDK.
 */

#include <cstddef>

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/http/rac_http_client.h"

namespace {

// Static brand string — must match Swift's HTTPClientAdapter.defaultHeaders
// (`X-SDK-Client = "RunAnywhereSDK"`) and the Kotlin CppBridgeTelemetry
// equivalent. Hard-coded here so commons is the single source of truth.
constexpr const char* kSdkClientName = "RunAnywhereSDK";

// JSON content-type / accept — also static-string literals.
constexpr const char* kContentTypeJson = "application/json";
constexpr const char* kHeaderContentType = "Content-Type";
constexpr const char* kHeaderAccept = "Accept";
constexpr const char* kHeaderSdkClient = "X-SDK-Client";
constexpr const char* kHeaderSdkVersion = "X-SDK-Version";

// Build the static header array on first call. The version string comes
// from `rac_get_version().string`, which itself points at static storage
// inside rac_core.cpp — so the resulting array stays valid for the
// lifetime of the process.
const rac_http_header_kv_t* default_kvs(size_t* out_count) {
    static const rac_version_t kVersion = rac_get_version();

    static const rac_http_header_kv_t kHeaders[] = {
        {kHeaderSdkClient, kSdkClientName},
        {kHeaderSdkVersion, kVersion.string},
        {kHeaderContentType, kContentTypeJson},
        {kHeaderAccept, kContentTypeJson},
    };

    *out_count = sizeof(kHeaders) / sizeof(kHeaders[0]);
    return kHeaders;
}

}  // namespace

extern "C" rac_result_t rac_http_default_headers(const rac_http_header_kv_t** out_kvs,
                                                 size_t* out_count) {
    if (out_kvs == nullptr || out_count == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out_kvs = default_kvs(out_count);
    return RAC_SUCCESS;
}
