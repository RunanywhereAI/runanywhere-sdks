/**
 * @file device_facts.cpp
 * @brief Canonical device-fact classifiers (chip / GPU / NPU / P-E / memory).
 *
 * Ports the policy previously reimplemented in Kotlin CppBridgeHardware,
 * Flutter dart_bridge_device, and RN HybridRunAnywhereDeviceInfo into one
 * C++ source of truth. Platforms remain responsible for reading OS facts.
 */

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <string>
#include <string_view>

#include "rac/infrastructure/device/rac_device_facts.h"

namespace {

bool is_blank(std::string_view s) {
    return s.empty() || s == "unknown" || s == "Unknown" || s == "UNKNOWN";
}

bool equals_ci(std::string_view a, std::string_view b) {
    if (a.size() != b.size()) {
        return false;
    }
    for (size_t i = 0; i < a.size(); ++i) {
        if (std::tolower(static_cast<unsigned char>(a[i])) !=
            std::tolower(static_cast<unsigned char>(b[i]))) {
            return false;
        }
    }
    return true;
}

bool contains_ci(std::string_view haystack, std::string_view needle) {
    if (needle.empty() || haystack.size() < needle.size()) {
        return false;
    }
    auto lower = [](unsigned char c) { return static_cast<char>(std::tolower(c)); };
    for (size_t i = 0; i + needle.size() <= haystack.size(); ++i) {
        bool match = true;
        for (size_t j = 0; j < needle.size(); ++j) {
            if (lower(static_cast<unsigned char>(haystack[i + j])) !=
                lower(static_cast<unsigned char>(needle[j]))) {
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

bool is_bare_vendor(std::string_view s) {
    return equals_ci(s, "qcom") || equals_ci(s, "qualcomm");
}

std::string to_lower(std::string_view s) {
    std::string out;
    out.reserve(s.size());
    for (char c : s) {
        out.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
    }
    return out;
}

bool write_out(char* out, size_t out_size, std::string_view value) {
    if (out == nullptr || out_size < 2) {
        return false;
    }
    const size_t n = std::min(value.size(), out_size - 1);
    if (n > 0) {
        std::memcpy(out, value.data(), n);
    }
    out[n] = '\0';
    return n == value.size();
}

/** Exynos / s5e model with leading 2xxx generation (2200+ → Xclipse). */
bool is_exynos_xclipse_model(std::string_view model) {
    const std::string m = to_lower(model);
    // Match 2[2-9]xx digit runs (Exynos 2200, 2400, s5e9925, …).
    for (size_t i = 0; i + 3 < m.size(); ++i) {
        if (m[i] == '2' && m[i + 1] >= '2' && m[i + 1] <= '9' &&
            std::isdigit(static_cast<unsigned char>(m[i + 2])) &&
            std::isdigit(static_cast<unsigned char>(m[i + 3]))) {
            return true;
        }
    }
    return false;
}

/** Dimensity 9xxx flagship → Immortalis. */
bool is_dimensity_immortalis_model(std::string_view model) {
    const std::string m = to_lower(model);
    for (size_t i = 0; i + 3 < m.size(); ++i) {
        if (m[i] == '9' && std::isdigit(static_cast<unsigned char>(m[i + 1])) &&
            std::isdigit(static_cast<unsigned char>(m[i + 2])) &&
            std::isdigit(static_cast<unsigned char>(m[i + 3]))) {
            return true;
        }
    }
    return false;
}

bool match_exynos_2xxx(std::string_view haystack) {
    const std::string h = to_lower(haystack);
    // (exynos|s5e) optionally spaced then 2xxx
    auto try_at = [&](std::string_view prefix) {
        size_t pos = 0;
        while (pos < h.size()) {
            const size_t found = h.find(prefix, pos);
            if (found == std::string::npos) {
                return false;
            }
            size_t i = found + prefix.size();
            while (i < h.size() && (h[i] == ' ' || h[i] == '-' || h[i] == '_')) {
                ++i;
            }
            if (i < h.size() && h[i] == '2') {
                size_t digits = 0;
                while (i + digits < h.size() &&
                       std::isdigit(static_cast<unsigned char>(h[i + digits]))) {
                    ++digits;
                }
                if (digits >= 3) {
                    return true;
                }
            }
            pos = found + 1;
        }
        return false;
    };
    return try_at("exynos") || try_at("s5e");
}

}  // namespace

rac_result_t rac_device_resolve_chip_name(const char* soc_manufacturer, const char* soc_model,
                                          const char* build_hardware, const char* cpuinfo_hardware,
                                          const char* architecture_fallback, char* out,
                                          size_t out_size) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (out_size < 2) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }
    out[0] = '\0';

    const std::string_view model = soc_model ? soc_model : "";
    const std::string_view manufacturer = soc_manufacturer ? soc_manufacturer : "";

    if (!is_blank(model)) {
        std::string resolved(model);
        if (!is_blank(manufacturer) && !contains_ci(model, manufacturer)) {
            resolved = std::string(manufacturer) + " " + std::string(model);
        }
        if (!write_out(out, out_size, resolved)) {
            return RAC_ERROR_BUFFER_TOO_SMALL;
        }
        return RAC_SUCCESS;
    }

    auto try_hardware = [&](const char* raw) -> rac_result_t {
        if (raw == nullptr || is_blank(raw) || is_bare_vendor(raw)) {
            return RAC_ERROR_NOT_FOUND;
        }
        if (!write_out(out, out_size, raw)) {
            return RAC_ERROR_BUFFER_TOO_SMALL;
        }
        return RAC_SUCCESS;
    };

    {
        const rac_result_t rc = try_hardware(build_hardware);
        if (rc == RAC_SUCCESS || rc == RAC_ERROR_BUFFER_TOO_SMALL) {
            return rc;
        }
    }
    {
        const rac_result_t rc = try_hardware(cpuinfo_hardware);
        if (rc == RAC_SUCCESS || rc == RAC_ERROR_BUFFER_TOO_SMALL) {
            return rc;
        }
    }

    if (architecture_fallback != nullptr && !is_blank(architecture_fallback)) {
        if (!write_out(out, out_size, architecture_fallback)) {
            return RAC_ERROR_BUFFER_TOO_SMALL;
        }
        return RAC_SUCCESS;
    }

    return RAC_ERROR_NOT_FOUND;
}

rac_result_t rac_device_classify_gpu_family(const char* soc_manufacturer, const char* soc_model,
                                            const char* chip_name, char* out, size_t out_size) {
    if (out == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (out_size < 2) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    const std::string_view manufacturer = soc_manufacturer ? soc_manufacturer : "";
    const std::string_view model = soc_model ? soc_model : "";
    const std::string_view chip = chip_name ? chip_name : "";

    const char* family = "unknown";

    if (!is_blank(manufacturer)) {
        const std::string mfg = to_lower(manufacturer);
        if (contains_ci(mfg, "qualcomm")) {
            family = "adreno";
        } else if (contains_ci(mfg, "samsung")) {
            family = is_exynos_xclipse_model(model) ? "xclipse" : "mali";
        } else if (contains_ci(mfg, "google")) {
            family = "mali";
        } else if (contains_ci(mfg, "mediatek")) {
            family = is_dimensity_immortalis_model(model) ? "immortalis" : "mali";
        } else if (contains_ci(mfg, "apple")) {
            family = "apple";
        }
    }

    if (std::strcmp(family, "unknown") == 0 && !is_blank(chip)) {
        const std::string c = to_lower(chip);
        if (contains_ci(c, "exynos") || c.rfind("s5e", 0) == 0 || contains_ci(c, "samsung") ||
            contains_ci(c, "mediatek") || c.rfind("mt6", 0) == 0 || c.rfind("mt8", 0) == 0 ||
            contains_ci(c, "dimensity") || contains_ci(c, "helio") || contains_ci(c, "kirin") ||
            contains_ci(c, "hisilicon") || contains_ci(c, "tensor") || c.rfind("gs1", 0) == 0 ||
            c.rfind("gs2", 0) == 0) {
            family = "mali";
        } else if (contains_ci(c, "snapdragon") || contains_ci(c, "qualcomm") ||
                   contains_ci(c, "sdm") || contains_ci(c, "sm8") || contains_ci(c, "sm7") ||
                   contains_ci(c, "sm6") || contains_ci(c, "msm")) {
            family = "adreno";
        } else if (contains_ci(c, "apple") || c.rfind("a1", 0) == 0 || c.rfind("m1", 0) == 0 ||
                   c.rfind("m2", 0) == 0 || c.rfind("m3", 0) == 0 || c.rfind("m4", 0) == 0) {
            family = "apple";
        } else if (contains_ci(c, "intel")) {
            family = "intel";
        } else if (contains_ci(c, "nvidia") || contains_ci(c, "tegra")) {
            family = "nvidia";
        }
    }

    if (!write_out(out, out_size, family)) {
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }
    return RAC_SUCCESS;
}

rac_bool_t rac_device_heuristic_has_npu(const char* soc_manufacturer, const char* soc_model,
                                        const char* chip_name) {
    std::string haystack;
    if (soc_manufacturer && soc_manufacturer[0] != '\0') {
        haystack.append(soc_manufacturer);
        haystack.push_back(' ');
    }
    if (soc_model && soc_model[0] != '\0') {
        haystack.append(soc_model);
        haystack.push_back(' ');
    }
    if (chip_name && chip_name[0] != '\0') {
        haystack.append(chip_name);
    }
    if (haystack.empty()) {
        return RAC_FALSE;
    }
    const std::string h = to_lower(haystack);

    if (contains_ci(h, "sm8") || contains_ci(h, "sm7") || contains_ci(h, "qcm") ||
        contains_ci(h, "tensor") || contains_ci(h, "gs1") || contains_ci(h, "gs2") ||
        contains_ci(h, "dimensity") || match_exynos_2xxx(h)) {
        return RAC_TRUE;
    }
    return RAC_FALSE;
}

rac_result_t rac_device_split_performance_cores(const int64_t* max_freqs, size_t count,
                                                int32_t* out_performance, int32_t* out_efficiency) {
    if (out_performance == nullptr || out_efficiency == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_performance = 0;
    *out_efficiency = 0;

    if (max_freqs == nullptr || count == 0) {
        return RAC_SUCCESS;  // unknown — never invent half/half
    }

    int64_t max_freq = 0;
    for (size_t i = 0; i < count; ++i) {
        if (max_freqs[i] <= 0) {
            return RAC_SUCCESS;  // incomplete sample → unknown
        }
        if (max_freqs[i] > max_freq) {
            max_freq = max_freqs[i];
        }
    }

    int32_t performance = 0;
    for (size_t i = 0; i < count; ++i) {
        if (max_freqs[i] == max_freq) {
            ++performance;
        }
    }
    *out_performance = performance;
    *out_efficiency = static_cast<int32_t>(count) - performance;
    return RAC_SUCCESS;
}

int64_t rac_device_coalesce_available_memory(int64_t probed_available_bytes) {
    return probed_available_bytes > 0 ? probed_available_bytes : 0;
}
