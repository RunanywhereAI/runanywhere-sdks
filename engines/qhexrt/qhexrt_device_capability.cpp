/**
 * @file qhexrt_device_capability.cpp
 * @brief QHexRT-owned Snapdragon/Hexagon capability probe.
 */

#include <cstdio>
#include <cstring>
#include <vector>

#include "rac/qhexrt/rac_qhexrt.h"

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

#if defined(RAC_QHEXRT_HAVE_PROTOBUF)
#include "hardware_profile.pb.h"

static_assert(static_cast<int32_t>(RAC_QHEXRT_HEXAGON_ARCH_UNKNOWN) ==
              static_cast<int32_t>(runanywhere::v1::HEXAGON_ARCH_UNKNOWN));
static_assert(static_cast<int32_t>(RAC_QHEXRT_HEXAGON_ARCH_V68) ==
              static_cast<int32_t>(runanywhere::v1::HEXAGON_ARCH_V68));
static_assert(static_cast<int32_t>(RAC_QHEXRT_HEXAGON_ARCH_V69) ==
              static_cast<int32_t>(runanywhere::v1::HEXAGON_ARCH_V69));
static_assert(static_cast<int32_t>(RAC_QHEXRT_HEXAGON_ARCH_V73) ==
              static_cast<int32_t>(runanywhere::v1::HEXAGON_ARCH_V73));
static_assert(static_cast<int32_t>(RAC_QHEXRT_HEXAGON_ARCH_V75) ==
              static_cast<int32_t>(runanywhere::v1::HEXAGON_ARCH_V75));
static_assert(static_cast<int32_t>(RAC_QHEXRT_HEXAGON_ARCH_V79) ==
              static_cast<int32_t>(runanywhere::v1::HEXAGON_ARCH_V79));
static_assert(static_cast<int32_t>(RAC_QHEXRT_HEXAGON_ARCH_V81) ==
              static_cast<int32_t>(runanywhere::v1::HEXAGON_ARCH_V81));
#endif

namespace {

struct SocArchEntry {
    const char* model;
    rac_qhexrt_hexagon_arch_t arch;
};

constexpr SocArchEntry kSocArchTable[] = {
    {"SM8850", RAC_QHEXRT_HEXAGON_ARCH_V81}, {"SM8750", RAC_QHEXRT_HEXAGON_ARCH_V79},
    {"SM8650", RAC_QHEXRT_HEXAGON_ARCH_V75}, {"SM8550", RAC_QHEXRT_HEXAGON_ARCH_V73},
    {"SM7675", RAC_QHEXRT_HEXAGON_ARCH_V73}, {"SM7635", RAC_QHEXRT_HEXAGON_ARCH_V73},
    {"SM8475", RAC_QHEXRT_HEXAGON_ARCH_V69}, {"SM8450", RAC_QHEXRT_HEXAGON_ARCH_V69},
};

constexpr SocArchEntry kBoardArchTable[] = {
    {"SUN", RAC_QHEXRT_HEXAGON_ARCH_V79},
    {"PINEAPPLE", RAC_QHEXRT_HEXAGON_ARCH_V75},
    {"KALAMA", RAC_QHEXRT_HEXAGON_ARCH_V73},
};

void to_upper(char* value) {
    for (; *value != '\0'; ++value) {
        if (*value >= 'a' && *value <= 'z') {
            *value = static_cast<char>(*value - ('a' - 'A'));
        }
    }
}

rac_qhexrt_hexagon_arch_t lookup(const SocArchEntry* table, size_t count, const char* upper_key) {
    for (size_t index = 0; index < count; ++index) {
        if (std::strcmp(table[index].model, upper_key) == 0) {
            return table[index].arch;
        }
    }
    return RAC_QHEXRT_HEXAGON_ARCH_UNKNOWN;
}

#if defined(__ANDROID__)
int read_property(const char* name, char* out, size_t out_size) {
    if (out_size == 0) {
        return 0;
    }
    out[0] = '\0';
    char value[PROP_VALUE_MAX] = {0};
    const int length = __system_property_get(name, value);
    if (length <= 0) {
        return 0;
    }
    std::snprintf(out, out_size, "%s", value);
    return static_cast<int>(std::strlen(out));
}

int32_t read_soc_id() {
    std::FILE* file = std::fopen("/sys/devices/soc0/soc_id", "r");
    if (file == nullptr) {
        return -1;
    }
    long id = -1;
    if (std::fscanf(file, "%ld", &id) != 1) {
        id = -1;
    }
    std::fclose(file);
    return static_cast<int32_t>(id);
}
#endif

}  // namespace

