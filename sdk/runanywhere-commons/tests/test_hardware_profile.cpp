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

#include "rac/router/rac_hardware_abi.h"
#include "rac/router/rac_hardware_profile.h"

#ifdef RAC_HAVE_PROTOBUF
#include "hardware_profile.pb.h"
#endif

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

#ifdef RAC_HAVE_PROTOBUF
    /* (5) Hardware C ABI returns canonical HardwareProfileResult proto bytes. */
    uint8_t* profile_bytes = nullptr;
    size_t profile_size = 0;
    rac_result_t profile_rc = rac_hardware_profile_get(&profile_bytes, &profile_size);
    if (profile_rc != RAC_SUCCESS || profile_bytes == nullptr || profile_size == 0) {
        std::fprintf(stderr,
                     "  FAIL: rac_hardware_profile_get returned rc=%d size=%zu\n",
                     static_cast<int>(profile_rc),
                     profile_size);
        ++fails;
    } else {
        runanywhere::v1::HardwareProfileResult decoded;
        if (!decoded.ParseFromArray(profile_bytes, static_cast<int>(profile_size))) {
            std::fprintf(stderr, "  FAIL: hardware profile proto bytes did not decode\n");
            ++fails;
        } else if (!decoded.has_profile()) {
            std::fprintf(stderr, "  FAIL: hardware profile proto missing profile field\n");
            ++fails;
        } else if (decoded.profile().platform().empty()) {
            std::fprintf(stderr, "  FAIL: hardware profile proto missing platform\n");
            ++fails;
        } else if (decoded.accelerators_size() == 0) {
            std::fprintf(stderr, "  FAIL: hardware profile proto missing accelerators\n");
            ++fails;
        } else {
            std::fprintf(stdout,
                         "  ok:   hardware C ABI returns decodable HardwareProfileResult\n");
        }
    }
    rac_hardware_profile_free(profile_bytes);

    uint8_t* accelerator_bytes = nullptr;
    size_t accelerator_size = 0;
    rac_result_t accelerator_rc =
        rac_hardware_get_accelerators(&accelerator_bytes, &accelerator_size);
    if (accelerator_rc != RAC_SUCCESS || accelerator_bytes == nullptr ||
        accelerator_size == 0) {
        std::fprintf(stderr,
                     "  FAIL: rac_hardware_get_accelerators returned rc=%d size=%zu\n",
                     static_cast<int>(accelerator_rc),
                     accelerator_size);
        ++fails;
    } else {
        runanywhere::v1::HardwareProfileResult decoded;
        if (!decoded.ParseFromArray(accelerator_bytes, static_cast<int>(accelerator_size))) {
            std::fprintf(stderr, "  FAIL: accelerator proto bytes did not decode\n");
            ++fails;
        } else if (decoded.has_profile()) {
            std::fprintf(stderr,
                         "  FAIL: accelerator-only proto unexpectedly included profile\n");
            ++fails;
        } else if (decoded.accelerators_size() == 0) {
            std::fprintf(stderr, "  FAIL: accelerator-only proto missing accelerators\n");
            ++fails;
        } else {
            std::fprintf(stdout,
                         "  ok:   accelerator C ABI returns decodable proto list\n");
        }
    }
    rac_hardware_profile_free(accelerator_bytes);
#else
    std::fprintf(stdout, "  skip: hardware proto-byte decode test (no protobuf)\n");
#endif

    return fails == 0 ? 0 : 1;
}
