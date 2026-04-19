// SPDX-License-Identifier: Apache-2.0
#include "../router/engine_router.h"
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
