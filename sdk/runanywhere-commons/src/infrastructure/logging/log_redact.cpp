/**
 * @file log_redact.cpp
 * @brief Centralized log-metadata redaction policy.
 *
 * Mirrors the sanitizer in Swift's `SDKLogger.swift` so that C++ and platform
 * logs apply the same rule: a metadata key is redacted iff its lowercased form
 * contains any of the canonical sensitive substrings.
 *
 * Keep the substring list in lockstep with:
 *   sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Logging/SDKLogger.swift
 *   (search for `sensitivePatterns`)
 */

#include <cctype>
#include <cstring>
#include <string_view>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"

namespace {

// Canonical sensitive-substring list. Lowercase, in declaration order; both
// the C++ logger and Swift `SDKLogger` honor exactly this set.
constexpr std::string_view kSensitiveSubstrings[] = {
    "key", "secret", "password", "token", "auth", "credential",
};

inline bool ascii_contains_ci(std::string_view haystack, std::string_view needle) {
    if (needle.empty()) {
        return true;
    }
    if (haystack.size() < needle.size()) {
        return false;
    }
    const size_t span = haystack.size() - needle.size();
    for (size_t i = 0; i <= span; ++i) {
        bool match = true;
        for (size_t j = 0; j < needle.size(); ++j) {
            const unsigned char hc = static_cast<unsigned char>(haystack[i + j]);
            const unsigned char nc = static_cast<unsigned char>(needle[j]);
            if (std::tolower(hc) != std::tolower(nc)) {
                match = false;
                break;
            }
        }
        if (match) {
            return true;
        }
    }
    return false;
}

}  // namespace

extern "C" rac_result_t rac_log_metadata_should_redact(const char* key, rac_bool_t* out) {
    if (key == nullptr || out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    const std::string_view key_view{key, std::strlen(key)};
    for (const std::string_view& pattern : kSensitiveSubstrings) {
        if (ascii_contains_ci(key_view, pattern)) {
            *out = RAC_TRUE;
            return RAC_SUCCESS;
        }
    }
    *out = RAC_FALSE;
    return RAC_SUCCESS;
}
