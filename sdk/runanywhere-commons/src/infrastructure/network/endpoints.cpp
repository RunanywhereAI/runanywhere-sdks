/**
 * @file endpoints.cpp
 * @brief API endpoint implementation
 */

#include <cstdio>
#include <cstring>
#include <utility>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/network/rac_endpoints.h"

const char* rac_endpoint_device_registration(rac_environment_t env) {
    // Every environment registers against the FastAPI backend now; the
    // Supabase-direct dev path is retired. The parameter is retained for ABI
    // stability.
    (void)env;
    return RAC_ENDPOINT_DEVICE_REGISTER;
}

const char* rac_endpoint_model_assignments(void) {
    return "/api/v1/model-assignments/for-sdk";
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
        return (written < 0 || std::cmp_greater_equal(written, buffer_size)) ? -1 : written;
    }

    int written = snprintf(out_buffer, buffer_size, "%.*s%s", (int)base_len, base_url, ep);

    if (written < 0 || std::cmp_greater_equal(written, buffer_size)) {
        return -1;
    }

    return written;
}
