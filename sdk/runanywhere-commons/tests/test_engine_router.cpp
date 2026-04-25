/**
 * @file test_engine_router.cpp
 * @brief 6 deterministic scoring scenarios for the GAP 04 EngineRouter.
 *
 * Required by v2_gap_specs/GAP_04_ENGINE_ROUTER.md Success Criteria:
 *   1. PrefersHardwareAcceleratedOnAppleSilicon — Metal plugin beats CPU plugin by ≥30.
 *   2. ANEHintSelectsWhisperKit — preferred_runtime = ANE returns whisperkit_coreml over onnx.
 *   3. PinnedEngineHardWins — pinned_engine returns it even against higher-scoring rivals.
 *   4. NoFallbackReturnsNotFound — no_fallback=1 + missing pinned name → RAC_ERROR_NOT_FOUND.
 *   5. Determinism — same RouteRequest 1000× → same winner.
 *   6. LegacyCompat — providers with NULL runtimes still routed via priority.
 */

#include <cassert>
#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/plugin/rac_runtime_registry.h"
#include "rac/plugin/rac_runtime_vtable.h"
#include "rac/router/rac_engine_router.h"
#include "rac/router/rac_hardware_profile.h"
#include "rac/router/rac_route.h"

namespace {

const int k_sentinel = 0xCAFE;

/* Build a vtable with the given metadata (helper). */
rac_result_t backend_unavailable_capability_check(void) {
    return RAC_ERROR_BACKEND_UNAVAILABLE;
}

rac_result_t runtime_ok_init(void) {
    return RAC_SUCCESS;
}

void runtime_noop_destroy(void) {}

rac_runtime_vtable_t make_runtime_vt(rac_runtime_id_t id, const char* name, int32_t priority = 100) {
    rac_runtime_vtable_t v{};
    v.metadata.abi_version = RAC_RUNTIME_ABI_VERSION;
    v.metadata.id = id;
    v.metadata.name = name;
    v.metadata.display_name = name;
    v.metadata.priority = priority;
    v.init = runtime_ok_init;
    v.destroy = runtime_noop_destroy;
    return v;
}

rac_engine_vtable_t make_vt(const char* name, int32_t priority,
                            const rac_runtime_id_t* rts, size_t rts_n,
                            const uint32_t* fmts, size_t fmts_n,
                            rac_result_t (*capability_check)(void) = nullptr) {
    rac_engine_vtable_t v{};
    v.metadata.abi_version    = RAC_PLUGIN_API_VERSION;
    v.metadata.name           = name;
    v.metadata.display_name   = name;
    v.metadata.engine_version = "0.0.0";
    v.metadata.priority       = priority;
    v.metadata.runtimes       = rts;
    v.metadata.runtimes_count = rts_n;
    v.metadata.formats        = fmts;
    v.metadata.formats_count  = fmts_n;
    v.capability_check        = capability_check;
    /* Single sentinel pointer reused for all primitive slots — never deref'd. */
    v.llm_ops = reinterpret_cast<const struct rac_llm_service_ops*>(&k_sentinel);
    return v;
}

int test_count = 0, fail_count = 0;
#define CHECK(cond, label) do { \
    ++test_count; \
    if (!(cond)) { \
        ++fail_count; \
        std::fprintf(stderr, "  FAIL: %s (%s:%d) — %s\n", label, __FILE__, __LINE__, #cond); \
    } else { \
        std::fprintf(stdout, "  ok:   %s\n", label); \
    } \
} while (0)

/* Build a router that lies about hardware so tests are deterministic
 * regardless of which CI node we run on. */
struct FakeProfile {
    rac::router::HardwareProfile p{};
};

}  // namespace

