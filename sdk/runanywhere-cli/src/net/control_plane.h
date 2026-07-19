/**
 * @file control_plane.h
 * @brief Control-plane network wiring for rcli (auth, device, telemetry HTTP).
 *
 * rcli is the 6th consumer of runanywhere-commons and plays the same role the
 * Swift/Kotlin/Flutter/RN/Web bridges play for the control plane: it supplies
 * the platform-side callbacks (device info, persistent device id, HTTP POST)
 * and drives the canonical commons entry points
 * (rac_auth_* + rac_sdk_init_phase2_proto). All handshake sequencing, JSON
 * request building, and response parsing stay in commons.
 *
 * Requires bootstrap() (rac_init + curl transport + rac_state) to have run.
 */

#ifndef RCLI_NET_CONTROL_PLANE_H
#define RCLI_NET_CONTROL_PLANE_H

#include <cstdint>
#include <string>

#include "rac/core/rac_types.h"

namespace rcli::net {

/** "macos" / "linux" / "windows" — the X-Platform header + auth payload value. */
const char* platform_name();

/** Best-effort local hardware model (e.g. "Mac16,8"); empty when unknown. */
const std::string& device_model();

/** Best-effort OS version string (kernel release); empty when unknown. */
const std::string& os_version_string();

/**
 * Install the CLI's rac_device_callbacks_t: device info gathered from the
 * desktop platform adapter, the rac_state persistent device id, an in-process
 * registration flag, and an HTTP POST that routes through the registered curl
 * transport (Bearer token attached when the request requires auth).
 * Idempotent; called from bootstrap().
 */
void register_device_callbacks();

/** One buffered control-plane HTTP exchange. */
struct HttpResult {
    rac_result_t transport = RAC_SUCCESS;  ///< send-level result (network/TLS/timeout)
    int32_t status = 0;                    ///< HTTP status (0 when transport failed)
    std::string body;                      ///< response body (server error JSON on 4xx/5xx)

    [[nodiscard]] bool ok() const {
        return transport == RAC_SUCCESS && status >= 200 && status < 300;
    }
    /** "HTTP 401: {...}" / "network error" — for user-facing error lines. */
    [[nodiscard]] std::string describe() const;
};

/**
 * POST `endpoint` (path, e.g. "/api/v2/sdk/telemetry/llm") against the
 * configured base URL with the canonical control-plane headers
 * (commons defaults + X-Platform + apikey). When `bearer_auth` is true the
 * current JWT access token is attached as `Authorization: Bearer <token>`.
 */
HttpResult control_plane_post(const std::string& endpoint, const std::string& json_body,
                              bool bearer_auth);

/** Result of the real auth handshake (authenticate → device → assignments). */
struct LoginSummary {
    std::string organization_id;
    std::string user_id;             // may be empty (org-scoped keys)
    std::string backend_device_id;   // control-plane device row id (auth response)
    std::string persistent_device_id;  // SDK persistent UUID (device fingerprint)
    int64_t token_expires_at = 0;    // unix seconds
    bool device_registered = false;
    uint32_t assignment_count = 0;
    std::string warning;             // non-fatal phase-2 notes
};

/**
 * Run the real control-plane handshake against the configured backend:
 *   1. POST /api/v1/auth/sdk/authenticate (API key → JWT + refresh token),
 *   2. rac_sdk_init_phase2_proto (device registration + model-assignment
 *      fetch through the commons lifecycle orchestrator).
 *
 * Requires a staging/production environment (development mode has no control
 * plane). Idempotent within a process — a valid token short-circuits step 1.
 * On failure returns a non-SUCCESS code and fills `error` with the
 * server-surfaced message (HTTP status + response body).
 */
rac_result_t login(LoginSummary* out, std::string* error);

}  // namespace rcli::net

#endif  // RCLI_NET_CONTROL_PLANE_H
