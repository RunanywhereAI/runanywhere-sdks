// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// HardwareProfile::detect() tests — confirm the detection snapshot is
// non-degenerate on macOS / Linux and that repeated calls agree on the
// invariants (a single-process machine does not change its CPU core count
// between consecutive calls).
//
// We can't assert specific values (they vary by host) but we CAN assert
// a battery of self-consistency invariants that catch regressions in the
// detection logic.

#include "hardware_profile.h"

#include <gtest/gtest.h>

#include <thread>

using ra::core::CpuVendor;
using ra::core::GpuVendor;
using ra::core::HardwareProfile;

TEST(HardwareProfile, ReportsPositiveCoreCount) {
    auto hw = HardwareProfile::detect();
    EXPECT_GT(hw.cpu_cores_total, 0)
        << "detect() must report at least one CPU core";
    EXPECT_LE(hw.cpu_cores_physical, hw.cpu_cores_total)
        << "physical cores cannot exceed total (hyperthreading only adds)";
}

TEST(HardwareProfile, ReportsNonZeroRam) {
    auto hw = HardwareProfile::detect();
    EXPECT_GT(hw.total_ram_bytes, 0u)
        << "detect() must report a non-zero total RAM figure";
    EXPECT_LE(hw.available_ram_bytes, hw.total_ram_bytes)
        << "available RAM cannot exceed total RAM";
}

TEST(HardwareProfile, IsaStringIsPopulated) {
    auto hw = HardwareProfile::detect();
    EXPECT_FALSE(hw.cpu_isa.empty())
        << "detect() must populate cpu_isa (e.g. 'arm64e' or 'x86_64')";
}

TEST(HardwareProfile, DetectIsIdempotentUnderThreadRace) {
    // Run detect() from several threads; every snapshot must agree on the
    // invariants that can't change mid-process (core count, CPU ISA).
    constexpr int kThreads = 8;
    std::vector<HardwareProfile> snaps(kThreads);
    std::vector<std::thread> ts;
    ts.reserve(kThreads);
    for (int i = 0; i < kThreads; ++i) {
        ts.emplace_back([&, i] { snaps[i] = HardwareProfile::detect(); });
    }
    for (auto& t : ts) t.join();

    const auto ref = HardwareProfile::detect();
    for (const auto& s : snaps) {
        EXPECT_EQ(s.cpu_cores_total, ref.cpu_cores_total);
        EXPECT_EQ(s.cpu_cores_physical, ref.cpu_cores_physical);
        EXPECT_EQ(s.cpu_isa, ref.cpu_isa);
        EXPECT_EQ(static_cast<int>(s.cpu_vendor),
                  static_cast<int>(ref.cpu_vendor));
    }
}

#if defined(__APPLE__)
TEST(HardwareProfile, AppleHostReportsAppleVendorAndMetal) {
    auto hw = HardwareProfile::detect();
    // On any recent Apple Silicon or Intel Mac we still expect cpu_vendor
    // to be either Apple or Intel (never kUnknown).
    EXPECT_TRUE(hw.cpu_vendor == CpuVendor::kApple ||
                hw.cpu_vendor == CpuVendor::kIntel)
        << "Apple host must report a known vendor";
    // Metal is available on every supported macOS build.
    EXPECT_TRUE(hw.has_metal);
    // Apple chip generation is ≥ 1 on arm64, 0 on x86_64.
    if (hw.cpu_vendor == CpuVendor::kApple) {
        EXPECT_GE(hw.apple_chip_generation, 1);
    } else {
        EXPECT_EQ(hw.apple_chip_generation, 0);
    }
}
#endif  // __APPLE__
