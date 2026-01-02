/**
 * @file endpoints.cpp
 * @brief API endpoint implementation
 */

#include <cstdio>
#include <cstring>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/network/rac_endpoints.h"

const char* rac_endpoint_device_registration(rac_environment_t env) {
    switch (env) {
        case RAC_ENV_DEVELOPMENT:
            return RAC_ENDPOINT_DEV_DEVICE_REGISTER;
        case RAC_ENV_STAGING:
        case RAC_ENV_PRODUCTION:
        default:
            return RAC_ENDPOINT_DEVICE_REGISTER;
    }
}

const char* rac_endpoint_telemetry(rac_environment_t env) {
    switch (env) {
        case RAC_ENV_DEVELOPMENT:
            return RAC_ENDPOINT_DEV_TELEMETRY;
        case RAC_ENV_STAGING:
        case RAC_ENV_PRODUCTION:
        default:
            return RAC_ENDPOINT_TELEMETRY;
    }
}

int rac_endpoint_model_assignments(const char* device_type, const char* platform, char* out_buffer,
                                   size_t buffer_size) {
    if (!device_type || !platform || !out_buffer || buffer_size == 0) {
        return -1;
    }

    int written = snprintf(out_buffer, buffer_size,
                           "/api/v1/model-assignments/for-sdk?device_type=%s&platform=%s",
                           device_type, platform);

    if (written < 0 || (size_t)written >= buffer_size) {
        return -1;
    }

    return written;
}

int rac_endpoint_model_download(const char* model_id, char* out_buffer, size_t buffer_size) {
    if (!model_id || !out_buffer || buffer_size == 0) {
        return -1;
    }

    int written = snprintf(out_buffer, buffer_size, "/api/v1/models/%s/download", model_id);

    if (written < 0 || (size_t)written >= buffer_size) {
        return -1;
    }

    return written;
}

int rac_build_url(const char* base_url, const char* endpoint, char* out_buffer,
                  size_t buffer_size) {
    if (!base_url || !endpoint || !out_buffer || buffer_size == 0) {
        return -1;
    }

    // Remove trailing slash from base_url if present
    size_t base_len = strlen(base_url);
    while (base_len > 0 && base_url[base_len - 1] == '/') {
        base_len--;
    }

    // Ensure endpoint starts with /
    const char* ep = endpoint;
    if (*ep != '/') {
        // Shouldn't happen with our constants, but handle it
        int written = snprintf(out_buffer, buffer_size, "%.*s/%s", (int)base_len, base_url, ep);
        return (written < 0 || (size_t)written >= buffer_size) ? -1 : written;
    }

    int written = snprintf(out_buffer, buffer_size, "%.*s%s", (int)base_len, base_url, ep);

    if (written < 0 || (size_t)written >= buffer_size) {
        return -1;
    }

    return written;
}
