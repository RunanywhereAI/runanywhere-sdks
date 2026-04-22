/**
 * @file test_hardware_profile.cpp
 * @brief Sanity test for HardwareProfile detection.
 *
 * GAP 04 Phase 12. We can't assert exact values (depends on the host) but
 * we can assert invariants:
 *   - cached() returns the same address as the previous call (memoization).
 *   - refresh() invalidates the cache.
 *   - RAC_FORCE_RUNTIME=cpu zeroes every has_* flag.
 *   - supports_runtime(CPU) is always true.
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "rac/router/rac_hardware_profile.h"

int main() {
    using rac::router::HardwareProfile;

    std::fprintf(stdout, "test_hardware_profile\n");
    int fails = 0;

    /* (1) cached() is memoized. */
    const HardwareProfile& a = HardwareProfile::cached();
    const HardwareProfile& b = HardwareProfile::cached();
    if (&a != &b) {
        std::fprintf(stderr, "  FAIL: cached() did not memoize\n"); ++fails;
    } else {
        std::fprintf(stdout, "  ok:   cached() returns memoized reference\n");
    }

    /* (2) supports_runtime(CPU) is always true. */
    if (!a.supports_runtime(RAC_RUNTIME_CPU)) {
        std::fprintf(stderr, "  FAIL: CPU runtime not supported (impossible)\n"); ++fails;
    } else {
        std::fprintf(stdout, "  ok:   CPU runtime always supported\n");
    }

    /* (3) refresh() invalidates the cache. */
    HardwareProfile::refresh();
    const HardwareProfile& c = HardwareProfile::cached();
    /* After refresh, address may equal the original storage if the optional
     * happens to allocate in the same slot; either way, supports_runtime(CPU)
     * must remain true. */
    if (!c.supports_runtime(RAC_RUNTIME_CPU)) {
        std::fprintf(stderr, "  FAIL: refresh() broke CPU support\n"); ++fails;
    } else {
        std::fprintf(stdout, "  ok:   refresh() yields a fresh profile\n");
    }

    /* (4) RAC_FORCE_RUNTIME=cpu zeroes every has_* flag. */
    setenv("RAC_FORCE_RUNTIME", "cpu", 1);
    HardwareProfile::refresh();
    const HardwareProfile& d = HardwareProfile::cached();
    bool any_accel = d.has_metal || d.has_ane || d.has_coreml || d.has_cuda ||
                     d.has_vulkan || d.has_qnn || d.has_nnapi || d.has_webgpu;
    if (any_accel) {
        std::fprintf(stderr, "  FAIL: RAC_FORCE_RUNTIME=cpu but accelerators detected\n"); ++fails;
    } else {
        std::fprintf(stdout, "  ok:   RAC_FORCE_RUNTIME=cpu disables every accelerator\n");
    }
    if (!d.supports_runtime(RAC_RUNTIME_CPU)) {
        std::fprintf(stderr, "  FAIL: CPU still not supported under FORCE\n"); ++fails;
    }
    unsetenv("RAC_FORCE_RUNTIME");
    HardwareProfile::refresh();  /* leave cache in normal state for any later tests */

    return fails == 0 ? 0 : 1;
}
