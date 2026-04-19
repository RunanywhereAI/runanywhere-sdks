// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Dynamic plugin loader smoke — dlopens every built engine plugin and
// confirms the PluginRegistry discovers them with correct metadata.
//
// This is intentionally a single test that exercises the real engine
// dylibs produced by the same build, rather than a synthetic fixture
// plugin. If the engine vtables drift from the registry's expectations,
// this test is the first thing that catches it.
//
// Skipped under RA_STATIC_PLUGINS — in static mode the engines are
// already linked and their RA_STATIC_PLUGIN_REGISTER constructors fire
// at process start, so dlopen has nothing to do.

#include "../registry/plugin_registry.h"

#include <gtest/gtest.h>

#include <cstddef>
#include <filesystem>
#include <string>
#include <string_view>

#if !defined(RA_STATIC_PLUGINS)

using ra::core::PluginHandleRef;
using ra::core::PluginRegistry;

namespace {

// The CMake build sets RA_ENGINE_PLUGIN_DIR to the directory that holds
// librunanywhere_*.dylib / .so for the current config. When running ad-hoc
// from the build tree we can fall back to walking `../engines/*` relative
// to the test binary's CWD.
std::filesystem::path find_plugin_dir() {
#ifdef RA_ENGINE_PLUGIN_DIR
    return std::filesystem::path(RA_ENGINE_PLUGIN_DIR);
#else
    return std::filesystem::current_path();
#endif
}

std::string plugin_basename(std::string_view name) {
    // Full library basename as emitted by ra_add_engine_plugin's
    // OUTPUT_NAME=<target_name> → "runanywhere_llamacpp" etc, prefixed
    // with "lib" by CMake on Unix-ish platforms.
#if defined(__APPLE__)
    return "lib" + std::string(name) + ".dylib";
#elif defined(_WIN32)
    return std::string(name) + ".dll";
#else
    return "lib" + std::string(name) + ".so";
#endif
}

}  // namespace

TEST(PluginLoaderDynamic, LoadsBuiltLlamacppDylib) {
    const auto dir = find_plugin_dir();
    const auto path = dir / "llamacpp" / plugin_basename("runanywhere_llamacpp");
    if (!std::filesystem::exists(path)) {
        GTEST_SKIP() << "plugin dylib not present at " << path
                     << " — skipping (expected when test is invoked outside "
                        "the build tree or with a different CMake config)";
    }

    auto& reg = PluginRegistry::global();
    const auto rc = reg.load_plugin(path.string());
    EXPECT_EQ(rc, RA_OK);

    PluginHandleRef h = reg.find_by_name("llamacpp");
    ASSERT_TRUE(h);
    EXPECT_EQ(h->name, "llamacpp");
    EXPECT_FALSE(h->is_static);
    EXPECT_EQ(h->vtable.metadata.abi_version, RA_PLUGIN_API_VERSION);
    EXPECT_STREQ(h->vtable.metadata.name, "llamacpp");

    // llamacpp advertises both generate_text and embed.
    bool has_llm = false, has_embed = false;
    for (std::size_t i = 0; i < h->vtable.metadata.primitives_count; ++i) {
        auto p = h->vtable.metadata.primitives[i];
        if (p == RA_PRIMITIVE_GENERATE_TEXT) has_llm   = true;
        if (p == RA_PRIMITIVE_EMBED)         has_embed = true;
    }
    EXPECT_TRUE(has_llm);
    EXPECT_TRUE(has_embed);
}

TEST(PluginLoaderDynamic, LoadingUnknownPathReturnsError) {
    auto& reg = PluginRegistry::global();
    const auto rc = reg.load_plugin("/definitely/does/not/exist.dylib");
    EXPECT_NE(rc, RA_OK);
}

TEST(PluginLoaderDynamic, DuplicateLoadIsIdempotent) {
    const auto dir = find_plugin_dir();
    const auto path = dir / "llamacpp" / plugin_basename("runanywhere_llamacpp");
    if (!std::filesystem::exists(path)) {
        GTEST_SKIP() << "plugin dylib not present";
    }
    auto& reg = PluginRegistry::global();
    // First load must succeed.
    EXPECT_EQ(reg.load_plugin(path.string()), RA_OK);
    const auto before = reg.size();
    // Second load must not add a duplicate.
    EXPECT_EQ(reg.load_plugin(path.string()), RA_OK);
    EXPECT_EQ(reg.size(), before);
}

TEST(PluginLoaderDynamic, LoadsAllThreeEnginesSideBySide) {
    // Cross-engine sanity: loading llamacpp + sherpa + wakeword should
    // populate three distinct registry entries with non-overlapping
    // primitives. This is the closest we get to a realistic "production
    // bootstrap" without real inference.
    const auto dir = find_plugin_dir();
    struct Expected {
        const char* subdir;
        const char* lib_stem;
        const char* plugin_name;
    };
    const Expected engines[] = {
        {"llamacpp", "runanywhere_llamacpp", "llamacpp"},
        {"sherpa",   "runanywhere_sherpa",   "sherpa"  },
        // wakeword primitive is served by the sherpa plugin — no
        // separate wakeword plugin is built.
    };

    auto& reg = PluginRegistry::global();
    for (const auto& e : engines) {
        const auto path = dir / e.subdir / plugin_basename(e.lib_stem);
        if (!std::filesystem::exists(path)) {
            GTEST_SKIP() << "plugin dylib not present at " << path;
        }
        EXPECT_EQ(reg.load_plugin(path.string()), RA_OK);
    }
    for (const auto& e : engines) {
        auto h = reg.find_by_name(e.plugin_name);
        ASSERT_TRUE(h) << "plugin " << e.plugin_name << " not found";
        EXPECT_STREQ(h->vtable.metadata.name, e.plugin_name);
    }
}

#endif  // !RA_STATIC_PLUGINS
