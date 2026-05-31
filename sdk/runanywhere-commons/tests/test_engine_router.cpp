/**
 * @file test_engine_router.cpp
 * @brief 6 deterministic scoring scenarios for the EngineRouter.
 *
 * Success criteria:
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
#include "rac/plugin/rac_model_format_ids.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/plugin/rac_runtime_registry.h"
#include "rac/plugin/rac_runtime_vtable.h"
#include "rac/router/rac_engine_router.h"
#include "rac/router/rac_hardware_abi.h"
#include "rac/router/rac_hardware_profile.h"
#include "rac/router/rac_route.h"

namespace {

const int k_sentinel = 0xCAFE;

/* Build a vtable with the given metadata (helper). */
rac_result_t backend_unavailable_capability_check() {
    return RAC_ERROR_BACKEND_UNAVAILABLE;
}

rac_result_t runtime_ok_init() {
    return RAC_SUCCESS;
}

void runtime_noop_destroy() {}

const rac_runtime_vtable_v2_t k_noop_runtime_v2 = {
    /* .abi_version    = */ RAC_RUNTIME_ABI_VERSION_V2,
    /* .struct_size    = */ sizeof(rac_runtime_vtable_v2_t),
    /* .run_session_v2 = */ nullptr,
    /* .alloc_buffer   = */ nullptr,
    /* .buffer_info    = */ nullptr,
    /* .map_buffer     = */ nullptr,
    /* .unmap_buffer   = */ nullptr,
    /* .copy_buffer    = */ nullptr,
    /* .release_tensor = */ nullptr,
    /* .reserved_0     = */ nullptr,
    /* .reserved_1     = */ nullptr,
    /* .reserved_2     = */ nullptr,
    /* .reserved_3     = */ nullptr,
    /* .reserved_4     = */ nullptr,
    /* .reserved_5     = */ nullptr,
    /* .reserved_6     = */ nullptr,
    /* .reserved_7     = */ nullptr,
};

rac_runtime_vtable_t make_runtime_vt(rac_runtime_id_t id, const char* name,
                                     int32_t priority = 100) {
    rac_runtime_vtable_t v{};
    v.metadata.abi_version = RAC_RUNTIME_ABI_VERSION;
    v.metadata.id = id;
    v.metadata.name = name;
    v.metadata.display_name = name;
    v.metadata.priority = priority;
    v.init = runtime_ok_init;
    v.destroy = runtime_noop_destroy;
    v.reserved_slot_0 = &k_noop_runtime_v2;
    return v;
}

rac_engine_vtable_t make_vt(const char* name, int32_t priority, const rac_runtime_id_t* rts,
                            size_t rts_n, const uint32_t* fmts, size_t fmts_n,
                            rac_result_t (*capability_check)() = nullptr) {
    rac_engine_vtable_t v{};
    v.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    v.metadata.name = name;
    v.metadata.display_name = name;
    v.metadata.engine_version = "0.0.0";
    v.metadata.priority = priority;
    v.metadata.runtimes = rts;
    v.metadata.runtimes_count = rts_n;
    v.metadata.formats = fmts;
    v.metadata.formats_count = fmts_n;
    v.capability_check = capability_check;
    /* Single sentinel pointer reused for all primitive slots — never deref'd. */
    v.llm_ops = reinterpret_cast<const struct rac_llm_service_ops*>(&k_sentinel);
    return v;
}

