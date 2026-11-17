/**
 * @file test_backend_registration_results.cpp
 * @brief Exercise the real QHexRT/MLX wrappers with controlled registration results.
 * No private runtime or device is needed; only their external dependencies are faked.
 */

#include <cstdio>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_bundle_policy.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_registration.h"
#include "rac/qhexrt/rac_qhexrt.h"

extern "C" {
rac_result_t rac_backend_qhexrt_register(void);
rac_result_t rac_backend_qhexrt_unregister(void);
rac_bool_t rac_backend_qhexrt_is_registered(void);
rac_result_t rac_backend_mlx_register(void);
rac_result_t rac_backend_mlx_unregister(void);
}

namespace {
rac_result_t next_result = RAC_SUCCESS;
rac_result_t next_unregister_result = RAC_SUCCESS;
int registration_calls = 0;
int mlx_policy_calls = 0;
bool supported_device = true;
const rac_engine_vtable_t fixture{};

bool check(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "%s (result=%d)\n", message, next_result);
    }
    return condition;
}
}  // namespace

extern "C" {
const rac_engine_vtable_t* rac_plugin_entry_qhexrt(void) {
    return &fixture;
}
const rac_engine_vtable_t* rac_plugin_entry_mlx(void) {
    return &fixture;
}
rac_result_t rac_plugin_register(const rac_engine_vtable_t*) noexcept {
    ++registration_calls;
    return next_result;
}
rac_result_t rac_plugin_unregister(const char*) noexcept {
    return next_unregister_result;
}
rac_result_t rac_bundle_policy_register(const rac_bundle_policy_t* policy) {
    if (policy->framework == RAC_FRAMEWORK_MLX) {
        ++mlx_policy_calls;
    }
    return RAC_SUCCESS;
}
rac_result_t rac_bundle_policy_unregister(rac_inference_framework_t) {
    return RAC_SUCCESS;
}
rac_result_t rac_qhexrt_probe(rac_qhexrt_device_info_t* out) {
    *out = {};
    out->supported = supported_device ? RAC_TRUE : RAC_FALSE;
    out->hexagon_arch = RAC_QHEXRT_HEXAGON_ARCH_V79;
    return RAC_SUCCESS;
}
const char* rac_qhexrt_arch_name(rac_qhexrt_hexagon_arch_t) {
    return "v79";
}
rac_log_level_t rac_logger_get_min_level(void) {
    return RAC_LOG_FATAL;
}
void rac_logger_logf(rac_log_level_t, const char*, const rac_log_metadata_t*, const char*, ...) {}
}

int main() {
    const rac_result_t available[] = {RAC_SUCCESS, RAC_ERROR_PLUGIN_DUPLICATE,
                                      RAC_ERROR_PLUGIN_BUSY, RAC_ERROR_MODULE_ALREADY_REGISTERED};
    const rac_result_t unavailable[] = {
        RAC_ERROR_PLUGIN_LOAD_FAILED,   RAC_ERROR_CAPABILITY_UNSUPPORTED,
        RAC_ERROR_ABI_VERSION_MISMATCH, RAC_ERROR_BACKEND_UNAVAILABLE,
        RAC_ERROR_OUT_OF_MEMORY,        RAC_ERROR_NULL_POINTER};
    for (auto rc : available) {
        next_result = rc;
        registration_calls = 0;
        mlx_policy_calls = 0;
        if (!check(rac_plugin_registration_succeeded(rc) == RAC_TRUE,
                   "available result rejected") ||
            !check(rac_backend_qhexrt_register() == RAC_SUCCESS, "QHexRT registration failed") ||
            !check(rac_backend_qhexrt_is_registered() == RAC_TRUE, "QHexRT flag not set") ||
            !check(rac_backend_qhexrt_register() == RAC_SUCCESS, "QHexRT retry failed") ||
            !check(registration_calls == 1, "QHexRT retry repeated plugin registration") ||
            !check(rac_backend_mlx_register() == RAC_SUCCESS, "MLX registration failed") ||
            !check(rac_backend_mlx_register() == RAC_SUCCESS, "MLX retry failed") ||
            !check(registration_calls == 2 && mlx_policy_calls == 1,
                   "MLX did not commit registered state and policy exactly once")) {
            return 1;
        }
        rac_backend_qhexrt_unregister();
        rac_backend_mlx_unregister();
    }
    for (auto rc : unavailable) {
        next_result = rc;
        registration_calls = 0;
        mlx_policy_calls = 0;
        if (!check(rac_plugin_registration_succeeded(rc) == RAC_FALSE, "failure accepted") ||
            !check(rac_backend_qhexrt_register() == rc, "QHexRT failure swallowed") ||
            !check(rac_backend_qhexrt_is_registered() == RAC_FALSE, "QHexRT failure set flag") ||
            !check(rac_backend_qhexrt_register() == rc, "QHexRT failure cached as registered") ||
            !check(rac_backend_mlx_register() == rc, "MLX failure swallowed") ||
            !check(rac_backend_mlx_register() == rc, "MLX failure cached as registered") ||
            !check(registration_calls == 4 && mlx_policy_calls == 0,
                   "failed registration committed state or policy")) {
            return 1;
        }
        rac_backend_qhexrt_unregister();
        rac_backend_mlx_unregister();
    }
    supported_device = false;
    next_result = RAC_SUCCESS;
    registration_calls = 0;
    if (!check(rac_backend_qhexrt_register() == RAC_ERROR_BACKEND_UNAVAILABLE,
               "QHexRT device gate bypassed") ||
        !check(registration_calls == 0, "unsupported device attempted registration")) {
        return 1;
    }
    rac_backend_qhexrt_unregister();
    // Busy unregistration must keep state intact and propagate the error.
    next_result = RAC_SUCCESS;
    next_unregister_result = RAC_ERROR_PLUGIN_BUSY;
    supported_device = true;
    registration_calls = 0;
    if (!check(rac_backend_qhexrt_register() == RAC_SUCCESS,
               "QHexRT busy-test registration failed") ||
        !check(rac_backend_qhexrt_unregister() == RAC_ERROR_PLUGIN_BUSY,
               "QHexRT busy unregister not propagated") ||
        !check(rac_backend_qhexrt_is_registered() == RAC_TRUE, "QHexRT busy dropped flag") ||
        !check(rac_backend_mlx_register() == RAC_SUCCESS, "MLX busy-test registration failed") ||
        !check(rac_backend_mlx_unregister() == RAC_ERROR_PLUGIN_BUSY,
               "MLX busy unregister not propagated")) {
        return 1;
    }
    // Retry after the lease is released unregisters cleanly.
    next_unregister_result = RAC_SUCCESS;
    if (!check(rac_backend_qhexrt_unregister() == RAC_SUCCESS, "QHexRT retry unregister failed") ||
        !check(rac_backend_qhexrt_is_registered() == RAC_FALSE,
               "QHexRT retry did not clear flag") ||
        !check(rac_backend_mlx_unregister() == RAC_SUCCESS, "MLX retry unregister failed")) {
        return 1;
    }
    std::puts("ok: registration policy, flags, retries and genuine failures");
    return 0;
}
