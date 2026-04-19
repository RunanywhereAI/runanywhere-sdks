// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Deeper lifecycle tests for PluginRegistry: enumerate(), unload_plugin(),
// and concurrent reader/writer stress. The existing plugin_registry_test.cpp
// covers the happy-path; this file covers the corners.

#include "../registry/plugin_registry.h"

#include <gtest/gtest.h>

#include <array>
#include <atomic>
#include <string>
#include <thread>
#include <unordered_set>
#include <vector>

using ra::core::PluginHandleRef;
using ra::core::PluginRegistry;

namespace {

const std::array<ra_primitive_t, 1> kPrims   = { RA_PRIMITIVE_EMBED };
const std::array<ra_model_format_t, 1> kFmts = { RA_FORMAT_ONNX };
const std::array<ra_runtime_id_t, 1> kRts    = { RA_RUNTIME_SELF_CONTAINED };

template <char const* Name>
ra_status_t fill(ra_engine_vtable_t* out) {
    if (!out) return RA_ERR_INVALID_ARGUMENT;
    *out = {};
    out->metadata.name             = Name;
    out->metadata.version          = "0.0.0";
    out->metadata.abi_version      = RA_PLUGIN_API_VERSION;
    out->metadata.primitives       = kPrims.data();
    out->metadata.primitives_count = kPrims.size();
    out->metadata.formats          = kFmts.data();
    out->metadata.formats_count    = kFmts.size();
    out->metadata.runtimes         = kRts.data();
    out->metadata.runtimes_count   = kRts.size();
    return RA_OK;
}

constexpr char kNameA[] = "lifecycle_a";
constexpr char kNameB[] = "lifecycle_b";
constexpr char kNameC[] = "lifecycle_c";

}  // namespace

TEST(PluginRegistryLifecycle, EnumerateSnapshotsCurrentPlugins) {
    auto& reg = PluginRegistry::global();
    reg.register_static(kNameA, &fill<kNameA>);
    reg.register_static(kNameB, &fill<kNameB>);

    std::unordered_set<std::string> seen;
    reg.enumerate([&](const PluginHandleRef& h) {
        if (h) seen.insert(h->name);
    });
    EXPECT_TRUE(seen.count(kNameA));
    EXPECT_TRUE(seen.count(kNameB));
}

TEST(PluginRegistryLifecycle, UnloadRemovesFromRegistryKeepsHandleAlive) {
    auto& reg = PluginRegistry::global();
    reg.register_static(kNameC, &fill<kNameC>);

    // Grab a PluginHandleRef — it should keep the handle alive even after
    // unload_plugin drops the registry's own shared_ptr.
    PluginHandleRef h = reg.find_by_name(kNameC);
    ASSERT_TRUE(h);

    EXPECT_EQ(reg.unload_plugin(kNameC), RA_OK);
    EXPECT_FALSE(reg.find_by_name(kNameC))
        << "after unload the registry must not return the handle";

    // Our ref is still live (shared_ptr) — this is the in-flight-session
    // safety contract documented in plugin_registry.h.
    EXPECT_EQ(h->name, std::string(kNameC));
}

TEST(PluginRegistryLifecycle, UnloadOfUnknownPluginIsAnError) {
    auto& reg = PluginRegistry::global();
    EXPECT_EQ(reg.unload_plugin("no_such_plugin_foo"), RA_ERR_INVALID_ARGUMENT);
}

TEST(PluginRegistryLifecycle, ConcurrentReadersDoNotRace) {
    auto& reg = PluginRegistry::global();
    reg.register_static(kNameA, &fill<kNameA>);

    // 16 threads constantly find_by_name + enumerate while one thread
    // mutates the registry with duplicate registrations (which should be
    // idempotent). Green under TSan == mutex covers the read/write
    // boundary.
    constexpr int kReaders = 16;
    std::atomic<bool> stop{false};
    std::vector<std::thread> ts;
    ts.reserve(kReaders + 1);
    for (int i = 0; i < kReaders; ++i) {
        ts.emplace_back([&] {
            while (!stop.load(std::memory_order_relaxed)) {
                auto h = reg.find_by_name(kNameA);
                (void)h;
                reg.enumerate([](const PluginHandleRef& p) { (void)p; });
            }
        });
    }
    ts.emplace_back([&] {
        for (int i = 0; i < 1000; ++i) {
            reg.register_static(kNameA, &fill<kNameA>);
        }
        stop.store(true);
    });
    for (auto& t : ts) t.join();
}
