/**
 * ExternalConfigGuard.hpp
 *
 * Shared native guards for auth, telemetry, and device-registration endpoints.
 * Platform code can provide HTTP transport, but the decision to use external
 * network config belongs in C++ so JS/Swift/Kotlin wrappers stay thin.
 */

#pragma once

#include <algorithm>
#include <cctype>
#include <string>

namespace runanywhere {
namespace bridges {
namespace config {

inline std::string trim(std::string value) {
    auto isSpace = [](unsigned char c) {
        return std::isspace(c) != 0;
    };

    value.erase(value.begin(), std::find_if(value.begin(), value.end(), [&](char c) {
                    return !isSpace(static_cast<unsigned char>(c));
                }));
    value.erase(std::find_if(value.rbegin(), value.rend(), [&](char c) {
                    return !isSpace(static_cast<unsigned char>(c));
                }).base(),
                value.end());
    return value;
}

inline std::string lowercase(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

inline bool looksLikePlaceholder(const std::string& rawValue) {
    std::string value = lowercase(trim(rawValue));
    if (value.empty()) {
        return true;
    }

    return value.find("your_") != std::string::npos ||
           value.find("<your") != std::string::npos ||
           value.find("replace_me") != std::string::npos ||
           value.find("placeholder") != std::string::npos;
}

inline bool isUsableSecret(const std::string& rawValue) {
    return !looksLikePlaceholder(rawValue);
}

inline bool isUsableHttpUrl(const std::string& rawValue) {
    std::string value = trim(rawValue);
    if (looksLikePlaceholder(value)) {
        return false;
    }

    std::string lower = lowercase(value);
    const bool hasScheme =
        lower.rfind("https://", 0) == 0 || lower.rfind("http://", 0) == 0;
    if (!hasScheme) {
        return false;
    }

    const size_t schemeEnd = value.find("://");
    if (schemeEnd == std::string::npos) {
        return false;
    }

    const size_t hostStart = schemeEnd + 3;
    const size_t hostEnd = value.find_first_of("/?#", hostStart);
    const std::string host = value.substr(hostStart, hostEnd - hostStart);
    return !host.empty() && host.find_first_of(" \t\r\n<>") == std::string::npos;
}

struct ExternalEndpointConfig {
    bool usable = false;
    std::string baseURL;
    std::string token;
};

inline ExternalEndpointConfig makeEndpointConfig(
    const std::string& baseURL,
    const std::string& token
) {
    ExternalEndpointConfig config;
    config.baseURL = trim(baseURL);
    config.token = trim(token);
    config.usable = isUsableHttpUrl(config.baseURL) && isUsableSecret(config.token);
    return config;
}

inline std::string appendEndpointPath(std::string baseURL, const std::string& endpointPath) {
    while (!baseURL.empty() && baseURL.back() == '/') {
        baseURL.pop_back();
    }
    if (!endpointPath.empty() && endpointPath.front() == '/') {
        return baseURL + endpointPath;
    }
    return baseURL + "/" + endpointPath;
}

} // namespace config
} // namespace bridges
} // namespace runanywhere
