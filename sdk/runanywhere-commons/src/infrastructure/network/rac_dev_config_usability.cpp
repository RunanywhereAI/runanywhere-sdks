/**
 * @file rac_dev_config_usability.cpp
 * @brief Canonical dev-config usability checks shared by all SDKs.
 *
 * The placeholder-detection and http(s)-URL-shape logic was independently
 * re-implemented in every SDK (Swift / Kotlin / Flutter / React Native), with
 * at least one divergent copy. Hosting it here behind the C ABI lets each SDK
 * drop its bespoke regex and call one source of truth. Pure logic, no secrets,
 * so it lives outside the git-ignored development_config.cpp.
 */

#include <cctype>
#include <string>

#include "rac/infrastructure/network/rac_dev_config.h"

namespace {

std::string dev_trim(const char* value) {
    if (!value)
        return std::string();
    std::string text(value);
    const size_t start = text.find_first_not_of(" \t\r\n");
    if (start == std::string::npos)
        return std::string();
    const size_t end = text.find_last_not_of(" \t\r\n");
    return text.substr(start, end - start + 1);
}

std::string dev_lowercase(std::string text) {
    for (char& c : text)
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return text;
}

}  // namespace

extern "C" {

bool rac_dev_config_is_usable_credential(const char* value) {
    const std::string normalized = dev_lowercase(dev_trim(value));
    if (normalized.empty())
        return false;
    return normalized.find("your_") == std::string::npos &&
           normalized.find("<your") == std::string::npos &&
           normalized.find("replace_me") == std::string::npos &&
           normalized.find("placeholder") == std::string::npos;
}

bool rac_dev_config_is_usable_http_url(const char* value) {
    const std::string url = dev_trim(value);
    if (!rac_dev_config_is_usable_credential(url.c_str()))
        return false;
    const std::string normalized = dev_lowercase(url);
    const bool has_scheme =
        normalized.rfind("https://", 0) == 0 || normalized.rfind("http://", 0) == 0;
    if (!has_scheme)
        return false;
    const size_t scheme_end = url.find("://");
    if (scheme_end == std::string::npos)
        return false;
    const size_t host_start = scheme_end + 3;
    const size_t host_end = url.find_first_of("/?#", host_start);
    const std::string host = url.substr(host_start, host_end - host_start);
    return !host.empty() && host.find_first_of(" \t\r\n<>") == std::string::npos;
}

}  // extern "C"
