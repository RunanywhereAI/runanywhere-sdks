#include <cstdlib>
#include <cstdio>
#include <cstring>

#include "diffusion_coreml_backend.h"

int main() {
#if !defined(__APPLE__)
    std::fprintf(stdout, "SKIP: CoreML diffusion generate test is Apple-only\n");
    return 0;
#else
    const char* bundle = std::getenv("RAC_TEST_COREML_DIFFUSION_BUNDLE");
    if (!bundle || bundle[0] == '\0') {
        std::fprintf(stdout,
                     "SKIP: set RAC_TEST_COREML_DIFFUSION_BUNDLE to a CoreML Stable Diffusion bundle\n");
        return 0;
    }

    rac_diffusion_coreml_impl_t* impl = nullptr;
    rac_result_t rc = rac_diffusion_coreml_create("test-coreml-diffusion", nullptr, &impl);
    if (rc != RAC_SUCCESS || !impl) {
        std::fprintf(stderr, "create failed: %d\n", static_cast<int>(rc));
        return 1;
    }

    rac_diffusion_config_t config = RAC_DIFFUSION_CONFIG_DEFAULT;
    config.enable_safety_checker = RAC_FALSE;
    rc = rac_diffusion_coreml_initialize(impl, bundle, &config);
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "initialize failed for %s: %d\n", bundle, static_cast<int>(rc));
        rac_diffusion_coreml_destroy(impl);
        return 1;
    }

    rac_diffusion_options_t options = RAC_DIFFUSION_OPTIONS_DEFAULT;
    options.prompt = "a small red cube on a white table";
    options.negative_prompt = "";
    options.width = 512;
    options.height = 512;
    options.steps = 1;
    options.guidance_scale = 7.5f;
    options.seed = 1234;
    options.scheduler = RAC_DIFFUSION_SCHEDULER_DDIM;
    options.mode = RAC_DIFFUSION_MODE_TEXT_TO_IMAGE;

    rac_diffusion_result_t result{};
    rc = rac_diffusion_coreml_generate(impl, &options, &result);
    if (rc == RAC_ERROR_NOT_SUPPORTED) {
        std::fprintf(stderr,
                     "generate returned NOT_SUPPORTED for configured CoreML diffusion bundle: %s\n",
                     result.error_message ? result.error_message : "(no message)");
        rac_diffusion_result_free(&result);
        rac_diffusion_coreml_destroy(impl);
        return 1;
    }
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "generate failed: %d %s\n", static_cast<int>(rc),
                     result.error_message ? result.error_message : "");
        rac_diffusion_result_free(&result);
        rac_diffusion_coreml_destroy(impl);
        return 1;
    }
    if (!result.image_data || result.image_size == 0 || result.width <= 0 || result.height <= 0) {
        std::fprintf(stderr, "generate returned an empty image result\n");
        rac_diffusion_result_free(&result);
        rac_diffusion_coreml_destroy(impl);
        return 1;
    }

    std::fprintf(stdout, "ok: generated %dx%d RGBA image (%zu bytes), seed=%lld\n",
                 result.width, result.height, result.image_size,
                 static_cast<long long>(result.seed_used));
    rac_diffusion_result_free(&result);
    rac_diffusion_coreml_destroy(impl);
    return 0;
#endif
}
