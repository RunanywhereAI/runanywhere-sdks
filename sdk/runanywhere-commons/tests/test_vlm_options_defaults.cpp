/**
 * @file test_vlm_options_defaults.cpp
 * @brief Regression coverage for shared VLM generation defaults.
 */

#include <cstdio>

#include "rac/features/vlm/rac_vlm_types.h"

namespace {

#define EXPECT_TRUE(_cond)                                                          \
    do {                                                                            \
        if (!(_cond)) {                                                             \
            std::fprintf(stderr, "FAIL @ %s:%d: %s\n", __FILE__, __LINE__, #_cond); \
            return 1;                                                               \
        }                                                                           \
    } while (0)

int test_default_sampling_guards_against_repetition() {
    rac_vlm_options_t options = RAC_VLM_OPTIONS_DEFAULT;

    EXPECT_TRUE(options.temperature > 0.0f);
    EXPECT_TRUE(options.top_p > 0.0f);
    EXPECT_TRUE(options.top_p <= 1.0f);
    EXPECT_TRUE(options.repetition_penalty > 1.0f);
    EXPECT_TRUE(options.min_p == 0.0f);
    return 0;
}

}  // namespace

int main() {
    if (test_default_sampling_guards_against_repetition() != 0) {
        return 1;
    }
    std::printf("vlm option default tests passed\n");
    return 0;
}
