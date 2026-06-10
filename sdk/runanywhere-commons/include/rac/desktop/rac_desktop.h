/**
 * @file rac_desktop.h
 * @brief RunAnywhere Commons - Desktop (macOS/Linux) platform adapter + HTTP transport.
 *
 * Desktop equivalent of the per-SDK platform bridges (Swift URLSession adapter,
 * Kotlin OkHttp adapter, ...). Built only when RAC_DESKTOP_ADAPTER=ON; consumed
 * by desktop binaries that link rac_commons directly: the rcli CLI,
 * runanywhere-server, commons real-inference tests, and Playground apps.
 *
 * Provides:
 *   - rac_desktop_adapter_init():  fills a rac_platform_adapter_t with real
 *     POSIX implementations (file I/O, directory enumeration, 0600-file secure
 *     storage, stderr logging, monotonic-epoch clock, memory info). The
 *     http_download / extract_archive slots stay NULL on purpose — downloads
 *     route through the HTTP transport below and archive extraction uses the
 *     in-core libarchive path (rac_extract_archive_native).
 *   - rac_desktop_http_transport_register():  registers a libcurl-backed
 *     rac_http_transport_ops_t (request_send / request_stream / request_resume)
 *     so the download orchestrator, model assignment fetch, and telemetry all
 *     work without a mobile SDK bridge.
 *   - rac_desktop_default_base_dir():  canonical desktop storage root
 *     (${XDG_DATA_HOME:-~/.local/share}/runanywhere) shared by every desktop
 *     consumer so models land in one place.
 *
 * Typical bootstrap (mirrors tests/test_voice_agent.cpp but with real I/O):
 *
 *   rac_platform_adapter_t adapter;
 *   rac_desktop_adapter_init(NULL, &adapter);
 *   rac_config_t config = {0};
 *   config.platform_adapter = &adapter;
 *   config.log_level = RAC_LOG_INFO;
 *   rac_init(&config);
 *   rac_desktop_http_transport_register();
 *
 * Threading: all installed callbacks are thread-safe per the
 * rac_platform_adapter_t contract. The secure store serializes on an internal
 * mutex; the curl transport uses one easy handle per request.
 *
 * Security note: secure_get/set/delete persist to per-key files created with
 * mode 0600 under the config dir. This is deliberate, documented MVP behavior
 * for desktop (no Keychain/libsecret dependency) — do not store anything more
 * sensitive than API keys / device ids through it.
 */

#ifndef RAC_DESKTOP_RAC_DESKTOP_H
#define RAC_DESKTOP_RAC_DESKTOP_H

#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Configuration for the desktop adapter. All fields optional.
 */
typedef struct rac_desktop_adapter_config {
    /**
     * Directory for the secure-store files (created 0700 if missing).
     * NULL → ${XDG_CONFIG_HOME:-~/.config}/runanywhere
     */
    const char* secure_store_dir;
} rac_desktop_adapter_config_t;

/**
 * @brief Populate a platform adapter with the desktop POSIX implementation.
 *
 * The adapter struct itself is caller-owned (keep it alive until
 * rac_shutdown(), exactly like the SDK bridges do). Internal state (secure
 * store directory) is process-global; calling this twice with different
 * config replaces that state.
 *
 * @param config      Optional configuration (NULL for defaults).
 * @param out_adapter Receives the populated adapter. Must not be NULL.
 * @return RAC_SUCCESS, or RAC_ERROR_INVALID_ARGUMENT when out_adapter is NULL.
 */
RAC_API rac_result_t rac_desktop_adapter_init(const rac_desktop_adapter_config_t* config,
                                              rac_platform_adapter_t* out_adapter);

/**
 * @brief Register the libcurl HTTP transport as the process-wide transport.
 *
 * Implements request_send (buffered), request_stream (chunk callback;
 * returning RAC_FALSE cancels with RAC_ERROR_CANCELLED) and request_resume
 * (Range: bytes=N-). Call once after rac_init(); replaces any previously
 * registered transport per the rac_http_transport_register contract.
 *
 * @return RAC_SUCCESS, or the error surfaced by rac_http_transport_register
 *         (e.g. curl global init failure).
 */
RAC_API rac_result_t rac_desktop_http_transport_register(void);

/**
 * @brief Canonical desktop storage root shared by all desktop consumers.
 *
 * Resolves ${XDG_DATA_HOME:-$HOME/.local/share}/runanywhere (no trailing
 * slash). Pass this to rac_model_paths_set_base_dir() so model downloads land
 * in <root>/Models/{framework}/{modelId} — the same layout used by the Linux
 * test rig and Playground tooling. The directory is NOT created by this call.
 *
 * @param out_path    Buffer receiving the NUL-terminated path.
 * @param path_size   Buffer capacity in bytes.
 * @return RAC_SUCCESS, RAC_ERROR_INVALID_ARGUMENT on NULL/zero buffer,
 *         RAC_ERROR_BUFFER_TOO_SMALL when the path does not fit, or
 *         RAC_ERROR_NOT_INITIALIZED when $HOME cannot be resolved.
 */
RAC_API rac_result_t rac_desktop_default_base_dir(char* out_path, size_t path_size);

#ifdef __cplusplus
}
#endif

#endif /* RAC_DESKTOP_RAC_DESKTOP_H */
