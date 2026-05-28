/**
 * @file rac_hardware_abi.cpp
 * @brief C ABI for hardware profile queries (proto-serialised results).
 *
 * Implements rac_hardware_profile_get / rac_hardware_profile_free /
 * rac_hardware_get_accelerators / rac_hardware_set_accelerator_preference
 * declared in rac_hardware_abi.h.
 *
 * The implementation builds a hand-encoded protobuf binary using field tags
 * that match hardware_profile.proto (idl/).  We do NOT depend on protoc-
 * generated code here so that this TU compiles without the protoc step —
 * each SDK frontend decodes with its own generated classes.
 *
 * Proto field numbers used (must stay in sync with hardware_profile.proto):
 *   HardwareProfile: chip=1, has_neural_engine=2, acceleration_mode=3,
 *     total_memory_bytes=4, core_count=5, performance_cores=6,
 *     efficiency_cores=7, architecture=8, platform=9, npu_chip=10.
 *   HardwareProfileResult: profile=1, accelerators=2.
 *   AcceleratorInfo: name=1, type=2, available=3.
 */

#include "rac/router/rac_hardware_abi.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#if defined(__linux__) || defined(__ANDROID__)
#include <unistd.h>  // sysconf / _SC_NPROCESSORS_ONLN
#endif
#if defined(__APPLE__)
#include <sys/sysctl.h>  // sysctlbyname
#endif

#include "accelerator_preference_internal.h"

#include <atomic>

#include "rac/core/rac_logger.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/router/rac_hardware_profile.h"

// ============================================================================
// Minimal hand-encoded protobuf helpers
// ============================================================================

