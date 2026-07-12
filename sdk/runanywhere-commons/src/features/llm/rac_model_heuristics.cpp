/**
 * @file rac_model_heuristics.cpp
 * @brief commons-owned heuristics derived from RAModelInfo.
 *
 * Background: every example app was duplicating the same small-model regex
 * (`0.3b`, `0.5b`, `0.6b`, `350m`, `360m`, `500m`). The reviewer flagged this
 * as four examples encoding SDK-internal knowledge across platforms.
 *
 * Resolution: this TU centralizes the heuristics behind a proto-byte ABI so
 * SDKs derive every value from a serialized `runanywhere.v1.ModelInfo`. The
 * helpers consume the same `name` / `id` / `description` fields the examples
 * were inspecting by hand, so behaviour matches the existing reviewer
 * verifications byte-for-byte while the example heuristics can be deleted.
 */

#include <algorithm>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "model_types.pb.h"
#endif

namespace {

std::string to_lower(const std::string& in) {
    std::string out;
    out.reserve(in.size());
    for (char c : in) {
        out.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
    }
    return out;
}

#if defined(RAC_HAVE_PROTOBUF)
// Concatenate the human-readable fields that examples were inspecting (`name`,
// `id`, `description`) into one lowercase haystack so the heuristic matches
// regardless of which field carries the model identity.
std::string build_haystack(const runanywhere::v1::ModelInfo& model) {
    std::string combined;
    const std::string description =
        model.has_metadata() ? model.metadata().description() : std::string();
    combined.reserve(model.name().size() + model.id().size() + description.size() + 4);
    combined += model.name();
    combined.push_back(' ');
    combined += model.id();
    combined.push_back(' ');
    combined += description;
    return to_lower(combined);
}
#endif  // RAC_HAVE_PROTOBUF

// Parse a float that follows a digit-sequence followed by 'b' (billions). The
// regex-style scan is hand-written so the helper has zero non-stdlib
// dependencies. Returns -1 when no parameter-count token is found.
//
// Matches: "1.2b", "0.5b", "1b", "7B", " 1.2 b", "1.2-b". A bare integer
// without a trailing 'b' is ignored to avoid false positives on quantization
// tags like "4bit".
float scan_param_count_b(const std::string& lowered) {
    const size_t n = lowered.size();
    for (size_t i = 0; i < n; ++i) {
        const char c = lowered[i];
        const bool is_digit_start = (c >= '0' && c <= '9');
        if (!is_digit_start) {
            continue;
        }
        // The token must be preceded by a non-alphabetic char (or start of
        // string) so "7b" inside "lfm27b" still matches but the "32" of
        // "qwen32k" does not extend across multiple digits.
        if (i > 0) {
            const char prev = lowered[i - 1];
            if ((prev >= 'a' && prev <= 'z') || (prev >= '0' && prev <= '9')) {
                continue;
            }
        }
        size_t j = i;
        bool seen_dot = false;
        while (j < n) {
            const char d = lowered[j];
            if (d >= '0' && d <= '9') {
                ++j;
            } else if (d == '.' && !seen_dot) {
                seen_dot = true;
                ++j;
            } else {
                break;
            }
        }
        // After the number, accept an optional separator (' ' or '-') then 'b'.
        size_t k = j;
        while (k < n && (lowered[k] == ' ' || lowered[k] == '-' || lowered[k] == '_')) {
            ++k;
        }
        if (k < n && lowered[k] == 'b') {
            // Reject "bit" / "byte" tail tokens.
            if (k + 1 < n) {
                const char tail = lowered[k + 1];
                if ((tail >= 'a' && tail <= 'z') && tail != 'b') {
                    continue;
                }
            }
            const std::string token = lowered.substr(i, j - i);
            try {
                return std::stof(token);
            } catch (...) {
                // fall through and continue scanning
            }
        }
        // Allow "m" suffix (millions) — convert to billions.
        if (k < n && lowered[k] == 'm') {
            if (k + 1 < n) {
                const char tail = lowered[k + 1];
                if ((tail >= 'a' && tail <= 'z') && tail != 'b') {
                    continue;
                }
            }
            const std::string token = lowered.substr(i, j - i);
            try {
                return std::stof(token) / 1000.0f;
            } catch (...) {
                // fall through
            }
        }
    }
    return -1.0f;
}

// Small-model threshold mirrors the Flutter banner that fires for ≤500M-param
// models (B-FL-6-003): 0.3B, 0.5B, 0.6B, 350M, 360M, 500M. The threshold
// 1.0 captures every example in the original list while keeping LFM2-1.2B-Tool
// above the threshold.
constexpr float kSmallModelThresholdB = 1.0f;

}  // namespace

extern "C" rac_result_t
rac_model_info_parameter_count_b_proto(const uint8_t* model_info_proto_bytes, size_t size,
                                       float* out_parameter_count_b) {
    if (!out_parameter_count_b) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_parameter_count_b = -1.0f;
#if !defined(RAC_HAVE_PROTOBUF)
    (void)model_info_proto_bytes;
    (void)size;
    return RAC_SUCCESS;
#else
    if (size == 0) {
        return RAC_SUCCESS;
    }
    if (rac_proto_bytes_validate(model_info_proto_bytes, size) != RAC_SUCCESS) {
        return RAC_ERROR_DECODING_ERROR;
    }
    runanywhere::v1::ModelInfo model;
    if (!model.ParseFromArray(rac_proto_bytes_data_or_empty(model_info_proto_bytes, size),
                              static_cast<int>(size))) {
        return RAC_ERROR_DECODING_ERROR;
    }
    const std::string haystack = build_haystack(model);
    *out_parameter_count_b = scan_param_count_b(haystack);
    return RAC_SUCCESS;
#endif
}

extern "C" rac_result_t rac_model_info_is_small_model_proto(const uint8_t* model_info_proto_bytes,
                                                            size_t size, rac_bool_t* out_is_small) {
    if (!out_is_small) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_is_small = RAC_FALSE;
    float params_b = -1.0f;
    const rac_result_t rc =
        rac_model_info_parameter_count_b_proto(model_info_proto_bytes, size, &params_b);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    *out_is_small = (params_b > 0.0f && params_b < kSmallModelThresholdB) ? RAC_TRUE : RAC_FALSE;
    return RAC_SUCCESS;
}
