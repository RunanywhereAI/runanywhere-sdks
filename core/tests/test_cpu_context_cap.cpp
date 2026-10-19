/**
 * @file test_cpu_context_cap.cpp
 * @brief Tier tests for the CPU-only llamacpp context ceiling.
 *
 * The backend re-caps common_fit_params' VRAM-based n_ctx against host RAM
 * on CPU-only builds; a fit that already clears the bar must pass through
 * untouched, and unknown RAM keeps today's conservative 4096.
 */

#include "test_common.h"

#include "cpu_context_cap.h"

namespace {

const uint64_t kGiB = 1024ULL * 1024ULL * 1024ULL;

TestResult run_tier_cases() {
    struct Case {
        uint64_t ram;
        uint32_t want;
        const char* note;
    };
    constexpr Case cases[] = {
        {0, 4096, "unknown RAM stays conservative"},
        {4 * kGiB, 4096, "small machine unchanged"},
        {12 * kGiB, 16384, "harness minimum reachable"},
        {24 * kGiB, 32768, "large fit passes through"},
        {48 * kGiB, 65536, "top tier"},
        {128 * kGiB, 65536, "caps at top tier"},
    };
    for (const Case& c : cases) {
        const uint32_t got = runanywhere::cpu_ram_context_cap(c.ram);
        ASSERT_EQ(got, c.want, std::string("ram tier: ") + c.note);
    }
    return TEST_PASS();
}

}  // namespace

int main(int argc, char** argv) {
    TestSuite suite("cpu_context_cap");
    suite.add("tier_cases", run_tier_cases);
    return suite.run(argc, argv);
}
