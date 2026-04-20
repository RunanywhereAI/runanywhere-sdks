// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_core_init.h"

#include <stdatomic.h>
#include <stdio.h>
#include <string.h>

static atomic_bool g_initialized         = false;
static atomic_int  g_min_log_level       = RA_LOG_LEVEL_INFO;
static atomic_bool g_stderr_fallback     = true;

// ----------------------------------------------------------------------------
// Init / shutdown
// ----------------------------------------------------------------------------

ra_status_t ra_init(const ra_init_config_t* config) {
    if (config && !ra_validate_config(config)) {
        return RA_ERR_INVALID_ARGUMENT;
    }
    if (config) {
        atomic_store(&g_min_log_level, config->log_level);
    }
    atomic_store(&g_initialized, true);
    return RA_OK;
}

void ra_shutdown(void) {
    atomic_store(&g_initialized, false);
}

bool ra_is_initialized(void) {
    return atomic_load(&g_initialized);
}

// ----------------------------------------------------------------------------
// Logger — wrappers over the platform adapter's log callback.
// ----------------------------------------------------------------------------

void ra_logger_set_min_level(ra_log_level_t level) {
    atomic_store(&g_min_log_level, level);
}

ra_log_level_t ra_logger_get_min_level(void) {
    return (ra_log_level_t)atomic_load(&g_min_log_level);
}

void ra_logger_set_stderr_fallback(bool enabled) {
    atomic_store(&g_stderr_fallback, enabled);
}

void ra_logger_log(ra_log_level_t level, const char* category,
                    const char* message) {
    if (level < atomic_load(&g_min_log_level)) return;
    const ra_platform_adapter_t* a = ra_get_platform_adapter();
    if (a && a->log) {
        a->log(level, category ? category : "", message ? message : "",
               a->user_data);
        return;
    }
    if (!atomic_load(&g_stderr_fallback)) return;
    static const char* level_names[] = {
        "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL"
    };
    const char* ln = (level >= 0 && level <= 5) ? level_names[level] : "?";
    fprintf(stderr, "[%s][%s] %s\n", ln,
            category ? category : "ra",
            message ? message : "");
}

// ----------------------------------------------------------------------------
// Validators — stricter than the legacy versions, which were mostly
// "non-empty string" checks. Matches what the Swift bridging layer
// expects to see.
// ----------------------------------------------------------------------------

bool ra_validate_api_key(const char* key) {
    if (!key) return false;
    // Minimum reasonable key length (legacy accepted >= 16).
    return strlen(key) >= 16;
}

bool ra_validate_base_url(const char* url) {
    if (!url) return false;
    return strncmp(url, "http://", 7) == 0 || strncmp(url, "https://", 8) == 0;
}

bool ra_validate_config(const ra_init_config_t* config) {
    if (!config) return true;  // all defaults
    if (config->api_key && !ra_validate_api_key(config->api_key)) return false;
    if (config->base_url && !ra_validate_base_url(config->base_url)) return false;
    return true;
}
