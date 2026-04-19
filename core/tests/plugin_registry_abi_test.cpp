// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Smoke test for the public ra_registry_* C ABI (used by every frontend
// SDK's loadPlugin path).

#include "../abi/ra_primitives.h"
#include "../abi/ra_plugin.h"

#include <gtest/gtest.h>

extern "C" {
ra_status_t ra_registry_load_plugin(const char* library_path);
ra_status_t ra_registry_unload_plugin(const char* plugin_name);
int32_t     ra_registry_plugin_count(void);
}

namespace {

TEST(RegistryABI, PluginCountIsNonNegative) {
    EXPECT_GE(ra_registry_plugin_count(), 0);
}

TEST(RegistryABI, LoadNullPathIsRejected) {
    EXPECT_EQ(ra_registry_load_plugin(nullptr), RA_ERR_INVALID_ARGUMENT);
}

TEST(RegistryABI, UnloadNullNameIsRejected) {
    EXPECT_EQ(ra_registry_unload_plugin(nullptr), RA_ERR_INVALID_ARGUMENT);
}

TEST(RegistryABI, LoadNonexistentPathReturnsError) {
    // Path can't possibly exist. Must not crash, must not invent a handle.
    const auto before = ra_registry_plugin_count();
    const auto rc = ra_registry_load_plugin("/tmp/ra_bogus_plugin_path.dylib");
    EXPECT_NE(rc, RA_OK);
    EXPECT_EQ(ra_registry_plugin_count(), before);
}

}  // namespace
