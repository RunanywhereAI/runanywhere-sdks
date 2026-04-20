// SPDX-License-Identifier: Apache-2.0
#include "engine_router.h"
#include <gtest/gtest.h>

#include <array>

using namespace ra::core;

namespace {

const std::array<ra_primitive_t, 1> kLLMPrims  = { RA_PRIMITIVE_GENERATE_TEXT };
const std::array<ra_model_format_t, 1> kGguf   = { RA_FORMAT_GGUF };
const std::array<ra_runtime_id_t, 1>   kSelf   = { RA_RUNTIME_SELF_CONTAINED };

ra_status_t router_fake_entry(ra_engine_vtable_t* out) {
    *out = {};
    out->metadata.name              = "router_fake_llm";
    out->metadata.version           = "0.0.1";
    out->metadata.abi_version       = RA_PLUGIN_API_VERSION;
    out->metadata.primitives        = kLLMPrims.data();
    out->metadata.primitives_count  = kLLMPrims.size();
    out->metadata.formats           = kGguf.data();
    out->metadata.formats_count     = kGguf.size();
    out->metadata.runtimes          = kSelf.data();
    out->metadata.runtimes_count    = kSelf.size();
    return RA_OK;
}

}  // namespace

TEST(EngineRouter, RoutesToCapableEngine) {
    auto& reg = PluginRegistry::global();
    reg.register_static("router_fake_llm", router_fake_entry);
    EngineRouter router(reg, HardwareProfile::detect());

    RouteRequest req{RA_PRIMITIVE_GENERATE_TEXT, RA_FORMAT_GGUF, 0, {}};
    auto result = router.route(req);
    ASSERT_NE(result.plugin, nullptr);
    EXPECT_EQ(result.plugin->name, "router_fake_llm");
    EXPECT_GT(result.score, 0);
}

TEST(EngineRouter, RejectsUnmatchedFormat) {
    auto& reg = PluginRegistry::global();
    reg.register_static("router_fake_llm", router_fake_entry);
    EngineRouter router(reg, HardwareProfile::detect());

    RouteRequest req{RA_PRIMITIVE_GENERATE_TEXT, RA_FORMAT_ONNX, 0, {}};
    auto result = router.route(req);
    EXPECT_EQ(result.plugin, nullptr);
    EXPECT_FALSE(result.rejection_reason.empty());
}

TEST(EngineRouter, PinnedEngineBypassesScoring) {
    auto& reg = PluginRegistry::global();
    reg.register_static("router_fake_llm", router_fake_entry);
    EngineRouter router(reg, HardwareProfile::detect());

    RouteRequest req{RA_PRIMITIVE_GENERATE_TEXT, RA_FORMAT_GGUF, 0,
                      "router_fake_llm"};
    auto result = router.route(req);
    ASSERT_NE(result.plugin, nullptr);
    EXPECT_EQ(result.plugin->name, "router_fake_llm");
}

TEST(EngineRouter, PinnedEngineNotFoundYieldsError) {
    auto& reg = PluginRegistry::global();
    EngineRouter router(reg, HardwareProfile::detect());
    RouteRequest req{RA_PRIMITIVE_GENERATE_TEXT, RA_FORMAT_GGUF, 0,
                      "nonexistent_engine"};
    auto result = router.route(req);
    EXPECT_EQ(result.plugin, nullptr);
    EXPECT_NE(result.rejection_reason.find("pinned"), std::string::npos);
}

namespace {

// A second fake LLM engine so we can test multi-candidate tie-breaks.
// This one is named differently + shares the same (primitive, format) pair
// so both are routing candidates.
const std::array<ra_runtime_id_t, 1> kMetal = { RA_RUNTIME_METAL };

ra_status_t router_fake_metal_entry(ra_engine_vtable_t* out) {
    *out = {};
    out->metadata.name              = "router_fake_llm_metal";
    out->metadata.version           = "0.0.1";
    out->metadata.abi_version       = RA_PLUGIN_API_VERSION;
    out->metadata.primitives        = kLLMPrims.data();
    out->metadata.primitives_count  = kLLMPrims.size();
    out->metadata.formats           = kGguf.data();
    out->metadata.formats_count     = kGguf.size();
    out->metadata.runtimes          = kMetal.data();
    out->metadata.runtimes_count    = kMetal.size();
    return RA_OK;
}

}  // namespace

TEST(EngineRouter, PinnedEngineRejectsFormatMismatch) {
    auto& reg = PluginRegistry::global();
    reg.register_static("router_fake_llm", router_fake_entry);
    EngineRouter router(reg, HardwareProfile::detect());

    // Pinned engine exists, but caller requests a format the plugin doesn't
    // list — router rejects with a descriptive reason.
    RouteRequest req{RA_PRIMITIVE_GENERATE_TEXT, RA_FORMAT_ONNX, 0,
                      "router_fake_llm"};
    auto result = router.route(req);
    EXPECT_EQ(result.plugin, nullptr);
    EXPECT_NE(result.rejection_reason.find("format"), std::string::npos);
}

TEST(EngineRouter, PinnedEngineRejectsPrimitiveMismatch) {
    auto& reg = PluginRegistry::global();
    reg.register_static("router_fake_llm", router_fake_entry);
    EngineRouter router(reg, HardwareProfile::detect());

    // Pinned engine exists, but caller asks for a primitive it doesn't
    // serve — router rejects.
    RouteRequest req{RA_PRIMITIVE_TRANSCRIBE, RA_FORMAT_GGUF, 0,
                      "router_fake_llm"};
    auto result = router.route(req);
    EXPECT_EQ(result.plugin, nullptr);
    EXPECT_NE(result.rejection_reason.find("primitive"), std::string::npos);
}

TEST(EngineRouter, PrefersHardwareAcceleratedOnAppleSilicon) {
    auto& reg = PluginRegistry::global();
    reg.register_static("router_fake_llm",       router_fake_entry);
    reg.register_static("router_fake_llm_metal", router_fake_metal_entry);

    // Construct a hardware profile with Metal available. We can't mutate
    // HardwareProfile::detect(); instead we construct the HW profile
    // directly so the test is host-independent.
    HardwareProfile hw;
    hw.cpu_vendor = CpuVendor::kApple;
    hw.has_metal  = true;
    hw.cpu_isa    = "arm64";
    hw.cpu_cores_total = 8;
    EngineRouter router(reg, hw);

    RouteRequest req{RA_PRIMITIVE_GENERATE_TEXT, RA_FORMAT_GGUF, 0, {}};
    auto result = router.route(req);
    ASSERT_NE(result.plugin, nullptr);
    // The Metal-runtime engine must win on an Apple+Metal host.
    EXPECT_EQ(result.plugin->name, "router_fake_llm_metal");
    EXPECT_GT(result.score, 100);  // base + metal bonus
}

TEST(EngineRouter, NoCandidateYieldsInformativeRejection) {
    auto& reg = PluginRegistry::global();
    reg.register_static("router_fake_llm", router_fake_entry);
    EngineRouter router(reg, HardwareProfile::detect());

    // Ask for a primitive no registered plugin serves. router_fake_llm
    // advertises RA_PRIMITIVE_GENERATE_TEXT only.
    RouteRequest req{RA_PRIMITIVE_TRANSCRIBE, RA_FORMAT_ONNX, 0, {}};
    auto result = router.route(req);
    EXPECT_EQ(result.plugin, nullptr);
    EXPECT_FALSE(result.rejection_reason.empty());
}
