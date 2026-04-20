// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_platform_adapter.h"

#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

// Process-wide adapter. Stored as a shallow copy so ownership of the
// caller's struct ends at ra_set_platform_adapter return.
static ra_platform_adapter_t g_adapter;
static atomic_bool g_adapter_set = false;

ra_status_t ra_set_platform_adapter(const ra_platform_adapter_t* adapter) {
    if (!adapter) {
        memset(&g_adapter, 0, sizeof(g_adapter));
        atomic_store(&g_adapter_set, false);
        return RA_OK;
    }
    g_adapter = *adapter;
    atomic_store(&g_adapter_set, true);
    return RA_OK;
}

const ra_platform_adapter_t* ra_get_platform_adapter(void) {
    return atomic_load(&g_adapter_set) ? &g_adapter : NULL;
}

void ra_log(ra_log_level_t level, const char* category, const char* message) {
    const ra_platform_adapter_t* a = ra_get_platform_adapter();
    if (a && a->log) {
        a->log(level, category ? category : "", message ? message : "", a->user_data);
        return;
    }
    // Fallback: stderr. Matches legacy rac_log's stderr fallback path.
    static const char* level_names[] = {"TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL"};
    const char* ln = (level >= 0 && level <= 5) ? level_names[level] : "?";
    fprintf(stderr, "[%s][%s] %s\n", ln,
            category ? category : "ra",
            message ? message : "");
}

int64_t ra_get_current_time_ms(void) {
    const ra_platform_adapter_t* a = ra_get_platform_adapter();
    if (a && a->now_ms) {
        return a->now_ms(a->user_data);
    }
    // Fallback: clock_gettime for POSIX, GetTickCount64 for Win (TODO).
    struct timespec ts;
    if (clock_gettime(CLOCK_REALTIME, &ts) != 0) return 0;
    return ((int64_t)ts.tv_sec * 1000) + (ts.tv_nsec / 1000000);
}

ra_status_t ra_http_download(const char* url, const char* destination_path,
                              ra_http_progress_callback_fn progress_callback,
                              ra_http_complete_callback_fn complete_callback,
                              void* callback_user_data, char** out_task_id) {
    const ra_platform_adapter_t* a = ra_get_platform_adapter();
    if (!a || !a->http_download) return RA_ERR_CAPABILITY_UNSUPPORTED;
    return a->http_download(url, destination_path,
                             progress_callback, complete_callback,
                             callback_user_data, out_task_id,
                             a->user_data);
}

ra_status_t ra_http_download_cancel(const char* task_id) {
    const ra_platform_adapter_t* a = ra_get_platform_adapter();
    if (!a || !a->http_download_cancel) return RA_ERR_CAPABILITY_UNSUPPORTED;
    return a->http_download_cancel(task_id, a->user_data);
}

ra_status_t ra_extract_archive_via_adapter(const char* archive_path,
                                            const char* destination_dir,
                                            ra_extract_progress_callback_fn progress_callback,
                                            void* callback_user_data) {
    const ra_platform_adapter_t* a = ra_get_platform_adapter();
    if (!a || !a->extract_archive) return RA_ERR_CAPABILITY_UNSUPPORTED;
    return a->extract_archive(archive_path, destination_dir,
                               progress_callback, callback_user_data,
                               a->user_data);
}
