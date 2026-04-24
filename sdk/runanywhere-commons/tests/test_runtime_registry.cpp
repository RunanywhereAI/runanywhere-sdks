/**
 * @file test_runtime_registry.cpp
 * @brief Behavioural tests for the L1 runtime-plugin registry (task T4.1).
 *
 * Mirrors the engine registry's test_engine_vtable / test_legacy_coexistence
 * style: pure C++ with no backend deps, links only `rac_commons`, runs on
 * every preset (macos, linux, ios, wasm).
 *
 * Scenarios (matches §8 of RUNTIME_VTABLE_DESIGN.md):
 *   1. register + get_by_id round-trip.
 *   2. unregister removes + subsequent get_by_id returns NULL.
 *   3. NULL vtable / NULL metadata.name / missing init or destroy → rejected.
 *   4. ABI version mismatch → RAC_ERROR_ABI_VERSION_MISMATCH.
 *   5. init() returning non-zero → runtime silently rejected, not in registry.
 *   6. duplicate id with lower priority → RAC_ERROR_PLUGIN_DUPLICATE, existing
 *      entry keeps its slot.
 *   7. duplicate id with higher-or-equal priority → replaces; previous
 *      vtable's destroy() fires.
 *   8. rac_runtime_list returns entries in descending-priority order, bounded
 *      by the caller-supplied `max`, and rac_runtime_count reflects the state.
 *   9. rac_runtime_is_available matches rac_runtime_get_by_id.
 */

#include <cassert>
#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/plugin/rac_runtime_registry.h"
#include "rac/plugin/rac_runtime_vtable.h"

namespace {

int g_test_count = 0;
int g_fail_count = 0;

#define CHECK(cond, label) do { \
    ++g_test_count; \
    if (!(cond)) { \
        ++g_fail_count; \
        std::fprintf(stderr, "  FAIL: %s (%s:%d) — %s\n", \
                     label, __FILE__, __LINE__, #cond); \
    } else { \
        std::fprintf(stdout, "  ok:   %s\n", label); \
    } \
} while (0)

/* Lightweight per-vtable state so we can observe init/destroy callbacks. */
struct VtState {
    int init_calls    = 0;
    int destroy_calls = 0;
    rac_result_t init_result = RAC_SUCCESS;
};

VtState g_states[8] = {};

/* Each vtable references its own VtState index via metadata.reserved_0. */
#define MAKE_OPS(slot)                                              \
    rac_result_t init_##slot(void) {                                \
        g_states[slot].init_calls++;                                \
        return g_states[slot].init_result;                          \
    }                                                               \
    void destroy_##slot(void) { g_states[slot].destroy_calls++; }

MAKE_OPS(0)
MAKE_OPS(1)
MAKE_OPS(2)
MAKE_OPS(3)
MAKE_OPS(4)

/* Build a runtime vtable with explicit slot + priority + id. */
rac_runtime_vtable_t make_vt(int slot, rac_runtime_id_t id, const char* name,
                             int32_t priority,
                             rac_result_t (*init)(void),
                             void (*destroy)(void)) {
    rac_runtime_vtable_t v{};
    v.metadata.abi_version = RAC_RUNTIME_ABI_VERSION;
    v.metadata.id          = id;
    v.metadata.name        = name;
    v.metadata.display_name = name;
    v.metadata.version     = "0.0.0";
    v.metadata.priority    = priority;
    v.metadata.reserved_0  = static_cast<uint64_t>(slot);
    v.init    = init;
    v.destroy = destroy;
    return v;
}

/* Drain any lingering registrations so each block starts clean. Uses a
 * snapshot because rac_runtime_unregister mutates the list. */
void reset_registry() {
    const rac_runtime_vtable_t* buf[32] = {nullptr};
    size_t n = 0;
    rac_runtime_list(buf, 32, &n);
    for (size_t i = 0; i < n; ++i) {
        if (buf[i] != nullptr) rac_runtime_unregister(buf[i]->metadata.id);
    }
}

}  // namespace

