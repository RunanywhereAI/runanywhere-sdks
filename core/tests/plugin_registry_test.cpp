// SPDX-License-Identifier: Apache-2.0
#include "plugin_registry.h"
#include <gtest/gtest.h>

#include <array>

using namespace ra::core;

namespace {

// ---- Test fixture: a fake engine that declares generate_text/GGUF --------
const std::array<ra_primitive_t, 1> kPrims      = { RA_PRIMITIVE_GENERATE_TEXT };
const std::array<ra_model_format_t, 1> kFormats = { RA_FORMAT_GGUF };
const std::array<ra_runtime_id_t, 1>   kRuntimes = { RA_RUNTIME_SELF_CONTAINED };

ra_status_t fake_entry(ra_engine_vtable_t* out) {
    if (!out) return RA_ERR_INVALID_ARGUMENT;
    *out = {};
    out->metadata.name              = "fake_llm";
    out->metadata.version           = "0.0.1";
    out->metadata.abi_version       = RA_PLUGIN_API_VERSION;
    out->metadata.primitives        = kPrims.data();
    out->metadata.primitives_count  = kPrims.size();
    out->metadata.formats           = kFormats.data();
    out->metadata.formats_count     = kFormats.size();
    out->metadata.runtimes          = kRuntimes.data();
    out->metadata.runtimes_count    = kRuntimes.size();
    return RA_OK;
}

}  // namespace

TEST(PluginRegistry, StaticRegistrationRoundtrip) {
    auto& reg = PluginRegistry::global();
    const auto before = reg.size();
    reg.register_static("fake_llm", fake_entry);
    EXPECT_GE(reg.size(), before);

    PluginHandleRef h = reg.find_by_name("fake_llm");
    ASSERT_TRUE(h);
    EXPECT_EQ(h->name, "fake_llm");
    EXPECT_TRUE(h->is_static);
}

TEST(PluginRegistry, FindByCapabilityAndFormat) {
    auto& reg = PluginRegistry::global();
    reg.register_static("fake_llm", fake_entry);

    PluginHandleRef h =
        reg.find(RA_PRIMITIVE_GENERATE_TEXT, RA_FORMAT_GGUF);
    ASSERT_TRUE(h);
    EXPECT_EQ(h->name, "fake_llm");

    EXPECT_FALSE(reg.find(RA_PRIMITIVE_TRANSCRIBE, RA_FORMAT_GGUF));
    EXPECT_FALSE(reg.find(RA_PRIMITIVE_GENERATE_TEXT, RA_FORMAT_ONNX));
}

TEST(PluginRegistry, DuplicateStaticRegistrationIsIdempotent) {
    auto& reg = PluginRegistry::global();
    reg.register_static("fake_llm", fake_entry);
    const auto s1 = reg.size();
    reg.register_static("fake_llm", fake_entry);
    const auto s2 = reg.size();
    EXPECT_EQ(s1, s2);
}
