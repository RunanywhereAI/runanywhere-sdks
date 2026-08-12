/**
 * @file rac_uuid.cpp
 * @brief RFC-4122 version-4 UUID generation (see rac_uuid.h).
 *
 * The format matches the former per-feature generate_uuid() helpers it
 * replaces (8-4-4-4-12 lowercase hex, version '4', variant 8/9/a/b).
 */

#include "rac/core/rac_uuid.h"

#include <random>

#include "rac/core/rac_error.h"

namespace {

constexpr char kHex[] = "0123456789abcdef";

}  // namespace

extern "C" {

rac_result_t rac_uuid_v4(char* out, size_t out_size) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (out_size < 37) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    static thread_local std::mt19937 gen(std::random_device{}());
    static thread_local std::uniform_int_distribution<int> dis(0, 15);

    size_t pos = 0;
    auto emit_hex = [&](int count) {
        for (int i = 0; i < count; ++i) {
            out[pos++] = kHex[dis(gen)];
        }
    };

    // xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx  (y in 8..b)
    emit_hex(8);
    out[pos++] = '-';
    emit_hex(4);
    out[pos++] = '-';
    out[pos++] = '4';
    emit_hex(3);
    out[pos++] = '-';
    out[pos++] = kHex[8 + (dis(gen) % 4)];
    emit_hex(3);
    out[pos++] = '-';
    emit_hex(12);
    out[pos] = '\0';

    return RAC_SUCCESS;
}

}  // extern "C"
