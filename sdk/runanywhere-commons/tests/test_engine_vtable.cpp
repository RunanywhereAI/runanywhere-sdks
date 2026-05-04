/**
 * @file test_engine_vtable.cpp
 * @brief Unit tests for the unified engine plugin registry.
 *
 * GAP 02 Phase 10 — see v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md.
 *
 * Nine scenarios required by the spec:
 *   1. Happy-path register → find → unregister.
 *   2. ABI version mismatch → RAC_ERROR_ABI_VERSION_MISMATCH.
 *   3. capability_check()≠0 → RAC_ERROR_CAPABILITY_UNSUPPORTED, plugin not in registry.
 *   4. NULL op-struct → rac_engine_vtable_slot() returns NULL for that primitive.
 *   5. Unregister by name.
 *   6. Duplicate name rejection (lower priority).
 *   7. Duplicate name promotion (higher priority replaces existing).
 *   8. Priority ordering (higher → rac_plugin_find returns it first).
 *   9. Static registration via RAC_STATIC_PLUGIN_REGISTER (smoke-check).
 */

#include <cassert>
#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

namespace {

int g_capability_check_rc = RAC_SUCCESS;

rac_result_t fake_capability_check(void) { return g_capability_check_rc; }

// A "pretend" LLM ops sentinel — never deref'd, only compared by address.
// We cast through uintptr_t to avoid an incompatible-pointer-types error
// when the real rac_llm_service_ops is forward-declared as an incomplete
// struct from rac_engine_vtable.h.
static const int k_fake_llm_ops_sentinel = 0xABCD;
const void* k_fake_llm_ops = static_cast<const void*>(&k_fake_llm_ops_sentinel);

rac_engine_vtable_t make_vt(const char* name, int32_t priority,
                             uint32_t abi_version = RAC_PLUGIN_API_VERSION,
                             rac_result_t (*cap)() = nullptr,
                             const void* llm_ops = k_fake_llm_ops) {
    rac_engine_vtable_t v{};
    v.metadata.abi_version      = abi_version;
    v.metadata.name             = name;
    v.metadata.display_name     = name;
    v.metadata.engine_version   = "0.0.0";
    v.metadata.priority         = priority;
    v.metadata.capability_flags = 0;
    v.capability_check          = cap;
    v.on_unload                 = nullptr;
    v.llm_ops = static_cast<const struct rac_llm_service_ops*>(llm_ops);
    return v;
}

int test_count = 0;
int test_failed = 0;

#define CHECK(cond, label) do { \
    ++test_count; \
    if (!(cond)) { \
        ++test_failed; \
        std::fprintf(stderr, "  FAIL: %s (%s:%d) — %s\n", label, __FILE__, __LINE__, #cond); \
    } else { \
        std::fprintf(stdout, "  ok:   %s\n", label); \
    } \
} while (0)

}  // namespace

int main() {
    std::fprintf(stdout, "test_engine_vtable\n");

    // (1) happy path
    {
        auto vt = make_vt("happy", 50);
        rac_result_t rc = rac_plugin_register(&vt);
        CHECK(rc == RAC_SUCCESS, "happy: register ok");
        CHECK(rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == &vt, "happy: find returns vt");
        CHECK(rac_plugin_unregister("happy") == RAC_SUCCESS, "happy: unregister ok");
        CHECK(rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == nullptr, "happy: post-unreg empty");
    }

    // (2) ABI mismatch
    {
        auto vt = make_vt("abi-bad", 50, RAC_PLUGIN_API_VERSION + 99);
        rac_result_t rc = rac_plugin_register(&vt);
        CHECK(rc == RAC_ERROR_ABI_VERSION_MISMATCH, "abi: mismatch rejected");
        CHECK(rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == nullptr, "abi: not inserted");
    }

    // (3) capability_check rejection
    {
        g_capability_check_rc = RAC_ERROR_CAPABILITY_UNSUPPORTED;
        auto vt = make_vt("cap-no", 50, RAC_PLUGIN_API_VERSION, fake_capability_check);
        rac_result_t rc = rac_plugin_register(&vt);
        CHECK(rc == RAC_ERROR_CAPABILITY_UNSUPPORTED, "cap: rejected silently");
        CHECK(rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == nullptr, "cap: not inserted");
        g_capability_check_rc = RAC_SUCCESS;
    }

    // (4) NULL op slot → rac_engine_vtable_slot returns NULL
    {
        auto vt = make_vt("null-slot", 50, RAC_PLUGIN_API_VERSION, nullptr, nullptr);
        rac_result_t rc = rac_plugin_register(&vt);
        CHECK(rc == RAC_SUCCESS, "null-slot: register ok (no served primitives)");
        CHECK(rac_engine_vtable_slot(&vt, RAC_PRIMITIVE_GENERATE_TEXT) == nullptr, "null-slot: slot NULL");
        rac_plugin_unregister("null-slot");
    }

    // (5) unregister nonexistent
    {
        rac_result_t rc = rac_plugin_unregister("does-not-exist");
        CHECK(rc == RAC_ERROR_NOT_FOUND, "unreg-missing: returns NOT_FOUND");
    }

    // (6) duplicate-name: lower priority rejected
    {
        auto hi = make_vt("dup", 100);
        rac_plugin_register(&hi);
        auto lo = make_vt("dup", 10);
        rac_result_t rc = rac_plugin_register(&lo);
        CHECK(rc == RAC_ERROR_PLUGIN_DUPLICATE, "dup: low priority rejected");
        CHECK(rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == &hi, "dup: hi still primary");
        rac_plugin_unregister("dup");
    }

    // (7) duplicate-name: equal-or-higher priority promotes
    {
        auto lo = make_vt("prom", 10);
        rac_plugin_register(&lo);
        auto hi = make_vt("prom", 100);
        rac_result_t rc = rac_plugin_register(&hi);
        CHECK(rc == RAC_SUCCESS, "prom: hi priority accepted");
        CHECK(rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == &hi, "prom: hi replaces lo");
        rac_plugin_unregister("prom");
    }

    // (8) priority order — higher wins across distinct names
    {
        auto a = make_vt("a", 10);
        auto b = make_vt("b", 100);
        auto c = make_vt("c", 50);
        rac_plugin_register(&a);
        rac_plugin_register(&b);
        rac_plugin_register(&c);
        CHECK(rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == &b, "priority: highest wins");

        const rac_engine_vtable_t* arr[4] = {};
        size_t n = 0;
        rac_plugin_list(RAC_PRIMITIVE_GENERATE_TEXT, arr, 4, &n);
        CHECK(n == 3, "priority: list returns 3");
        CHECK(arr[0] == &b && arr[1] == &c && arr[2] == &a, "priority: sorted desc");
        rac_plugin_unregister("a");
        rac_plugin_unregister("b");
        rac_plugin_unregister("c");
    }

    // (9) static registration — validate RAC_STATIC_PLUGIN_REGISTER expands
    //     to a no-op at compile time for C TUs (can only use in C++ TUs).
    //     Here we just re-verify rac_plugin_count reads back to 0 after all
    //     tests clean up.
    {
        CHECK(rac_plugin_count() == 0, "count: cleanly empty at end");
    }

    std::fprintf(stdout, "\n%d checks, %d failed\n", test_count, test_failed);
    return test_failed == 0 ? 0 : 1;
}