namespace {

// Wire types
static constexpr uint8_t WIRE_VARINT = 0;
static constexpr uint8_t WIRE_LEN = 2;

static void encode_tag(std::vector<uint8_t>& buf, uint32_t field_number, uint8_t wire_type) {
    uint32_t tag = (field_number << 3) | wire_type;
    while (tag > 0x7F) {
        buf.push_back(static_cast<uint8_t>((tag & 0x7F) | 0x80));
        tag >>= 7;
    }
    buf.push_back(static_cast<uint8_t>(tag));
}

static void encode_varint(std::vector<uint8_t>& buf, uint64_t v) {
    while (v > 0x7F) {
        buf.push_back(static_cast<uint8_t>((v & 0x7F) | 0x80));
        v >>= 7;
    }
    buf.push_back(static_cast<uint8_t>(v));
}

static void encode_string_field(std::vector<uint8_t>& buf, uint32_t field_number,
                                const std::string& s) {
    if (s.empty())
        return;
    encode_tag(buf, field_number, WIRE_LEN);
    encode_varint(buf, s.size());
    buf.insert(buf.end(), s.begin(), s.end());
}

static void encode_bool_field(std::vector<uint8_t>& buf, uint32_t field_number, bool v) {
    if (!v)
        return;  // default false — omit for compactness
    encode_tag(buf, field_number, WIRE_VARINT);
    encode_varint(buf, v ? 1 : 0);
}

static void encode_uint64_field(std::vector<uint8_t>& buf, uint32_t field_number, uint64_t v) {
    if (v == 0)
        return;
    encode_tag(buf, field_number, WIRE_VARINT);
    encode_varint(buf, v);
}

static void encode_uint32_field(std::vector<uint8_t>& buf, uint32_t field_number, uint32_t v) {
    if (v == 0)
        return;
    encode_tag(buf, field_number, WIRE_VARINT);
    encode_varint(buf, v);
}

static void encode_bytes_field(std::vector<uint8_t>& buf, uint32_t field_number,
                               const std::vector<uint8_t>& nested) {
    if (nested.empty())
        return;
    encode_tag(buf, field_number, WIRE_LEN);
    encode_varint(buf, nested.size());
    buf.insert(buf.end(), nested.begin(), nested.end());
}

// ============================================================================
// Platform-specific chip / architecture / platform string helpers
// ============================================================================

#if defined(__APPLE__)
#include <TargetConditionals.h>

static std::string apple_platform_string() {
#if TARGET_OS_IOS
    return "ios";
#elif TARGET_OS_OSX
    return "macos";
#elif TARGET_OS_TV
    return "tvos";
#elif TARGET_OS_WATCH
    return "watchos";
#else
    return "apple";
#endif
}
#endif

#if defined(__ANDROID__)
#include <sys/system_properties.h>
static std::string android_property(const char* key) {
    char buf[PROP_VALUE_MAX] = {};
    if (__system_property_get(key, buf) <= 0)
        return {};
    return std::string(buf);
}
#endif

// ============================================================================
// Chip / SoC string → NPUChip vendor classifier
// ============================================================================
//
// Single source of truth for the chip-name → NPU vendor mapping (previously
// duplicated in the RN JS facade as `mapChipStringToNPUChip`). Values match
// `runanywhere.v1.NPUChip` in storage_types.proto:
//   UNSPECIFIED=0, NONE=1, APPLE_NEURAL_ENGINE=2, QUALCOMM_HEXAGON=3,
//   MEDIATEK_APU=4, GOOGLE_TPU=5, INTEL_NPU=6, OTHER=99.

static constexpr int NPU_CHIP_UNSPECIFIED = 0;
static constexpr int NPU_CHIP_NONE = 1;
static constexpr int NPU_CHIP_APPLE_NEURAL_ENGINE = 2;
static constexpr int NPU_CHIP_QUALCOMM_HEXAGON = 3;
static constexpr int NPU_CHIP_MEDIATEK_APU = 4;
static constexpr int NPU_CHIP_GOOGLE_TPU = 5;
static constexpr int NPU_CHIP_INTEL_NPU = 6;
static constexpr int NPU_CHIP_OTHER = 99;

static bool npu_contains(const std::string& haystack, const char* needle) {
    return haystack.find(needle) != std::string::npos;
}

static bool npu_starts_with(const std::string& s, const char* prefix) {
    return s.rfind(prefix, 0) == 0;
}

// Word-boundary match for Apple model codes: a single `[aA]<n>` / `[mM]<n>`
// token where `n` is in [lo, hi]. Mirrors the RN regexes
// /\ba(?:[1-9]|1[0-9])\b/ (A1..A19) and /\bm[1-9]\b/ (M1..M9): the letter must
// not be preceded by an alphanumeric, and the trailing digits must not be
// followed by an alphanumeric.
static bool npu_has_model_code(const std::string& s, char letter, int lo, int hi) {
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] != letter)
            continue;
        bool left_boundary = (i == 0) || !std::isalnum(static_cast<unsigned char>(s[i - 1]));
        if (!left_boundary)
            continue;
        size_t j = i + 1;
        if (j >= s.size() || !std::isdigit(static_cast<unsigned char>(s[j])))
            continue;
        size_t digit_start = j;
        while (j < s.size() && std::isdigit(static_cast<unsigned char>(s[j])))
            ++j;
        bool right_boundary = (j >= s.size()) || !std::isalnum(static_cast<unsigned char>(s[j]));
        if (!right_boundary)
            continue;
        int num = std::atoi(s.substr(digit_start, j - digit_start).c_str());
        if (num >= lo && num <= hi)
            return true;
    }
    return false;
}

