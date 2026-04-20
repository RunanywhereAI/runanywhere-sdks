// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — top-level init / shutdown / logger C ABI. Ports the
// capability surface from `sdk/legacy/commons/include/rac/core/rac_core.h`
// + `rac_logger.h`.
//
// The new core doesn't really "need" init because registries are global
// singletons with lazy construction. But legacy frontend code calls
// `rac_init()` + `rac_shutdown()` as part of its normal lifecycle, so
// we expose stubs that thread-safely track init state, clamp logger
// level, and provide `ra_is_initialized()` for observability.

#ifndef RA_CORE_INIT_H
#define RA_CORE_INIT_H

#include <stdbool.h>
#include <stdint.h>

#include "ra_platform_adapter.h"
#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

// --- Init / shutdown --------------------------------------------------------
//
// Idempotent. After ra_init returns RA_OK, subsequent calls are no-ops
// until ra_shutdown is invoked. ra_is_initialized reflects the current
// state. Thread-safe.
typedef struct {
    const char*         api_key;        // may be NULL in dev builds
    const char*         base_url;       // may be NULL — defaults to prod
    ra_log_level_t      log_level;      // min level accepted by ra_log
} ra_init_config_t;

ra_status_t ra_init(const ra_init_config_t* config);
void        ra_shutdown(void);
bool        ra_is_initialized(void);

// --- Logger -----------------------------------------------------------------
//
// Thin wrappers over the platform adapter's log callback. If no adapter
// is registered, messages go to stderr when log_level >= min_level.
// ra_logger_log is identical to ra_log but respects the logger's min
// level even when the platform adapter's log callback is registered.

void           ra_logger_set_min_level(ra_log_level_t level);
ra_log_level_t ra_logger_get_min_level(void);
void           ra_logger_set_stderr_fallback(bool enabled);
void           ra_logger_log(ra_log_level_t level, const char* category,
                              const char* message);

// --- Validators -------------------------------------------------------------
//
// Input validation helpers. Legacy Swift/Kotlin bridges call these
// before firing HTTP requests; porting them lets the bridge stay
// unchanged.
bool  ra_validate_api_key(const char* key);
bool  ra_validate_base_url(const char* url);
bool  ra_validate_config(const ra_init_config_t* config);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_CORE_INIT_H
