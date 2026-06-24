/**
 * @file rac_npu_capability.cpp
 * @brief Pre-flight Hexagon NPU capability probe (see rac_npu_capability.h).
 */

#include "rac/infrastructure/device/rac_npu_capability.h"

#include <cstdio>
#include <cstring>

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

namespace {

// SoC model -> Hexagon architecture. Keyed by the `ro.soc.model` string
// (Android API 31+). Only the entries the SDK cares about are listed; any
// unlisted SoC resolves to UNKNOWN and is treated as unsupported (CPU
// fallback). QHexRT context binaries are arch-exact, so the supported set is
// deliberately limited to v79/v81.
struct SocArchEntry {
    const char* model;  // exact ro.soc.model value, upper-case
    rac_hexagon_arch_t arch;
};

constexpr SocArchEntry kSocArchTable[] = {
    {"SM8850", RAC_HEXAGON_ARCH_V81},  // Snapdragon 8 Elite Gen 5
    {"SM8750", RAC_HEXAGON_ARCH_V79},  // Snapdragon 8 Elite
    {"SM8650", RAC_HEXAGON_ARCH_V75},  // Snapdragon 8 Gen 3
    {"SM8550", RAC_HEXAGON_ARCH_V73},  // Snapdragon 8 Gen 2
    {"SM7675", RAC_HEXAGON_ARCH_V73},  // Snapdragon 7+ Gen 3
    {"SM7635", RAC_HEXAGON_ARCH_V73},  // Snapdragon 7s Gen 3
    {"SM8475", RAC_HEXAGON_ARCH_V69},  // Snapdragon 8+ Gen 1
    {"SM8450", RAC_HEXAGON_ARCH_V69},  // Snapdragon 8 Gen 1
};

// Fallback keyed by `ro.board.platform` codename when ro.soc.model is empty.
constexpr SocArchEntry kBoardArchTable[] = {
    {"SUN", RAC_HEXAGON_ARCH_V79},        // SM8750
    {"PINEAPPLE", RAC_HEXAGON_ARCH_V75},  // SM8650
    {"KALAMA", RAC_HEXAGON_ARCH_V73},     // SM8550
};

void to_upper(char* s) {
    for (; *s != '\0'; ++s) {
        if (*s >= 'a' && *s <= 'z') {
            *s = static_cast<char>(*s - ('a' - 'A'));
        }
    }
}

rac_hexagon_arch_t lookup(const SocArchEntry* table, size_t count, const char* upper_key) {
    for (size_t i = 0; i < count; ++i) {
        if (std::strcmp(table[i].model, upper_key) == 0) {
            return table[i].arch;
        }
    }
    return RAC_HEXAGON_ARCH_UNKNOWN;
}

#if defined(__ANDROID__)
// Reads a system property into out (NUL-terminated). Returns length, 0 if unset.
int read_property(const char* name, char* out, size_t out_size) {
    if (out_size == 0) {
        return 0;
    }
    out[0] = '\0';
    char value[PROP_VALUE_MAX] = {0};
    int len = __system_property_get(name, value);
    if (len <= 0) {
        return 0;
    }
    std::snprintf(out, out_size, "%s", value);
    return static_cast<int>(std::strlen(out));
}

int32_t read_soc_id() {
    std::FILE* f = std::fopen("/sys/devices/soc0/soc_id", "r");
    if (f == nullptr) {
        return -1;
    }
    long id = -1;
    if (std::fscanf(f, "%ld", &id) != 1) {
        id = -1;
    }
    std::fclose(f);
    return static_cast<int32_t>(id);
}
#endif  // __ANDROID__

}  // namespace

extern "C" {

rac_result_t rac_npu_probe(rac_npu_info_t* out) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    std::memset(out, 0, sizeof(*out));
    out->soc_id = -1;
    out->hexagon_arch = RAC_HEXAGON_ARCH_UNKNOWN;
    out->qhexrt_supported = RAC_FALSE;

#if defined(__ANDROID__)
    read_property("ro.soc.model", out->soc_model, sizeof(out->soc_model));
    out->soc_id = read_soc_id();

    char key[sizeof(out->soc_model)];
    std::snprintf(key, sizeof(key), "%s", out->soc_model);
    to_upper(key);
    out->hexagon_arch = lookup(kSocArchTable, sizeof(kSocArchTable) / sizeof(kSocArchTable[0]), key);

    if (out->hexagon_arch == RAC_HEXAGON_ARCH_UNKNOWN) {
        char board[PROP_VALUE_MAX] = {0};
        if (read_property("ro.board.platform", board, sizeof(board)) > 0) {
            to_upper(board);
            out->hexagon_arch =
                lookup(kBoardArchTable, sizeof(kBoardArchTable) / sizeof(kBoardArchTable[0]), board);
        }
    }
#endif  // __ANDROID__

    out->qhexrt_supported = (out->hexagon_arch == RAC_HEXAGON_ARCH_V79 ||
                             out->hexagon_arch == RAC_HEXAGON_ARCH_V81)
                                ? RAC_TRUE
                                : RAC_FALSE;
    return RAC_SUCCESS;
}

const char* rac_hexagon_arch_name(rac_hexagon_arch_t arch) {
    switch (arch) {
        case RAC_HEXAGON_ARCH_V68:
            return "v68";
        case RAC_HEXAGON_ARCH_V69:
            return "v69";
        case RAC_HEXAGON_ARCH_V73:
            return "v73";
        case RAC_HEXAGON_ARCH_V75:
            return "v75";
        case RAC_HEXAGON_ARCH_V79:
            return "v79";
        case RAC_HEXAGON_ARCH_V81:
            return "v81";
        case RAC_HEXAGON_ARCH_UNKNOWN:
        default:
            return "unknown";
    }
}

}  // extern "C"