// Map a free-form chip/SoC string to the NPUChip vendor enum. Returns
// NPU_CHIP_UNSPECIFIED when the string is empty or matches no known vendor.
static int map_chip_string_to_npu(const std::string& chip) {
    std::string lower;
    lower.reserve(chip.size());
    for (char c : chip)
        lower.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
    // Trim surrounding whitespace.
    const auto first = lower.find_first_not_of(" \t\r\n");
    if (first == std::string::npos)
        return NPU_CHIP_UNSPECIFIED;
    const auto last = lower.find_last_not_of(" \t\r\n");
    lower = lower.substr(first, last - first + 1);

    if (npu_contains(lower, "apple") || npu_has_model_code(lower, 'a', 1, 19) ||
        npu_has_model_code(lower, 'm', 1, 9)) {
        return NPU_CHIP_APPLE_NEURAL_ENGINE;
    }
    if (npu_contains(lower, "snapdragon") || npu_contains(lower, "qualcomm") ||
        npu_contains(lower, "hexagon") || npu_starts_with(lower, "sdm") ||
        npu_starts_with(lower, "sm8") || npu_starts_with(lower, "sm7") ||
        npu_starts_with(lower, "sm6") || npu_starts_with(lower, "msm")) {
        return NPU_CHIP_QUALCOMM_HEXAGON;
    }
    if (npu_contains(lower, "mediatek") || npu_contains(lower, "dimensity") ||
        npu_contains(lower, "helio") || npu_starts_with(lower, "mt6") ||
        npu_starts_with(lower, "mt8")) {
        return NPU_CHIP_MEDIATEK_APU;
    }
    if (npu_contains(lower, "tensor") || npu_contains(lower, "pixel") ||
        npu_starts_with(lower, "gs1") || npu_starts_with(lower, "gs2") ||
        npu_starts_with(lower, "gs3")) {
        return NPU_CHIP_GOOGLE_TPU;
    }
    if (npu_contains(lower, "intel") || npu_contains(lower, "core ultra") ||
        npu_contains(lower, "meteor lake") || npu_contains(lower, "lunar lake") ||
        npu_contains(lower, "arrow lake")) {
        return NPU_CHIP_INTEL_NPU;
    }
    if (npu_contains(lower, "exynos") || npu_starts_with(lower, "s5e") ||
        npu_contains(lower, "samsung") || npu_contains(lower, "kirin") ||
        npu_contains(lower, "hisilicon")) {
        return NPU_CHIP_OTHER;
    }
    return NPU_CHIP_UNSPECIFIED;
}

// Resolve the NPUChip enum for the profile: classify the chip string, then
// fall back to NONE / OTHER based on neural-engine presence. Mirrors the RN
// getNPUChip() gating: a mapped vendor wins; otherwise a present NPU (ANE on
// Apple, QNN/Hexagon on Android) reports OTHER and absence reports NONE.
static int resolve_npu_chip(const rac::router::HardwareProfile& hp, const std::string& chip) {
    int mapped = map_chip_string_to_npu(chip);
    if (mapped != NPU_CHIP_UNSPECIFIED)
        return mapped;
    if (hp.has_ane || hp.has_qnn)
        return NPU_CHIP_OTHER;
    return NPU_CHIP_NONE;
}

// ============================================================================
// Build HardwareProfile proto bytes from the cached HardwareProfile struct
// ============================================================================