int test_count = 0, fail_count = 0;
#define CHECK(cond, label)                                                                       \
    do {                                                                                         \
        ++test_count;                                                                            \
        if (!(cond)) {                                                                           \
            ++fail_count;                                                                        \
            std::fprintf(stderr, "  FAIL: %s (%s:%d) — %s\n", label, __FILE__, __LINE__, #cond); \
        } else {                                                                                 \
            std::fprintf(stdout, "  ok:   %s\n", label);                                         \
        }                                                                                        \
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
        const rac_runtime_id_t cpu[] = {RAC_RUNTIME_CPU};
        auto rt_metal = make_runtime_vt(RAC_RUNTIME_METAL, "metal-test");
        rac_runtime_register(&rt_metal);
        auto v_metal = make_vt("metal_engine", 50, metal, 1, nullptr, 0);
        auto v_cpu = make_vt("cpu_engine", 50, cpu, 1, nullptr, 0);
        rac_plugin_register(&v_metal);
        rac_plugin_register(&v_cpu);

        rac::router::RouteRequest req;
        req.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
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
        prof.has_ane = true;
        prof.has_coreml = true;
        prof.has_metal = true;
        rac::router::EngineRouter router(prof);

        const rac_runtime_id_t ane_rts[] = {RAC_RUNTIME_COREML, RAC_RUNTIME_ANE};
        const rac_runtime_id_t onnx_rts[] = {RAC_RUNTIME_ONNXRT};
        auto rt_ane = make_runtime_vt(RAC_RUNTIME_ANE, "ane-test");
        auto rt_onnxrt = make_runtime_vt(RAC_RUNTIME_ONNXRT, "onnxrt-test");
        rac_runtime_register(&rt_ane);
        rac_runtime_register(&rt_onnxrt);
        auto v_wkit = make_vt("whisperkit_coreml", 110, ane_rts, 2, nullptr, 0);
        auto v_onnx = make_vt("onnx", 80, onnx_rts, 1, nullptr, 0);
        rac_plugin_register(&v_wkit);
        rac_plugin_register(&v_onnx);

        rac::router::RouteRequest req;
        req.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
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

        auto v_low = make_vt("forced", 10, nullptr, 0, nullptr, 0);
        auto v_high = make_vt("would_win", 1000, nullptr, 0, nullptr, 0);
        rac_plugin_register(&v_low);
        rac_plugin_register(&v_high);

        rac::router::RouteRequest req;
        req.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
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
        req.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
        req.pinned_engine = "absent";
        req.no_fallback = true;
        auto result = router.route(req);
        CHECK(result.vtable == nullptr, "(4) no_fallback + missing pin → no plugin");
        CHECK(!result.rejection_reason.empty(), "(4) router populates rejection_reason");

        rac_plugin_unregister("present");
    }

    /* --- (5) Determinism — 1000 calls same input → same winner ----------- */
    {
        rac::router::HardwareProfile prof{};
        rac::router::EngineRouter router(prof);

        auto a = make_vt("a", 50, nullptr, 0, nullptr, 0);
        auto b = make_vt("b", 50, nullptr, 0, nullptr, 0); /* tied with a on score */
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
                deterministic = false;
                break;
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
        req.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
        req.preferred_runtime = RAC_RUNTIME_METAL; /* ignored — neither declares it */
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
        const uint32_t onnx_fmt[] = {RAC_MODEL_FORMAT_ID_ONNX};
        auto rt_qnn = make_runtime_vt(RAC_RUNTIME_QNN, "qnn-test");
        rac_runtime_register(&rt_qnn);

        auto registered = make_vt("registered_runtime", 20, qnn_rts, 1, onnx_fmt, 1);
        auto missing = make_vt("missing_runtime", 200, cuda_rts, 1, onnx_fmt, 1);
        rac_plugin_register(&registered);
        rac_plugin_register(&missing);

        rac::router::RouteRequest req;
        req.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
        req.preferred_runtime = RAC_RUNTIME_QNN;
        req.format = RAC_MODEL_FORMAT_ID_ONNX;
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
        auto diffusion = make_vt("diffusion_coreml", 100, coreml_rts, 2, nullptr, 0);
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

        rac_plugin_unregister("diffusion_coreml");
        rac_plugin_unregister("whisperkit_coreml");
    }

    /* --- (bonus) C ABI wrapper smoke test -------------------------------- */
    {
        auto v = make_vt("c_abi_smoke", 75, nullptr, 0, nullptr, 0);
        rac_plugin_register(&v);

        const rac_engine_vtable_t* out = nullptr;
        rac_result_t rc = rac_plugin_route(RAC_PRIMITIVE_GENERATE_TEXT, 0, nullptr, &out);
        CHECK(rc == RAC_SUCCESS, "(C) rac_plugin_route returns RAC_SUCCESS");
        CHECK(out == &v, "(C) rac_plugin_route returns the registered vt");

        rac_plugin_unregister("c_abi_smoke");
    }

    /* --- Runtime availability gating ---------------------------- */
    /*
     * Hard-reject contract: when an engine declares one or more L1 runtimes
     * and NONE of them are registered with the runtime registry, the router
     * must drop it from candidate selection — this is a hard filter, not a
     * scoring penalty. When every candidate fails this filter, the C ABI
     * surfaces a dedicated `RAC_ERROR_RUNTIME_UNAVAILABLE` so callers can
     * distinguish a runtime-mismatch from "no plugin registered at all".
     */

    /* Engine declares Metal-only; only CPU is registered → reject */
    {
        rac::router::HardwareProfile prof{};
        rac::router::EngineRouter router(prof);

        const rac_runtime_id_t metal_only[] = {RAC_RUNTIME_METAL};
        auto v = make_vt("metal_only_engine", 50, metal_only, 1, nullptr, 0);
        rac_plugin_register(&v);

        rac::router::RouteRequest req;
        req.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
        auto result = router.route(req);
        CHECK(result.vtable == nullptr,
              "Metal-only engine rejected when Metal runtime not registered");
        CHECK(!result.rejection_reason.empty(), "router populates rejection_reason");

        const rac_engine_vtable_t* out = nullptr;
        rac_result_t rc = rac_plugin_route(RAC_PRIMITIVE_GENERATE_TEXT, 0, nullptr, &out);
        CHECK(rc == RAC_ERROR_RUNTIME_UNAVAILABLE,
              "rac_plugin_route surfaces RAC_ERROR_RUNTIME_UNAVAILABLE");
        CHECK(out == nullptr, "rac_plugin_route leaves out_vtable NULL on runtime miss");

        rac_plugin_unregister("metal_only_engine");
    }

    /* Engine declares Metal+CPU; only CPU registered → accepted */
    {
        rac::router::HardwareProfile prof{};
        rac::router::EngineRouter router(prof);

        const rac_runtime_id_t metal_cpu[] = {RAC_RUNTIME_METAL, RAC_RUNTIME_CPU};
        auto v = make_vt("multi_runtime_engine", 50, metal_cpu, 2, nullptr, 0);
        rac_plugin_register(&v);

        /* CPU is registered automatically by the bootstrap path inside the
         * runtime registry; no Metal runtime is registered. The engine
         * declares both, so a single-match (CPU) is enough to pass the
         * runtime-availability filter. */
        CHECK(rac_runtime_is_registered(RAC_RUNTIME_CPU) == 1,
              "CPU runtime is registered via bootstrap");
        CHECK(rac_runtime_is_registered(RAC_RUNTIME_METAL) == 0,
              "Metal runtime is not registered");

        rac::router::RouteRequest req;
        req.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
        auto result = router.route(req);
        CHECK(result.vtable == &v,
              "engine accepted when at least one declared runtime is registered");

        rac_plugin_unregister("multi_runtime_engine");
    }

    /* Engine declares no runtimes → priority-only scoring */
    {
        rac::router::HardwareProfile prof{};
        rac::router::EngineRouter router(prof);

        /* Two engines, both with NULL runtimes; the higher-priority one wins
         * regardless of registered runtimes. Confirms the runtime-availability
         * filter only applies when `metadata.runtimes != NULL`. */
        auto v_lo = make_vt("legacy_lo", 10, nullptr, 0, nullptr, 0);
        auto v_hi = make_vt("legacy_hi", 90, nullptr, 0, nullptr, 0);
        rac_plugin_register(&v_lo);
        rac_plugin_register(&v_hi);

        rac::router::RouteRequest req;
        req.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
        auto result = router.route(req);
        CHECK(result.vtable == &v_hi,
              "legacy NULL-runtime engines bypass runtime check, "
              "highest-priority wins");
        CHECK(result.score == 90,
              "legacy engines score on priority alone (no runtime bonus)");

        rac_plugin_unregister("legacy_lo");
        rac_plugin_unregister("legacy_hi");
    }

    /* Two engines compete: CoreML-only (unavailable) vs CPU
     *            (available). Even when CoreML engine has higher priority,
     *            the CPU one wins because the router hard-rejects engines
     *            whose runtimes aren't registered. */
    {
        rac::router::HardwareProfile prof{};
        rac::router::EngineRouter router(prof);

        const rac_runtime_id_t coreml_rts[] = {RAC_RUNTIME_COREML};
        const rac_runtime_id_t cpu_rts[] = {RAC_RUNTIME_CPU};

        auto v_coreml = make_vt("coreml_high_prio", 500, coreml_rts, 1, nullptr, 0);
        auto v_cpu = make_vt("cpu_low_prio", 10, cpu_rts, 1, nullptr, 0);
        rac_plugin_register(&v_coreml);
        rac_plugin_register(&v_cpu);

        CHECK(rac_runtime_is_registered(RAC_RUNTIME_COREML) == 0,
              "CoreML runtime is not registered on this host");

        rac::router::RouteRequest req;
        req.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
        auto result = router.route(req);
        CHECK(result.vtable == &v_cpu,
              "CPU engine wins over higher-priority CoreML engine "
              "when CoreML is unavailable");

        /* Confirm the rejection scoring keeps the CoreML engine out of the
         * candidate set (route_all surfaces every plugin including rejects). */
        auto all = router.route_all(req);
        bool saw_coreml_rejected = false;
        for (const auto& item : all) {
            if (item.vtable == &v_coreml && item.score <= -1000) {
                saw_coreml_rejected = true;
            }
        }
        CHECK(saw_coreml_rejected,
              "CoreML engine appears in route_all() with reject score");

        rac_plugin_unregister("coreml_high_prio");
        rac_plugin_unregister("cpu_low_prio");
    }

    /* When the only LLM-serving plugin's runtimes are unavailable
     *            the C ABI surfaces RAC_ERROR_RUNTIME_UNAVAILABLE. A second
     *            engine that serves a different primitive (STT) does not
     *            interfere because it is filed under a different bucket. */
    {
        rac::router::HardwareProfile prof{};
        rac::router::EngineRouter router(prof);

        const rac_runtime_id_t cuda_rts[] = {RAC_RUNTIME_CUDA};
        auto v_cuda = make_vt("cuda_only_engine", 50, cuda_rts, 1, nullptr, 0);
        rac_plugin_register(&v_cuda);

        /* Engine that serves STT, never LLM — primitive bucket isolation. */
        auto v_stt = make_vt("stt_only_engine", 50, nullptr, 0, nullptr, 0);
        v_stt.llm_ops = nullptr;
        v_stt.stt_ops = reinterpret_cast<const struct rac_stt_service_ops*>(&k_sentinel);
        rac_plugin_register(&v_stt);

        const rac_engine_vtable_t* out = nullptr;
        rac_result_t rc = rac_plugin_route(RAC_PRIMITIVE_GENERATE_TEXT, 0, nullptr, &out);
        CHECK(rc == RAC_ERROR_RUNTIME_UNAVAILABLE,
              "C ABI returns RAC_ERROR_RUNTIME_UNAVAILABLE when "
              "all LLM candidates are runtime-rejected");
        CHECK(out == nullptr, "C ABI leaves out_vtable NULL on runtime rejection");

        rac_plugin_unregister("cuda_only_engine");
        rac_plugin_unregister("stt_only_engine");
    }

    /* rac_runtime_is_registered alias matches rac_runtime_is_available */
    {
        /* CPU is bootstrapped lazily on first registry touch — calling either
         * accessor triggers the bootstrap, so both must agree afterwards. */
        int avail = rac_runtime_is_available(RAC_RUNTIME_CPU);
        int reg = rac_runtime_is_registered(RAC_RUNTIME_CPU);
        CHECK(avail == reg,
              "rac_runtime_is_registered mirrors rac_runtime_is_available");
        CHECK(reg == 1, "CPU runtime is registered after bootstrap");

        /* An obviously-not-registered id should report 0 from both. */
        CHECK(rac_runtime_is_registered(RAC_RUNTIME_CUDA) == 0,
              "unregistered CUDA reports 0");
        CHECK(rac_runtime_is_available(RAC_RUNTIME_CUDA) == 0,
              "unregistered CUDA reports 0 from available alias too");
    }

    /* Pinned engine whose declared runtimes are all unregistered
     *            must still be hard-rejected — pinning is not an escape hatch
     *            from the runtime-unavailable contract. Covers both the
     *            EngineRouter::route path and the rac_plugin_route C ABI with
     *            no_fallback=true so model_lifecycle's framework-pinned loads
     *            cannot select a non-executable engine.
     *
     *            Also register a second LLM-serving engine that does NOT match
     *            the pin name. Pre-fix the router
     *            would emit RAC_ERROR_NOT_FOUND because the non-pin engine's
     *            pin-mismatch rejection set `any_other_reject=true` and the
     *            runtime-unavailable branch only fired when EVERY rejection
     *            was a runtime-reject. Post-fix the pinned engine's own
     *            runtime-rejection takes precedence over the pin-mismatch
     *            noise, so the C ABI must still surface
     *            RAC_ERROR_RUNTIME_UNAVAILABLE. */
    {
        rac::router::HardwareProfile prof{};
        rac::router::EngineRouter router(prof);

        const rac_runtime_id_t cuda_rts[] = {RAC_RUNTIME_CUDA};
        auto v_pin = make_vt("cuda_pinned_engine", 50, cuda_rts, 1, nullptr, 0);
        rac_plugin_register(&v_pin);

        CHECK(rac_runtime_is_registered(RAC_RUNTIME_CUDA) == 0,
              "CUDA runtime is not registered on this host");

        rac::router::RouteRequest req;
        req.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
        req.pinned_engine = "cuda_pinned_engine";
        req.no_fallback = true;
        auto result = router.route(req);
        CHECK(result.vtable == nullptr,
              "pinned engine with unregistered declared runtime is rejected");

        rac_routing_hints_t hints = {};
        hints.preferred_engine_name = "cuda_pinned_engine";
        hints.no_fallback = 1;
        const rac_engine_vtable_t* out = nullptr;
        rac_result_t rc = rac_plugin_route(RAC_PRIMITIVE_GENERATE_TEXT, 0, &hints, &out);
        CHECK(rc == RAC_ERROR_RUNTIME_UNAVAILABLE,
              "C ABI surfaces RAC_ERROR_RUNTIME_UNAVAILABLE for pinned "
              "engine when its declared runtime is unregistered");
        CHECK(out == nullptr,
              "C ABI leaves out_vtable NULL on pinned runtime rejection");

        /* Introduce a second LLM-serving engine that doesn't
         * match the pin name. Without the fix, the pin-mismatch rejection
         * would set `any_other_reject = true` and demote the failure to
         * NOT_FOUND. */
        auto v_other = make_vt("other_llm_engine", 10, nullptr, 0, nullptr, 0);
        rac_plugin_register(&v_other);
        const rac_engine_vtable_t* out2 = nullptr;
        rac_result_t rc2 = rac_plugin_route(RAC_PRIMITIVE_GENERATE_TEXT, 0, &hints, &out2);
        CHECK(rc2 == RAC_ERROR_RUNTIME_UNAVAILABLE,
              "pinned engine's runtime-rejection wins over "
              "non-pin candidates' pin-mismatch rejection");
        CHECK(out2 == nullptr, "C ABI still leaves out_vtable NULL");
        rac_plugin_unregister("other_llm_engine");

        rac_plugin_unregister("cuda_pinned_engine");
    }

    /* --- (bonus) Genie SDK-absent plugins are not routable --------------- */
    {
        rac::router::HardwareProfile prof{};
        prof.has_qnn = true;
        rac::router::EngineRouter router(prof);

        const rac_runtime_id_t qnn_rts[] = {RAC_RUNTIME_QNN};
        const uint32_t onnx_fmt[] = {RAC_MODEL_FORMAT_ID_ONNX};
        auto fallback = make_vt("fallback_llm", 10, nullptr, 0, nullptr, 0);
        auto genie_without_sdk =
            make_vt("genie", 200, qnn_rts, 1, onnx_fmt, 1, backend_unavailable_capability_check);

        CHECK(rac_plugin_register(&fallback) == RAC_SUCCESS, "(G) fallback LLM registers");
        CHECK(rac_plugin_register(&genie_without_sdk) == RAC_ERROR_CAPABILITY_UNSUPPORTED,
              "(G) Genie without SDK is rejected during registration");

        rac::router::RouteRequest req;
        req.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
        req.preferred_runtime = RAC_RUNTIME_QNN;
        req.format = RAC_MODEL_FORMAT_ID_ONNX;
        CHECK(rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == &fallback,
              "(G) SDK-absent Genie is not in the primitive registry");
        auto result = router.route(req);
        CHECK(result.vtable == &fallback,
              "(G) LLM route does not select SDK-absent Genie despite QNN hints");

        req.pinned_engine = "genie";
        req.no_fallback = true;
        result = router.route(req);
        CHECK(result.vtable == nullptr, "(G) pinned SDK-absent Genie still has no route");

        rac_plugin_unregister("fallback_llm");
        rac_plugin_unregister("genie");
    }

    /* --- Accelerator preference steers GPU vs CPU winner --------- *
     * Two engines serve the same primitive with identical priority but
     * distinct declared runtimes (one Metal-only, one CPU-only). When the
     * process-wide accelerator preference is set to GPU via the public C
     * ABI, the router must surface the Metal engine; when switched to CPU,
     * the CPU engine wins. Covers `rac_hardware_set_accelerator_preference`
     * end-to-end through the scoring path. */
    {
        rac::router::HardwareProfile prof{};
        prof.has_metal = true;
        rac::router::EngineRouter router(prof);

        const rac_runtime_id_t metal_rts[] = {RAC_RUNTIME_METAL};
        const rac_runtime_id_t cpu_rts[] = {RAC_RUNTIME_CPU};
        auto rt_metal = make_runtime_vt(RAC_RUNTIME_METAL, "metal-pref-test");
        rac_runtime_register(&rt_metal);

        auto v_gpu = make_vt("gpu_engine", 50, metal_rts, 1, nullptr, 0);
        auto v_cpu = make_vt("cpu_engine", 50, cpu_rts, 1, nullptr, 0);
        rac_plugin_register(&v_gpu);
        rac_plugin_register(&v_cpu);

        rac::router::RouteRequest req;
        req.primitive = RAC_PRIMITIVE_GENERATE_TEXT;
        /* No per-request preferred_runtime — steering comes solely from the
         * process-wide accelerator preference. */

        /* ACCELERATION_PREFERENCE_GPU (proto value 3) — GPU engine wins. */
        CHECK(rac_hardware_set_accelerator_preference(3) == RAC_SUCCESS,
              "setter accepts ACCELERATION_PREFERENCE_GPU");
        auto gpu_result = router.route(req);
        CHECK(gpu_result.vtable == &v_gpu,
              "GPU preference selects Metal-declaring engine");
        CHECK(gpu_result.score > v_cpu.metadata.priority + 40,
              "GPU-preferred score exceeds CPU engine's base + runtime weight");

        /* ACCELERATION_PREFERENCE_CPU (proto value 2) — CPU engine wins. */
        CHECK(rac_hardware_set_accelerator_preference(2) == RAC_SUCCESS,
              "setter accepts ACCELERATION_PREFERENCE_CPU");
        auto cpu_result = router.route(req);
        CHECK(cpu_result.vtable == &v_cpu, "CPU preference selects CPU-declaring engine");
        CHECK(cpu_result.score > v_gpu.metadata.priority + 40,
              "CPU-preferred score exceeds GPU engine's base + runtime weight");

        /* Reset to AUTO (proto value 1) so later tests in the process run
         * with no preference steering. Tied scores fall back to the
         * deterministic tiebreak (priority desc → name asc → "cpu_engine"). */
        CHECK(rac_hardware_set_accelerator_preference(1) == RAC_SUCCESS,
              "setter accepts ACCELERATION_PREFERENCE_AUTO (reset)");
        auto tie_result = router.route(req);
        CHECK(tie_result.vtable == &v_cpu,
              "AUTO preference leaves scoring to priority+tiebreak");

        /* Out-of-range preference rejected (validator clamps to 0..3). */
        CHECK(rac_hardware_set_accelerator_preference(-1) == RAC_ERROR_INVALID_ARGUMENT,
              "setter rejects negative preference");
        CHECK(rac_hardware_set_accelerator_preference(99) == RAC_ERROR_INVALID_ARGUMENT,
              "setter rejects out-of-range preference");

        /* Leave the global preference at UNSPECIFIED=0 so we don't leak
         * state into any future router-test binary invocation. */
        rac_hardware_set_accelerator_preference(0);

        rac_plugin_unregister("gpu_engine");
        rac_plugin_unregister("cpu_engine");
        rac_runtime_unregister(RAC_RUNTIME_METAL);
    }

    std::fprintf(stdout, "\n%d checks, %d failed\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
}
