// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "hardware_profile.h"

#include <cstddef>
#include <cstring>
#include <string>
#include <thread>

#if defined(__APPLE__)
#  include <sys/sysctl.h>
#  include <sys/types.h>
#elif defined(__linux__) || defined(__ANDROID__)
#  include <sys/sysinfo.h>
#  include <fstream>
#  include <sstream>
#elif defined(_WIN32)
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#endif

namespace ra::core {

namespace {

#if defined(__APPLE__)
std::string sysctl_string(const char* key) {
    std::size_t size = 0;
    if (::sysctlbyname(key, nullptr, &size, nullptr, 0) != 0 || size == 0) {
        return {};
    }
    std::string s(size, '\0');
    if (::sysctlbyname(key, s.data(), &size, nullptr, 0) != 0) return {};
    // Trim trailing null.
    while (!s.empty() && s.back() == '\0') s.pop_back();
    return s;
}

template <typename T>
T sysctl_int(const char* key, T fallback = 0) {
    T value{};
    std::size_t size = sizeof(value);
    if (::sysctlbyname(key, &value, &size, nullptr, 0) != 0) return fallback;
    return value;
}

int parse_apple_chip_gen(const std::string& brand) {
    // Brand strings look like "Apple M1 Pro", "Apple M2 Ultra", "Apple M3 Max".
    const auto pos = brand.find(" M");
    if (pos == std::string::npos || pos + 2 >= brand.size()) return 0;
    const char c = brand[pos + 2];
    if (c >= '1' && c <= '9') return c - '0';
    return 0;
}
#elif defined(__linux__) || defined(__ANDROID__)
std::string cpuinfo_value(const std::string& field) {
    std::ifstream f("/proc/cpuinfo");
    std::string line;
    while (std::getline(f, line)) {
        const auto colon = line.find(':');
        if (colon == std::string::npos) continue;
        auto key = line.substr(0, colon);
        // Trim trailing whitespace.
        while (!key.empty() && (key.back() == ' ' || key.back() == '\t')) {
            key.pop_back();
        }
        if (key == field) {
            auto val = line.substr(colon + 1);
            while (!val.empty() && (val.front() == ' ' || val.front() == '\t')) {
                val.erase(val.begin());
            }
            return val;
        }
    }
    return {};
}
#endif

}  // namespace

HardwareProfile HardwareProfile::detect() {
    HardwareProfile p;

    p.cpu_cores_total = static_cast<int>(std::thread::hardware_concurrency());
    if (p.cpu_cores_total <= 0) p.cpu_cores_total = 1;

#if defined(__APPLE__)
    p.cpu_brand          = sysctl_string("machdep.cpu.brand_string");
    p.cpu_cores_physical = sysctl_int<int>("hw.physicalcpu", p.cpu_cores_total);
    p.total_ram_bytes    = sysctl_int<std::uint64_t>("hw.memsize", 0);

    if (p.cpu_brand.find("Apple") != std::string::npos) {
        p.cpu_vendor = CpuVendor::kApple;
        p.has_metal  = true;
        p.apple_chip_generation = parse_apple_chip_gen(p.cpu_brand);
        // Apple Silicon always has the ANE; flag conservatively.
        p.has_ane    = p.apple_chip_generation > 0;
        p.cpu_isa    = "arm64";
        p.gpu_vendor = GpuVendor::kApple;
        p.gpu_name   = p.cpu_brand;  // GPU is integrated
    } else if (p.cpu_brand.find("Intel") != std::string::npos) {
        p.cpu_vendor = CpuVendor::kIntel;
        p.cpu_isa    = "x86_64";
    }

#elif defined(__linux__) || defined(__ANDROID__)
    p.cpu_brand = cpuinfo_value("model name");
    if (p.cpu_brand.empty()) p.cpu_brand = cpuinfo_value("Hardware");
    if (p.cpu_brand.empty()) p.cpu_brand = cpuinfo_value("Processor");

    struct sysinfo si {};
    if (::sysinfo(&si) == 0) {
        p.total_ram_bytes     = static_cast<std::size_t>(si.totalram) *
                                 static_cast<std::size_t>(si.mem_unit);
        p.available_ram_bytes = static_cast<std::size_t>(si.freeram) *
                                 static_cast<std::size_t>(si.mem_unit);
    }

    if (p.cpu_brand.find("Intel") != std::string::npos) {
        p.cpu_vendor = CpuVendor::kIntel;
    } else if (p.cpu_brand.find("AMD") != std::string::npos) {
        p.cpu_vendor = CpuVendor::kAmd;
    } else if (p.cpu_brand.find("Qualcomm") != std::string::npos ||
               cpuinfo_value("Hardware").find("Qualcomm") != std::string::npos) {
        p.cpu_vendor = CpuVendor::kQualcomm;
    } else if (p.cpu_brand.find("MediaTek") != std::string::npos) {
        p.cpu_vendor = CpuVendor::kMediaTek;
    } else {
        p.cpu_vendor = CpuVendor::kArm;
    }

    // Populate cpu_isa. Linux exposes it via uname(2) but that's overkill;
    // the compile-time __aarch64__ / __x86_64__ / __arm__ macros resolve
    // to the same answer for a given build target and cost nothing.
#if defined(__aarch64__)
    p.cpu_isa = "aarch64";
#elif defined(__x86_64__)
    p.cpu_isa = "x86_64";
#elif defined(__arm__)
    p.cpu_isa = "arm";
#elif defined(__i386__)
    p.cpu_isa = "i386";
#elif defined(__riscv)
    p.cpu_isa = "riscv";
#else
    p.cpu_isa = "unknown";
#endif
    // TODO: probe /dev/nvidia* for CUDA, vulkaninfo for Vulkan, etc.

#elif defined(_WIN32)
    SYSTEM_INFO si{};
    ::GetSystemInfo(&si);
    p.cpu_cores_physical = static_cast<int>(si.dwNumberOfProcessors);

    MEMORYSTATUSEX ms{};
    ms.dwLength = sizeof(ms);
    if (::GlobalMemoryStatusEx(&ms)) {
        p.total_ram_bytes     = static_cast<std::size_t>(ms.ullTotalPhys);
        p.available_ram_bytes = static_cast<std::size_t>(ms.ullAvailPhys);
    }
    p.cpu_isa = "x86_64";
#endif

    if (p.cpu_cores_physical == 0) p.cpu_cores_physical = p.cpu_cores_total;
    return p;
}

}  // namespace ra::core