int main() {
    std::fprintf(stdout, "test_runtime_registry\n");
    reset_registry();

    /* --- (1) register + get_by_id round-trip ---------------------------- */
    {
        for (auto& s : g_states) s = {};
        auto vt = make_vt(0, RAC_RUNTIME_METAL, "metal_fake", 50,
                          init_0, destroy_0);
        CHECK(rac_runtime_register(&vt) == RAC_SUCCESS,
              "(1) register happy-path returns RAC_SUCCESS");
        CHECK(g_states[0].init_calls == 1,
              "(1) register invokes init exactly once");
        CHECK(rac_runtime_get_by_id(RAC_RUNTIME_METAL) == &vt,
              "(1) get_by_id returns the registered vtable");
        CHECK(rac_runtime_count() == 1,
              "(1) rac_runtime_count reflects one entry");
        rac_runtime_unregister(RAC_RUNTIME_METAL);
    }

    /* --- (2) unregister removes + follow-up lookup returns NULL --------- */
    {
        for (auto& s : g_states) s = {};
        auto vt = make_vt(0, RAC_RUNTIME_CUDA, "cuda_fake", 10,
                          init_0, destroy_0);
        rac_runtime_register(&vt);
        CHECK(rac_runtime_unregister(RAC_RUNTIME_CUDA) == RAC_SUCCESS,
              "(2) unregister returns RAC_SUCCESS");
        CHECK(g_states[0].destroy_calls == 1,
              "(2) unregister invokes destroy exactly once");
        CHECK(rac_runtime_get_by_id(RAC_RUNTIME_CUDA) == nullptr,
              "(2) get_by_id returns NULL after unregister");
        CHECK(rac_runtime_unregister(RAC_RUNTIME_CUDA) == RAC_ERROR_NOT_FOUND,
              "(2) second unregister returns RAC_ERROR_NOT_FOUND");
    }

    /* --- (3) NULL / missing-slot rejections ----------------------------- */
    {
        CHECK(rac_runtime_register(nullptr) == RAC_ERROR_NULL_POINTER,
              "(3) NULL vtable → RAC_ERROR_NULL_POINTER");

        auto vt = make_vt(0, RAC_RUNTIME_VULKAN, nullptr, 0,
                          init_0, destroy_0);
        CHECK(rac_runtime_register(&vt) == RAC_ERROR_INVALID_PARAMETER,
              "(3) NULL metadata.name → RAC_ERROR_INVALID_PARAMETER");

        auto no_init = make_vt(0, RAC_RUNTIME_VULKAN, "vulkan_no_init", 0,
                               nullptr, destroy_0);
        CHECK(rac_runtime_register(&no_init) == RAC_ERROR_INVALID_PARAMETER,
              "(3) NULL init op → RAC_ERROR_INVALID_PARAMETER");

        auto no_dtor = make_vt(0, RAC_RUNTIME_VULKAN, "vulkan_no_dtor", 0,
                               init_0, nullptr);
        CHECK(rac_runtime_register(&no_dtor) == RAC_ERROR_INVALID_PARAMETER,
              "(3) NULL destroy op → RAC_ERROR_INVALID_PARAMETER");
    }

    /* --- (4) ABI version mismatch --------------------------------------- */
    {
        for (auto& s : g_states) s = {};
        auto vt = make_vt(0, RAC_RUNTIME_VULKAN, "vulkan_bad_abi", 0,
                          init_0, destroy_0);
        vt.metadata.abi_version = RAC_RUNTIME_ABI_VERSION + 99u;
        CHECK(rac_runtime_register(&vt) == RAC_ERROR_ABI_VERSION_MISMATCH,
              "(4) bad abi_version → RAC_ERROR_ABI_VERSION_MISMATCH");
        CHECK(g_states[0].init_calls == 0,
              "(4) init() not called when ABI check fails");
        CHECK(rac_runtime_get_by_id(RAC_RUNTIME_VULKAN) == nullptr,
              "(4) rejected runtime absent from registry");
    }

    /* --- (5) init returning non-zero → silent reject -------------------- */
    {
        for (auto& s : g_states) s = {};
        g_states[1].init_result = RAC_ERROR_CAPABILITY_UNSUPPORTED;
        auto vt = make_vt(1, RAC_RUNTIME_NNAPI, "nnapi_gated", 0,
                          init_1, destroy_1);
        CHECK(rac_runtime_register(&vt) == RAC_ERROR_CAPABILITY_UNSUPPORTED,
              "(5) init!=0 → RAC_ERROR_CAPABILITY_UNSUPPORTED");
        CHECK(g_states[1].init_calls == 1,
              "(5) init called once even on rejection");
        CHECK(g_states[1].destroy_calls == 0,
              "(5) destroy NOT called when init failed");
        CHECK(rac_runtime_get_by_id(RAC_RUNTIME_NNAPI) == nullptr,
              "(5) gated runtime absent from registry");
    }

    /* --- (6) duplicate id, lower priority → rejected -------------------- */
    {
        for (auto& s : g_states) s = {};
        auto hi = make_vt(0, RAC_RUNTIME_COREML, "coreml_hi", 100,
                          init_0, destroy_0);
        auto lo = make_vt(1, RAC_RUNTIME_COREML, "coreml_lo",  10,
                          init_1, destroy_1);
        rac_runtime_register(&hi);
        CHECK(rac_runtime_register(&lo) == RAC_ERROR_PLUGIN_DUPLICATE,
              "(6) lower-priority duplicate rejected");
        CHECK(g_states[1].init_calls == 1,
              "(6) duplicate's init() was called (before dedup check)");
        CHECK(g_states[1].destroy_calls == 1,
              "(6) duplicate's destroy() was called to unwind init");
        CHECK(rac_runtime_get_by_id(RAC_RUNTIME_COREML) == &hi,
              "(6) existing higher-priority vtable survives");
        CHECK(g_states[0].destroy_calls == 0,
              "(6) existing vtable was NOT torn down");
        rac_runtime_unregister(RAC_RUNTIME_COREML);
    }

    /* --- (7) duplicate id, equal/higher priority → replaces ------------- */
    {
        for (auto& s : g_states) s = {};
        auto old = make_vt(0, RAC_RUNTIME_CPU, "cpu_old", 10, init_0, destroy_0);
        auto fresh = make_vt(1, RAC_RUNTIME_CPU, "cpu_new", 10, init_1, destroy_1);
        rac_runtime_register(&old);
        CHECK(rac_runtime_register(&fresh) == RAC_SUCCESS,
              "(7) equal-priority duplicate accepted");
        CHECK(g_states[0].destroy_calls == 1,
              "(7) evicted vtable's destroy fires");
        CHECK(rac_runtime_get_by_id(RAC_RUNTIME_CPU) == &fresh,
              "(7) registry now points at the replacement");
        rac_runtime_unregister(RAC_RUNTIME_CPU);
    }

    /* --- (8) list ordering + count + bounded-max semantics -------------- */
    {
        for (auto& s : g_states) s = {};
        auto a = make_vt(0, RAC_RUNTIME_CPU,    "cpu",   10, init_0, destroy_0);
        auto b = make_vt(1, RAC_RUNTIME_METAL,  "metal", 90, init_1, destroy_1);
        auto c = make_vt(2, RAC_RUNTIME_CUDA,   "cuda",  50, init_2, destroy_2);
        rac_runtime_register(&a);
        rac_runtime_register(&b);
        rac_runtime_register(&c);

        CHECK(rac_runtime_count() == 3, "(8) count=3 after 3 registers");

        const rac_runtime_vtable_t* buf[8] = {nullptr};
        size_t n = 0;
        CHECK(rac_runtime_list(buf, 8, &n) == RAC_SUCCESS,
              "(8) list returns RAC_SUCCESS");
        CHECK(n == 3, "(8) list writes all 3 entries when max=8");
        CHECK(buf[0] == &b, "(8) entry 0 = highest priority (metal, 90)");
        CHECK(buf[1] == &c, "(8) entry 1 = mid priority (cuda, 50)");
        CHECK(buf[2] == &a, "(8) entry 2 = lowest priority (cpu, 10)");

        const rac_runtime_vtable_t* small[2] = {nullptr};
        size_t n2 = 99;
        CHECK(rac_runtime_list(small, 2, &n2) == RAC_SUCCESS,
              "(8) list honours max when max < total");
        CHECK(n2 == 2, "(8) list writes exactly max entries");
        CHECK(small[0] == &b && small[1] == &c,
              "(8) list's first max entries are the top-priority ones");

        /* NULL-guard the output pointers. */
        CHECK(rac_runtime_list(nullptr, 8, &n) == RAC_ERROR_NULL_POINTER,
              "(8) list rejects NULL out_runtimes");
        size_t ignored = 0;
        CHECK(rac_runtime_list(buf, 8, nullptr) == RAC_ERROR_NULL_POINTER,
              "(8) list rejects NULL out_count");
        (void)ignored;

        rac_runtime_unregister(RAC_RUNTIME_CPU);
        rac_runtime_unregister(RAC_RUNTIME_METAL);
        rac_runtime_unregister(RAC_RUNTIME_CUDA);
    }

    /* --- (9) rac_runtime_is_available mirrors get_by_id ----------------- */
    {
        for (auto& s : g_states) s = {};
        CHECK(rac_runtime_is_available(RAC_RUNTIME_CPU) == 0,
              "(9) is_available=false when nothing registered");
        auto vt = make_vt(0, RAC_RUNTIME_CPU, "cpu", 0, init_0, destroy_0);
        rac_runtime_register(&vt);
        CHECK(rac_runtime_is_available(RAC_RUNTIME_CPU) == 1,
              "(9) is_available=true after register");
        rac_runtime_unregister(RAC_RUNTIME_CPU);
        CHECK(rac_runtime_is_available(RAC_RUNTIME_CPU) == 0,
              "(9) is_available=false after unregister");
    }

    /* Leave the registry clean so subsequent CTest targets run unaffected. */
    reset_registry();

    std::fprintf(stdout, "\n%d checks, %d failed\n", g_test_count, g_fail_count);
    return g_fail_count == 0 ? 0 : 1;
}
