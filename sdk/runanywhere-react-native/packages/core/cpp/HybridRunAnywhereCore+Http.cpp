/**
 * HybridRunAnywhereCore+Http.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

// HTTP Client
// ============================================================================
// HTTP Client — libcurl-backed rac_http_client_*
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhereCore::configureHttp(
    const std::string& baseUrl,
    const std::string& apiKey) {
    return Promise<bool>::async([baseUrl, apiKey]() -> bool {
        HTTPBridge::shared().configure(baseUrl, apiKey);
        return HTTPBridge::shared().isConfigured();
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::httpRequest(
    const std::string& method,
    const std::string& url,
    const std::string& headersJson,
    const std::string& bodyJson,
    double timeoutMs) {
    return Promise<std::string>::async([method, url, headersJson, bodyJson, timeoutMs]() -> std::string {
        auto headers = parseHeadersJson(headersJson);
        NativeHttpResult result = performNativeHttpRequest(
            method, url, headers, bodyJson, static_cast<int32_t>(timeoutMs));

        return buildJsonObject({
            {"status", std::to_string(result.status)},
            {"body", jsonString(result.body)},
            {"headersJson", jsonString(headersToJson(result.headers))}
        });
    });
}

} // namespace margelo::nitro::runanywhere
