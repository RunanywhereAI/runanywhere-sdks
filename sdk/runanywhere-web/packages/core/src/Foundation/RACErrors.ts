/**
 * RACErrors — canonical RACommons C ABI error codes.
 *
 * Mirrors the numeric values from `sdk/runanywhere-commons/include/rac/core/rac_error.h`.
 * Keep this file as the single source of truth for the Web SDK; backend
 * bridges and adapters MUST import from here (or from `@runanywhere/web/backend`)
 * instead of redeclaring the integer literals locally.
 *
 * The companion code in C lives at `c-api/include/rac_error.h` (proto-byte
 * adapters) and `include/rac/core/rac_error.h` (C++ core). Any divergence
 * between this file and those headers is a bug.
 */

/** Success — `rac_result_t` zero return. */
export const RAC_OK = 0 as const;

/** `RAC_ERROR_NOT_INITIALIZED` — an operation must be completed or retried later. */
export const RAC_ERROR_NOT_INITIALIZED = -100 as const;

/** `RAC_ERROR_INVALID_CONFIGURATION` — required runtime configuration is unusable. */
export const RAC_ERROR_INVALID_CONFIGURATION = -103 as const;

/** `RAC_ERROR_NETWORK_UNAVAILABLE` — host has no network connectivity. */
export const RAC_ERROR_NETWORK_UNAVAILABLE = -150 as const;

/** `RAC_ERROR_NETWORK_ERROR` — transport-level failure (DNS, TLS, timeout). */
export const RAC_ERROR_NETWORK_ERROR = -151 as const;

/** `RAC_ERROR_HTTP_ERROR` — the server returned a non-success HTTP status. */
export const RAC_ERROR_HTTP_ERROR = -157 as const;

/** `RAC_ERROR_FILE_NOT_FOUND` — requested browser filesystem path is missing. */
export const RAC_ERROR_FILE_NOT_FOUND = -183 as const;

/** `RAC_ERROR_DELETE_FAILED` — browser filesystem deletion could not be completed. */
export const RAC_ERROR_DELETE_FAILED = -187 as const;

/** `RAC_ERROR_MODEL_NOT_LOADED` — a required model unload could not be completed. */
export const RAC_ERROR_MODEL_NOT_LOADED = -116 as const;

/** `RAC_ERROR_OUT_OF_MEMORY` — heap allocation failed. */
export const RAC_ERROR_OUT_OF_MEMORY = -221 as const;

/** `RAC_ERROR_INVALID_ARGUMENT` — caller passed an unusable value. */
export const RAC_ERROR_INVALID_ARGUMENT = -259 as const;

/** `RAC_ERROR_NULL_POINTER` — required out-pointer was NULL. */
export const RAC_ERROR_NULL_POINTER = -260 as const;

/** `RAC_ERROR_CANCELLED` — operation aborted via a cancellation token. */
export const RAC_ERROR_CANCELLED = -380 as const;

/**
 * `RAC_ERROR_MODULE_ALREADY_REGISTERED` — `rac_backend_*_register()` was
 * called twice for the same backend on the same module. Treated as success
 * by every bridge so re-registration after a hot reload is idempotent.
 */
export const RAC_ERROR_MODULE_ALREADY_REGISTERED = -401 as const;

/** `RAC_ERROR_NOT_FOUND` — resource (model, file, key) is missing. */
export const RAC_ERROR_NOT_FOUND = -423 as const;

/**
 * `RAC_ERROR_FEATURE_NOT_AVAILABLE` — the requested code path is not
 * compiled into this WASM artifact (e.g. RAG with no native provider).
 */
export const RAC_ERROR_FEATURE_NOT_AVAILABLE = -801 as const;
