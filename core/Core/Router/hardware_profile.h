// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Hardware capability detection. Ported from RCLI core/hardware_profile.h.
//
// Populated once at startup, queried by the L3 router on every
// engine-selection decision. Safe to refresh via HardwareProfile::detect()
// (e.g. after a thermal state change).

#ifndef RA_CORE_HARDWARE_PROFILE_H
#define RA_CORE_HARDWARE_PROFILE_H

#include <cstddef>
#include <cstdint>
#include <string>

namespace ra::core {

enum class CpuVendor {
    kUnknown,
    kApple,
    kIntel,
    kAmd,
    kArm,
    kQualcomm,
    kMediaTek,
};

enum class GpuVendor {
    kNone,
    kApple,
    kNvidia,
    kAmd,
    kIntel,
    kArmMali,
    kQualcommAdreno,
    kPowerVr,
};

struct HardwareProfile {
    // CPU
    CpuVendor    cpu_vendor = CpuVendor::kUnknown;
    std::string  cpu_brand;
    int          cpu_cores_total    = 0;
    int          cpu_cores_physical = 0;
    std::string  cpu_isa;         // e.g. "arm64e", "x86_64"

    // Memory
    std::size_t  total_ram_bytes     = 0;
    std::size_t  available_ram_bytes = 0;

    // GPU
    GpuVendor    gpu_vendor = GpuVendor::kNone;
    std::string  gpu_name;
    std::size_t  gpu_memory_bytes = 0;

    // Accelerators
    bool has_metal           = false;
    bool has_ane             = false;   // Apple Neural Engine
    bool has_cuda            = false;
    bool has_rocm            = false;
    bool has_vulkan          = false;
    bool has_qnn             = false;   // Qualcomm Hexagon NPU
    bool has_intel_ai_boost  = false;   // Intel Meteor Lake NPU

    // Apple chip generation — used by MetalRT engine capability gates.
    // 0 if non-Apple; otherwise 1 (A/M1), 2 (M2), 3 (M3), etc.
    int  apple_chip_generation = 0;

    // Snapshot the current machine. Cheap to call — uses sysctl on Apple,
    // /proc on Linux, and Windows APIs on Win32. Thread-safe.
    static HardwareProfile detect();
};

}  // namespace ra::core

#endif  // RA_CORE_HARDWARE_PROFILE_H
