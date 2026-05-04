/**
 * @file rac_platform_services.cpp
 * @brief Platform service availability callback registry.
 */

#include "rac/features/platform/rac_platform_services.h"

#include <mutex>

#include "rac/core/rac_error.h"

namespace {

std::mutex g_platform_services_mutex;
rac_platform_service_availability_callback_t g_availability_callback = nullptr;

}  // namespace

extern "C" {

rac_result_t rac_platform_services_register_availability_callback(
    rac_platform_service_availability_callback_t callback) {
    if (callback == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(g_platform_services_mutex);
    g_availability_callback = callback;
    return RAC_SUCCESS;
}

rac_bool_t rac_platform_services_is_available(rac_platform_service_t service) {
    rac_platform_service_availability_callback_t callback = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_platform_services_mutex);
        callback = g_availability_callback;
    }

    if (callback == nullptr) {
        return RAC_FALSE;
    }

    return callback(static_cast<int32_t>(service), nullptr) == RAC_TRUE ? RAC_TRUE : RAC_FALSE;
}

}  // extern "C"
