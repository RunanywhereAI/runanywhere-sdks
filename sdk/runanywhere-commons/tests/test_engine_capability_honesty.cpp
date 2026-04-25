/**
 * @file test_engine_capability_honesty.cpp
 * @brief Cross-cut router tests for backend capability honesty.
 *
 * T3.4: Engines must not become routing candidates unless the primitive's
 * vtable slot is populated and the engine's capability check accepts the
 * current build/runtime environment.
 */

#include <cstdio>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/router/rac_engine_router.h"
#include "rac/router/rac_hardware_profile.h"

namespace {

const int k_ops_sentinel = 0xC0FFEE;

rac_result_t backend_unavailable_capability_check(void) {
    return RAC_ERROR_BACKEND_UNAVAILABLE;
}

rac_engine_vtable_t make_vt(const char* name,
                            int32_t priority,
                            rac_primitive_t primitive,
                            rac_result_t (*capability_check)(void) = nullptr) {
    rac_engine_vtable_t v{};
    v.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    v.metadata.name = name;
    v.metadata.display_name = name;
    v.metadata.engine_version = "0.0.0";
    v.metadata.priority = priority;
    v.capability_check = capability_check;

    switch (primitive) {
        case RAC_PRIMITIVE_GENERATE_TEXT:
            v.llm_ops = reinterpret_cast<const struct rac_llm_service_ops*>(&k_ops_sentinel);
            break;
        case RAC_PRIMITIVE_TRANSCRIBE:
            v.stt_ops = reinterpret_cast<const struct rac_stt_service_ops*>(&k_ops_sentinel);
            break;
        case RAC_PRIMITIVE_SYNTHESIZE:
            v.tts_ops = reinterpret_cast<const struct rac_tts_service_ops*>(&k_ops_sentinel);
            break;
        case RAC_PRIMITIVE_DETECT_VOICE:
            v.vad_ops = reinterpret_cast<const struct rac_vad_service_ops*>(&k_ops_sentinel);
            break;
        case RAC_PRIMITIVE_DIFFUSION:
            v.diffusion_ops =
                reinterpret_cast<const struct rac_diffusion_service_ops*>(&k_ops_sentinel);
            break;
        default:
            break;
    }

    return v;
}

int test_count = 0;
int fail_count = 0;

#define CHECK(cond, label) do { \
    ++test_count; \
    if (!(cond)) { \
        ++fail_count; \
        std::fprintf(stderr, "  FAIL: %s (%s:%d) -- %s\n", label, __FILE__, __LINE__, #cond); \
    } else { \
        std::fprintf(stdout, "  ok:   %s\n", label); \
    } \
} while (0)

bool route_is(const rac::router::EngineRouter& router,
              rac_primitive_t primitive,
              const rac_engine_vtable_t* expected) {
    rac::router::RouteRequest req;
    req.primitive = primitive;
    return router.route(req).vtable == expected;
}

void cleanup(const char* name) {
    (void)rac_plugin_unregister(name);
}

}  // namespace

int main() {
    std::fprintf(stdout, "test_engine_capability_honesty\n");

    rac::router::HardwareProfile profile{};
    rac::router::EngineRouter router(profile);

    {
        auto fallback = make_vt("fallback_llm", 10, RAC_PRIMITIVE_GENERATE_TEXT);
        auto genie = make_vt("genie", 200, RAC_PRIMITIVE_GENERATE_TEXT,
                             backend_unavailable_capability_check);

        CHECK(rac_plugin_register(&fallback) == RAC_SUCCESS,
              "LLM fallback registers");
        CHECK(rac_plugin_register(&genie) == RAC_ERROR_CAPABILITY_UNSUPPORTED,
              "unavailable Genie is rejected before routing");
        CHECK(route_is(router, RAC_PRIMITIVE_GENERATE_TEXT, &fallback),
              "LLM route does not choose unavailable Genie");

        cleanup("fallback_llm");
        cleanup("genie");
    }

    {
        auto fallback = make_vt("fallback_diffusion", 10, RAC_PRIMITIVE_DIFFUSION);
        auto generate_unavailable =
            make_vt("diffusion-coreml", 200, RAC_PRIMITIVE_UNSPECIFIED);

        CHECK(rac_plugin_register(&fallback) == RAC_SUCCESS,
              "diffusion fallback registers");
        CHECK(rac_plugin_register(&generate_unavailable) == RAC_SUCCESS,
              "generate-unavailable diffusion shell can be inspected");
        CHECK(rac_engine_vtable_slot(&generate_unavailable,
                                     RAC_PRIMITIVE_DIFFUSION) == nullptr,
              "generate-unavailable diffusion shell has no diffusion slot");
        CHECK(route_is(router, RAC_PRIMITIVE_DIFFUSION, &fallback),
              "diffusion route skips CoreML shell with no generate op");

        cleanup("diffusion-coreml");

        auto no_bundle = make_vt("diffusion-coreml", 200, RAC_PRIMITIVE_DIFFUSION,
                                 backend_unavailable_capability_check);
        CHECK(rac_plugin_register(&no_bundle) == RAC_ERROR_CAPABILITY_UNSUPPORTED,
              "CoreML diffusion without a usable bundle is rejected");
        CHECK(route_is(router, RAC_PRIMITIVE_DIFFUSION, &fallback),
              "diffusion route keeps fallback when CoreML bundle is unavailable");

        cleanup("fallback_diffusion");
        cleanup("diffusion-coreml");
    }

    struct SpeechCase {
        rac_primitive_t primitive;
        const char* fallback_name;
        const char* label;
    };

    const SpeechCase speech_cases[] = {
        {RAC_PRIMITIVE_TRANSCRIBE, "fallback_stt", "STT"},
        {RAC_PRIMITIVE_SYNTHESIZE, "fallback_tts", "TTS"},
        {RAC_PRIMITIVE_DETECT_VOICE, "fallback_vad", "VAD"},
    };

    for (const auto& c : speech_cases) {
        auto fallback = make_vt(c.fallback_name, 10, c.primitive);
        auto sherpa_shell = make_vt("sherpa", 70, RAC_PRIMITIVE_UNSPECIFIED,
                                    backend_unavailable_capability_check);

        CHECK(rac_plugin_register(&fallback) == RAC_SUCCESS,
              "speech fallback registers");
        CHECK(rac_plugin_register(&sherpa_shell) == RAC_ERROR_CAPABILITY_UNSUPPORTED,
              "Sherpa shell is rejected before speech ops are wired");
        CHECK(route_is(router, c.primitive, &fallback),
              "speech route skips Sherpa shell");

        auto sherpa_ready = make_vt("sherpa", 90, c.primitive);
        CHECK(rac_plugin_register(&sherpa_ready) == RAC_SUCCESS,
              "Sherpa registers after real speech op is present");
        CHECK(route_is(router, c.primitive, &sherpa_ready),
              c.label);

        cleanup("sherpa");
        cleanup(c.fallback_name);
    }

    std::fprintf(stdout, "\n%d checks, %d failed\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
}