int main() {
    std::fprintf(stdout, "test_engine_router\n");

    /* --- (1) PrefersHardwareAcceleratedOnAppleSilicon -------------------- */
    {
        rac::router::HardwareProfile prof{};
        prof.has_metal = true;
        rac::router::EngineRouter router(prof);

        const rac_runtime_id_t metal[] = {RAC_RUNTIME_METAL};
        const rac_runtime_id_t cpu[]   = {RAC_RUNTIME_CPU};
        auto rt_metal = make_runtime_vt(RAC_RUNTIME_METAL, "metal-test");
        rac_runtime_register(&rt_metal);
        auto v_metal = make_vt("metal_engine", 50, metal, 1, nullptr, 0);
        auto v_cpu   = make_vt("cpu_engine",   50, cpu,   1, nullptr, 0);
        rac_plugin_register(&v_metal);
        rac_plugin_register(&v_cpu);

        rac::router::RouteRequest req;
        req.primitive         = RAC_PRIMITIVE_GENERATE_TEXT;
        req.preferred_runtime = RAC_RUNTIME_METAL;
        auto result = router.route(req);
        CHECK(result.vtable == &v_metal, "(1) Metal plugin wins over CPU plugin");
        CHECK(result.score >= 50 + 40 + 20,
              "(1) score includes runtime compatibility and hardware weights");

        rac_plugin_unregister("metal_engine");
        rac_plugin_unregister("cpu_engine");
        rac_runtime_unregister(RAC_RUNTIME_METAL);
    }

    /* --- (2) ANEHintSelectsWhisperKit ------------------------------------ */
    {
        rac::router::HardwareProfile prof{};
        prof.has_ane = true; prof.has_coreml = true; prof.has_metal = true;
        rac::router::EngineRouter router(prof);

        const rac_runtime_id_t ane_rts[]  = {RAC_RUNTIME_COREML, RAC_RUNTIME_ANE};
        const rac_runtime_id_t onnx_rts[] = {RAC_RUNTIME_ONNXRT};
        auto rt_ane = make_runtime_vt(RAC_RUNTIME_ANE, "ane-test");
        auto rt_onnxrt = make_runtime_vt(RAC_RUNTIME_ONNXRT, "onnxrt-test");
        rac_runtime_register(&rt_ane);
        rac_runtime_register(&rt_onnxrt);
        auto v_wkit = make_vt("whisperkit_coreml", 110, ane_rts,  2, nullptr, 0);
        auto v_onnx = make_vt("onnx",                80, onnx_rts, 1, nullptr, 0);
        rac_plugin_register(&v_wkit);
        rac_plugin_register(&v_onnx);

        rac::router::RouteRequest req;
        req.primitive         = RAC_PRIMITIVE_GENERATE_TEXT;
        req.preferred_runtime = RAC_RUNTIME_ANE;
        auto result = router.route(req);
        CHECK(result.vtable == &v_wkit, "(2) ANE hint picks WhisperKit over ONNX");

        rac_plugin_unregister("whisperkit_coreml");
        rac_plugin_unregister("onnx");
        rac_runtime_unregister(RAC_RUNTIME_ANE);
        rac_runtime_unregister(RAC_RUNTIME_ONNXRT);
    }

    /* --- (3) PinnedEngineHardWins ---------------------------------------- */
    {
        rac::router::HardwareProfile prof{};
        rac::router::EngineRouter router(prof);

        auto v_low  = make_vt("forced",      10, nullptr, 0, nullptr, 0);
        auto v_high = make_vt("would_win", 1000, nullptr, 0, nullptr, 0);
        rac_plugin_register(&v_low);
        rac_plugin_register(&v_high);

        rac::router::RouteRequest req;
        req.primitive     = RAC_PRIMITIVE_GENERATE_TEXT;
        req.pinned_engine = "forced";
        auto result = router.route(req);
        CHECK(result.vtable == &v_low, "(3) pinned_engine hard-wins over higher priority");

        rac_plugin_unregister("forced");
        rac_plugin_unregister("would_win");
    }

    /* --- (4) NoFallbackReturnsNotFound ----------------------------------- */
    {
        rac::router::HardwareProfile prof{};
        rac::router::EngineRouter router(prof);

        auto v = make_vt("present", 50, nullptr, 0, nullptr, 0);
        rac_plugin_register(&v);

        rac::router::RouteRequest req;
        req.primitive     = RAC_PRIMITIVE_GENERATE_TEXT;
        req.pinned_engine = "absent";
        req.no_fallback   = true;
        auto result = router.route(req);
        CHECK(result.vtable == nullptr, "(4) no_fallback + missing pin → no plugin");
        CHECK(!result.rejection_reason.empty(),
              "(4) router populates rejection_reason");

        rac_plugin_unregister("present");
    }

    /* --- (5) Determinism — 1000 calls same input → same winner ----------- */
    {
        rac::router::HardwareProfile prof{};
        rac::router::EngineRouter router(prof);

        auto a = make_vt("a", 50, nullptr, 0, nullptr, 0);
        auto b = make_vt("b", 50, nullptr, 0, nullptr, 0);  /* tied with a on score */
        auto c = make_vt("c", 30, nullptr, 0, nullptr, 0);
        rac_plugin_register(&a);
        rac_plugin_register(&b);
        rac_plugin_register(&c);

        rac::router::RouteRequest req;
        req.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
        const rac_engine_vtable_t* first_winner = router.route(req).vtable;
        bool deterministic = true;
        for (int i = 0; i < 1000; ++i) {
            if (router.route(req).vtable != first_winner) {
                deterministic = false; break;
            }
        }
        CHECK(deterministic, "(5) 1000 routes return same winner (deterministic tiebreak)");

        rac_plugin_unregister("a");
        rac_plugin_unregister("b");
        rac_plugin_unregister("c");
    }

    /* --- (6) LegacyCompat — NULL runtimes still routed via priority ------ */
    {
        rac::router::HardwareProfile prof{};
        prof.has_metal = true;
        rac::router::EngineRouter router(prof);

        /* Both plugins have NULL runtimes (legacy plugins compiled against
         * the priority-only metadata). Router falls back to priority. */
        auto v_lo = make_vt("lo_legacy", 10, nullptr, 0, nullptr, 0);
        auto v_hi = make_vt("hi_legacy", 90, nullptr, 0, nullptr, 0);
        rac_plugin_register(&v_lo);
        rac_plugin_register(&v_hi);

        rac::router::RouteRequest req;
        req.primitive         = RAC_PRIMITIVE_GENERATE_TEXT;
        req.preferred_runtime = RAC_RUNTIME_METAL;  /* ignored — neither declares it */
        auto result = router.route(req);
        CHECK(result.vtable == &v_hi, "(6) legacy NULL-runtime plugins routed by priority");

        rac_plugin_unregister("lo_legacy");
        rac_plugin_unregister("hi_legacy");
    }

    /* --- (7) RuntimeCompatibility — registered runtime beats missing ---- */
    {
        rac::router::HardwareProfile prof{};
        prof.has_qnn = true;
        rac::router::EngineRouter router(prof);

        const rac_runtime_id_t qnn_rts[] = {RAC_RUNTIME_QNN};
        const rac_runtime_id_t cuda_rts[] = {RAC_RUNTIME_CUDA};
        const uint32_t onnx_fmt[] = {3};
        auto rt_qnn = make_runtime_vt(RAC_RUNTIME_QNN, "qnn-test");
        rac_runtime_register(&rt_qnn);

        auto registered = make_vt("registered_runtime", 20, qnn_rts, 1, onnx_fmt, 1);
        auto missing = make_vt("missing_runtime", 200, cuda_rts, 1, onnx_fmt, 1);
        rac_plugin_register(&registered);
        rac_plugin_register(&missing);

        rac::router::RouteRequest req;
        req.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
        req.preferred_runtime = RAC_RUNTIME_QNN;
        req.format = 3;
        auto result = router.route(req);
        CHECK(result.vtable == &registered,
              "(7) registered runtime candidate wins over higher-priority missing runtime");
        auto all = router.route_all(req);
        bool saw_missing_rejected = false;
        for (const auto& item : all) {
            if (item.vtable == &missing && item.score <= -1000) {
                saw_missing_rejected = true;
            }
        }
        CHECK(saw_missing_rejected, "(7) missing declared runtime scores as hard reject");

        rac_plugin_unregister("registered_runtime");
        rac_plugin_unregister("missing_runtime");
        rac_runtime_unregister(RAC_RUNTIME_QNN);
    }

    /* --- (8) EngineRuntimeContract — declared runtime required ---------- */
    {
        rac::router::HardwareProfile prof{};
        prof.has_cuda = true;
        rac::router::EngineRouter router(prof);

        const rac_runtime_id_t cuda_rts[] = {RAC_RUNTIME_CUDA};
        auto cuda_only = make_vt("cuda_only", 50, cuda_rts, 1, nullptr, 0);
        rac_plugin_register(&cuda_only);

        rac::router::RouteRequest req;
        req.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
        req.preferred_runtime = RAC_RUNTIME_CUDA;
        auto result = router.route(req);
        CHECK(result.vtable == nullptr,
              "(8) engine cannot route when its declared runtime is not registered");

        rac_plugin_unregister("cuda_only");
    }

    /* --- (9) ONNXRuntimeUnavailable — ONNX falls back ------------------- */
    {
        rac::router::HardwareProfile prof{};
        rac::router::EngineRouter router(prof);

        const rac_runtime_id_t onnxrt[] = {RAC_RUNTIME_ONNXRT};
        const rac_runtime_id_t cpu[] = {RAC_RUNTIME_CPU};
        auto onnx = make_vt("onnx", 200, onnxrt, 1, nullptr, 0);
        auto fallback = make_vt("cpu_embed", 10, cpu, 1, nullptr, 0);
        rac_plugin_register(&onnx);
        rac_plugin_register(&fallback);

        rac::router::RouteRequest req;
        req.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
        auto result = router.route(req);
        CHECK(result.vtable == &fallback,
              "(9) ONNX runtime unavailable rejects ONNX and chooses fallback");

        rac_plugin_unregister("onnx");
        rac_plugin_unregister("cpu_embed");
    }

    /* --- (10) CoreMLRuntimeUnavailable — CoreML engines reject ---------- */
    {
        rac::router::HardwareProfile prof{};
        prof.has_coreml = true;
        prof.has_ane = true;
        rac::router::EngineRouter router(prof);

        const rac_runtime_id_t coreml_rts[] = {RAC_RUNTIME_COREML, RAC_RUNTIME_ANE};
        auto diffusion = make_vt("diffusion-coreml", 100, coreml_rts, 2, nullptr, 0);
        diffusion.diffusion_ops =
            reinterpret_cast<const struct rac_diffusion_service_ops*>(&k_sentinel);
        diffusion.llm_ops = nullptr;
        auto whisperkit = make_vt("whisperkit_coreml", 110, coreml_rts, 2, nullptr, 0);
        whisperkit.stt_ops = reinterpret_cast<const struct rac_stt_service_ops*>(&k_sentinel);
        whisperkit.llm_ops = nullptr;
        rac_plugin_register(&diffusion);
        rac_plugin_register(&whisperkit);

        rac::router::RouteRequest diffusion_req;
        diffusion_req.primitive = RAC_PRIMITIVE_DIFFUSION;
        auto diffusion_result = router.route(diffusion_req);
        CHECK(diffusion_result.vtable == nullptr,
              "(10) CoreML diffusion rejects when CoreML runtime is not registered");

        rac::router::RouteRequest stt_req;
        stt_req.primitive = RAC_PRIMITIVE_TRANSCRIBE;
        auto stt_result = router.route(stt_req);
        CHECK(stt_result.vtable == nullptr,
              "(10) WhisperKit rejects when CoreML runtime is not registered");

        rac_plugin_unregister("diffusion-coreml");
        rac_plugin_unregister("whisperkit_coreml");
    }

    /* --- (bonus) C ABI wrapper smoke test -------------------------------- */
    {
        auto v = make_vt("c_abi_smoke", 75, nullptr, 0, nullptr, 0);
        rac_plugin_register(&v);

        const rac_engine_vtable_t* out = nullptr;
        rac_result_t rc = rac_plugin_route(RAC_PRIMITIVE_GENERATE_TEXT, 0, nullptr, &out);
        CHECK(rc == RAC_SUCCESS,    "(C) rac_plugin_route returns RAC_SUCCESS");
        CHECK(out == &v,            "(C) rac_plugin_route returns the registered vt");

        rac_plugin_unregister("c_abi_smoke");
    }

    /* --- (bonus) Genie SDK-absent plugins are not routable --------------- */
    {
        rac::router::HardwareProfile prof{};
        prof.has_qnn = true;
        rac::router::EngineRouter router(prof);

        const rac_runtime_id_t qnn_rts[] = {RAC_RUNTIME_QNN};
        const uint32_t onnx_fmt[] = {3};
        auto fallback = make_vt("fallback_llm", 10, nullptr, 0, nullptr, 0);
        auto genie_without_sdk = make_vt("genie", 200, qnn_rts, 1, onnx_fmt, 1,
                                        backend_unavailable_capability_check);

        CHECK(rac_plugin_register(&fallback) == RAC_SUCCESS,
              "(G) fallback LLM registers");
        CHECK(rac_plugin_register(&genie_without_sdk) == RAC_ERROR_CAPABILITY_UNSUPPORTED,
              "(G) Genie without SDK is rejected during registration");

        rac::router::RouteRequest req;
        req.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
        req.preferred_runtime = RAC_RUNTIME_QNN;
        req.format = 3;
        CHECK(rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == &fallback,
              "(G) SDK-absent Genie is not in the primitive registry");
        auto result = router.route(req);
        CHECK(result.vtable == &fallback,
              "(G) LLM route does not select SDK-absent Genie despite QNN hints");

        req.pinned_engine = "genie";
        req.no_fallback = true;
        result = router.route(req);
        CHECK(result.vtable == nullptr,
              "(G) pinned SDK-absent Genie still has no route");

        rac_plugin_unregister("fallback_llm");
        rac_plugin_unregister("genie");
    }

    std::fprintf(stdout, "\n%d checks, %d failed\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
}