extern "C" {

rac_bool_t rac_qhexrt_arch_is_supported(rac_qhexrt_hexagon_arch_t arch) {
    switch (arch) {
        case RAC_QHEXRT_HEXAGON_ARCH_V75:
        case RAC_QHEXRT_HEXAGON_ARCH_V79:
        case RAC_QHEXRT_HEXAGON_ARCH_V81:
            return RAC_TRUE;
        case RAC_QHEXRT_HEXAGON_ARCH_UNKNOWN:
        case RAC_QHEXRT_HEXAGON_ARCH_V68:
        case RAC_QHEXRT_HEXAGON_ARCH_V69:
        case RAC_QHEXRT_HEXAGON_ARCH_V73:
        default:
            return RAC_FALSE;
    }
}

const char* rac_qhexrt_arch_name(rac_qhexrt_hexagon_arch_t arch) {
    switch (arch) {
        case RAC_QHEXRT_HEXAGON_ARCH_V68:
            return "v68";
        case RAC_QHEXRT_HEXAGON_ARCH_V69:
            return "v69";
        case RAC_QHEXRT_HEXAGON_ARCH_V73:
            return "v73";
        case RAC_QHEXRT_HEXAGON_ARCH_V75:
            return "v75";
        case RAC_QHEXRT_HEXAGON_ARCH_V79:
            return "v79";
        case RAC_QHEXRT_HEXAGON_ARCH_V81:
            return "v81";
        case RAC_QHEXRT_HEXAGON_ARCH_UNKNOWN:
        default:
            return "unknown";
    }
}

rac_result_t rac_qhexrt_probe(rac_qhexrt_device_info_t* out) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    std::memset(out, 0, sizeof(*out));
    out->soc_id = -1;
    out->hexagon_arch = RAC_QHEXRT_HEXAGON_ARCH_UNKNOWN;

#if defined(__ANDROID__)
    read_property("ro.soc.model", out->soc_model, sizeof(out->soc_model));
    out->soc_id = read_soc_id();

    char key[sizeof(out->soc_model)] = {0};
    std::snprintf(key, sizeof(key), "%s", out->soc_model);
    to_upper(key);
    out->hexagon_arch =
        lookup(kSocArchTable, sizeof(kSocArchTable) / sizeof(kSocArchTable[0]), key);

    if (out->hexagon_arch == RAC_QHEXRT_HEXAGON_ARCH_UNKNOWN) {
        char board[PROP_VALUE_MAX] = {0};
        if (read_property("ro.board.platform", board, sizeof(board)) > 0) {
            to_upper(board);
            out->hexagon_arch = lookup(kBoardArchTable,
                                       sizeof(kBoardArchTable) / sizeof(kBoardArchTable[0]), board);
        }
    }
#endif

    out->supported = rac_qhexrt_arch_is_supported(out->hexagon_arch);
    return RAC_SUCCESS;
}

rac_result_t rac_qhexrt_probe_proto(rac_proto_buffer_t* out_capability) {
    if (out_capability == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
#if defined(RAC_QHEXRT_HAVE_PROTOBUF)
    rac_qhexrt_device_info_t info{};
    const rac_result_t probe_rc = rac_qhexrt_probe(&info);
    if (probe_rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_capability, probe_rc, "QHexRT device probe failed");
    }

    runanywhere::v1::NpuCapability capability;
    capability.set_soc_model(info.soc_model);
    capability.set_soc_id(info.soc_id);
    capability.set_hexagon_arch(
        static_cast<runanywhere::v1::HexagonArch>(static_cast<int32_t>(info.hexagon_arch)));
    capability.set_qhexrt_supported(info.supported == RAC_TRUE);
    capability.set_arch_name(rac_qhexrt_arch_name(info.hexagon_arch));

    std::vector<uint8_t> bytes(capability.ByteSizeLong());
    if (!bytes.empty() &&
        !capability.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return rac_proto_buffer_set_error(out_capability, RAC_ERROR_ENCODING_ERROR,
                                          "Failed to serialize QHexRT NpuCapability");
    }
    return rac_proto_buffer_copy(bytes.data(), bytes.size(), out_capability);
#else
    return rac_proto_buffer_set_error(out_capability, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "QHexRT NpuCapability requires protobuf support");
#endif
}

}  // extern "C"