static std::vector<uint8_t> build_hardware_profile_bytes(const rac::router::HardwareProfile& hp) {
    std::vector<uint8_t> buf;

    // field 1: chip (string)
    std::string chip = hp.apple_chip_gen;
#if defined(__ANDROID__)
    if (chip.empty()) {
        chip = android_property("ro.hardware.chipname");
        if (chip.empty())
            chip = android_property("ro.board.platform");
    }
#endif
    encode_string_field(buf, 1, chip);

    // field 2: has_neural_engine (bool)
    encode_bool_field(buf, 2, hp.has_ane);

    // field 3: acceleration_mode (string) — "ane" > "gpu" > "cpu"
    std::string accel_mode;
    if (hp.has_ane) {
        accel_mode = "ane";
    } else if (hp.has_metal || hp.has_cuda || hp.has_vulkan || hp.has_nnapi) {
        accel_mode = "gpu";
    } else {
        accel_mode = "cpu";
    }
    encode_string_field(buf, 3, accel_mode);

    // field 4: total_memory_bytes (uint64)
    encode_uint64_field(buf, 4, static_cast<uint64_t>(hp.total_ram_bytes));

    // fields 5,6,7: core_count, performance_cores, efficiency_cores
    // We source these from sysctl on Apple, /proc/cpuinfo on Linux/Android.
#if defined(__APPLE__)
    {
        uint32_t ncpu = 0;
        size_t sz = sizeof(ncpu);
        sysctlbyname("hw.logicalcpu", &ncpu, &sz, nullptr, 0);
        uint32_t perf = 0, eff = 0;
        sysctlbyname("hw.perflevel0.logicalcpu", &perf, &sz, nullptr, 0);
        sysctlbyname("hw.perflevel1.logicalcpu", &eff, &sz, nullptr, 0);
        encode_uint32_field(buf, 5, ncpu);
        encode_uint32_field(buf, 6, perf);
        encode_uint32_field(buf, 7, eff);
    }
#elif defined(__linux__) || defined(__ANDROID__)
    {
        long ncpu = sysconf(_SC_NPROCESSORS_ONLN);
        if (ncpu > 0) {
            encode_uint32_field(buf, 5, static_cast<uint32_t>(ncpu));
        }
    }
#endif

    // field 8: architecture (string)
    std::string arch;
#if defined(__aarch64__) || defined(_M_ARM64)
    arch = "arm64";
#elif defined(__x86_64__) || defined(_M_X64)
    arch = "x86_64";
#elif defined(__EMSCRIPTEN__)
    arch = "wasm32";
#elif defined(__arm__)
    arch = "arm";
#else
    arch = "unknown";
#endif
    encode_string_field(buf, 8, arch);

    // field 9: platform (string)
    std::string platform;
#if defined(__APPLE__)
    platform = apple_platform_string();
#elif defined(__ANDROID__)
    platform = "android";
#elif defined(__EMSCRIPTEN__)
    platform = "web";
#elif defined(_WIN32)
    platform = "windows";
#elif defined(__linux__)
    platform = "linux";
#else
    platform = "unknown";
#endif
    encode_string_field(buf, 9, platform);

    // field 10: npu_chip (NPUChip enum varint) — commons-classified from the
    // resolved chip string so every SDK reads the vendor family from the proto
    // instead of re-implementing the mapping client-side.
    int npu_chip = resolve_npu_chip(hp, chip);
    if (npu_chip != NPU_CHIP_UNSPECIFIED) {
        encode_tag(buf, 10, WIRE_VARINT);
        encode_varint(buf, static_cast<uint64_t>(npu_chip));
    }

    return buf;
}

// ============================================================================
// Build AcceleratorInfo proto bytes for a single accelerator entry
// ============================================================================

static std::vector<uint8_t> build_accelerator_info_bytes(const std::string& name, int32_t type_enum,
                                                         bool available) {
    std::vector<uint8_t> buf;
    encode_string_field(buf, 1, name);
    if (type_enum != 0) {
        encode_tag(buf, 2, WIRE_VARINT);
        encode_varint(buf, static_cast<uint64_t>(type_enum));
    }
    encode_bool_field(buf, 3, available);
    return buf;
}

// ============================================================================
// Build complete HardwareProfileResult proto bytes
// ============================================================================

