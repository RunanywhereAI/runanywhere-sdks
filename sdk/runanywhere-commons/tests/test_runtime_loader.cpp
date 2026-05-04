/**
 * @file test_runtime_loader.cpp
 * @brief Smoke test for RAC_STATIC_RUNTIME_REGISTER (task T4.1).
 *
 * Mirrors test_static_registration.cpp for the L1 runtime layer. Verifies:
 *
 *   1. The macro schedules registration BEFORE main() so a runtime built
 *      into the test TU is visible the moment the binary starts.
 *   2. The entry-point function `rac_runtime_entry_<name>()` returns a
 *      stable vtable pointer equal to the one in the registry.
 *   3. A register / unregister / re-register cycle restores visibility with
 *      the original vtable, i.e. destroy() does not permanently damage
 *      shared state.
 *
 * This test runs under BOTH static and shared-plugin builds — the static-init
 * mechanism is independent of dlopen.
 */

#include <cstdio>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_primitive.h"
#include "rac/plugin/rac_runtime_registry.h"
#include "rac/plugin/rac_runtime_vtable.h"

namespace {

bool g_loader_init_called = false;
bool g_loader_destroy_called = false;

rac_result_t loader_init(void) {
    g_loader_init_called = true;
    return RAC_SUCCESS;
}

void loader_destroy(void) {
    g_loader_destroy_called = true;
}

const rac_runtime_vtable_t k_loader_vtable = {
    /* .metadata = */ {
        /* .abi_version             = */ RAC_RUNTIME_ABI_VERSION,
        /* .id                      = */ RAC_RUNTIME_QNN,  /* arbitrary unused id */
        /* .name                    = */ "test_static_runtime",
        /* .display_name            = */ "T4.1 static-register fixture",
        /* .version                 = */ "0.0.0",
        /* .priority                = */ 7,
        /* .supported_formats       = */ nullptr,
        /* .supported_formats_count = */ 0,
        /* .supported_devices       = */ nullptr,
        /* .supported_devices_count = */ 0,
        /* .reserved_0              = */ 0,
        /* .reserved_1              = */ 0,
    },
    /* .init            = */ loader_init,
    /* .destroy         = */ loader_destroy,
    /* .create_session  = */ nullptr,
    /* .run_session     = */ nullptr,
    /* .destroy_session = */ nullptr,
    /* .alloc_buffer    = */ nullptr,
    /* .free_buffer     = */ nullptr,
    /* .device_info     = */ nullptr,
    /* .capabilities    = */ nullptr,
    /* .reserved_slot_0 = */ nullptr,
    /* .reserved_slot_1 = */ nullptr,
    /* .reserved_slot_2 = */ nullptr,
    /* .reserved_slot_3 = */ nullptr,
    /* .reserved_slot_4 = */ nullptr,
    /* .reserved_slot_5 = */ nullptr,
};

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

}  // namespace

extern "C" RAC_RUNTIME_ENTRY_DEF(test_static_runtime) {
    return &k_loader_vtable;
}

RAC_STATIC_RUNTIME_REGISTER(test_static_runtime);

int main() {
    std::fprintf(stdout, "test_runtime_loader\n");

    /* (1) Pre-main registration: the fixture's init() ran during static init
     *     and the vtable is already in the registry. */
    CHECK(g_loader_init_called,
          "(1) init() ran before main (RAC_STATIC_RUNTIME_REGISTER fired)");

    const rac_runtime_vtable_t* found = rac_runtime_get_by_id(RAC_RUNTIME_QNN);
    CHECK(found == &k_loader_vtable,
          "(1) registry entry matches the statically-registered vtable");

    /* (2) Entry-point returns the same vtable address. */
    CHECK(rac_runtime_entry_test_static_runtime() == &k_loader_vtable,
          "(2) rac_runtime_entry_<name> returns the vtable pointer");

    /* (3) Unregister → re-register cycle preserves vtable identity. */
    g_loader_destroy_called = false;
    g_loader_init_called = false;

    CHECK(rac_runtime_unregister(RAC_RUNTIME_QNN) == RAC_SUCCESS,
          "(3) unregister returns RAC_SUCCESS");
    CHECK(g_loader_destroy_called,
          "(3) destroy() fires during unregister");
    CHECK(rac_runtime_get_by_id(RAC_RUNTIME_QNN) == nullptr,
          "(3) lookup NULL after unregister");

    CHECK(rac_runtime_register(&k_loader_vtable) == RAC_SUCCESS,
          "(3) re-register after unregister succeeds");
    CHECK(g_loader_init_called,
          "(3) init() fires on re-register");
    CHECK(rac_runtime_get_by_id(RAC_RUNTIME_QNN) == &k_loader_vtable,
          "(3) vtable pointer stable across re-register cycle");

    /* Leave the registry clean. */
    rac_runtime_unregister(RAC_RUNTIME_QNN);

    std::fprintf(stdout, "\n%d checks, %d failed\n", g_test_count, g_fail_count);
    return g_fail_count == 0 ? 0 : 1;
}