static std::vector<uint8_t> build_hardware_profile_result_bytes(bool include_profile) {
    using namespace rac::router;
    const HardwareProfile hp = HardwareProfile::cached();

    std::vector<uint8_t> result_buf;

    // field 1: profile (HardwareProfile — embedded message)
    if (include_profile) {
        std::vector<uint8_t> profile_bytes = build_hardware_profile_bytes(hp);
        encode_bytes_field(result_buf, 1, profile_bytes);
    }

    // field 2: accelerators (repeated AcceleratorInfo)
    // We enumerate available accelerators in priority order.
    struct AccelEntry {
        std::string name;
        int32_t type_enum;  // matches AcceleratorPreference enum in proto
        bool available;
    };

    std::vector<AccelEntry> accels;

#if defined(__APPLE__)
    accels.push_back({"ANE", 1 /* ANE */, hp.has_ane});
    accels.push_back({"Metal", 2 /* GPU */, hp.has_metal});
    accels.push_back({"CoreML", 2 /* GPU */, hp.has_coreml});
    accels.push_back({"CPU", 3 /* CPU */, true});
#elif defined(__ANDROID__)
    accels.push_back({"QNN/Hexagon", 1 /* ANE */, hp.has_qnn});
    accels.push_back({"NNAPI", 2 /* GPU */, hp.has_nnapi});
    accels.push_back({"CPU", 3 /* CPU */, true});
#elif defined(__linux__)
    accels.push_back({"CUDA", 2 /* GPU */, hp.has_cuda});
    accels.push_back({"Vulkan", 2 /* GPU */, hp.has_vulkan});
    accels.push_back({"CPU", 3 /* CPU */, true});
#else
    accels.push_back({"CPU", 3 /* CPU */, true});
#endif

    for (const auto& a : accels) {
        std::vector<uint8_t> ai_bytes =
            build_accelerator_info_bytes(a.name, a.type_enum, a.available);
        encode_bytes_field(result_buf, 2, ai_bytes);
    }

    return result_buf;
}

// Global accelerator preference (default: AUTO = 0). Atomic so the engine
// router can read it from any thread without a lock.  Values follow
// `runanywhere.v1.AccelerationPreference` (see hardware_profile.proto).
std::atomic<int> g_accelerator_preference{0};

}  // namespace

// Internal accessor used by the engine router to turn the preference into a
// scoring bonus.  Kept in the `rac::router::internal` namespace so it isn't
// part of the public C ABI.
namespace rac::router::internal {

int get_accelerator_preference() {
    return g_accelerator_preference.load(std::memory_order_relaxed);
}

}  // namespace rac::router::internal

// ============================================================================
// Public C ABI
// ============================================================================

extern "C" {

rac_result_t rac_hardware_profile_get(uint8_t** proto_bytes_out, size_t* proto_size_out) {
    if (!proto_bytes_out || !proto_size_out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::vector<uint8_t> bytes;
    try {
        bytes = build_hardware_profile_result_bytes(/*include_profile=*/true);
    } catch (...) {
        return RAC_ERROR_UNKNOWN;
    }

    rac_result_t rc =
        rac_proto_buffer_copy_to_raw(bytes.data(), bytes.size(), proto_bytes_out, proto_size_out);
    if (rc == RAC_SUCCESS) {
        rac::events::publish_hardware_profile_completed(bytes.data(), bytes.size());
    }
    return rc;
}

void rac_hardware_profile_free(uint8_t* proto_bytes) {
    rac_proto_buffer_free_data(proto_bytes);
}

rac_result_t rac_hardware_get_accelerators(uint8_t** proto_bytes_out, size_t* proto_size_out) {
    if (!proto_bytes_out || !proto_size_out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::vector<uint8_t> bytes;
    try {
        bytes = build_hardware_profile_result_bytes(/*include_profile=*/false);
    } catch (...) {
        return RAC_ERROR_UNKNOWN;
    }

    rac_result_t rc =
        rac_proto_buffer_copy_to_raw(bytes.data(), bytes.size(), proto_bytes_out, proto_size_out);
    if (rc == RAC_SUCCESS) {
        rac::events::publish_hardware_profile_completed(bytes.data(), bytes.size());
    }
    return rc;
}

rac_result_t rac_hardware_set_accelerator_preference(int preference_enum) {
    // Validate against the full `runanywhere.v1.AccelerationPreference` value
    // range (UNSPECIFIED=0 .. VULKAN=7). Must stay in sync with
    // hardware_profile.proto — the generated header exposes
    // AccelerationPreference_MAX=7, but we hardcode the bound here because
    // this TU deliberately avoids depending on protoc-generated code (see
    // file header comment).
    if (preference_enum < 0 || preference_enum > 7) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    g_accelerator_preference.store(preference_enum, std::memory_order_relaxed);
    RAC_LOG_INFO("HardwareABI", "Accelerator preference set to %d", preference_enum);
    return RAC_SUCCESS;
}

}  // extern "C"
