/**
 * @file rac_http_internal.cpp
 * @brief Implementation of the internal C++ HTTP facade
 *        (v2 close-out Phase H, Stage 2).
 *
 * Thin C++-friendly wrappers around the existing C ABI. Both entry
 * points inherit platform-transport routing for free because their
 * underlying C functions (`rac_http_request_send`,
 * `rac_http_request_stream`, `rac_http_request_resume`) already
 * consult the `rac_http_transport_ops_t` registry before dispatching
 * to libcurl.
 *
 * The facade is deliberately thin — Stage 2 is about funnelling every
 * internal caller through a single entry point so Stage 5 can delete
 * libcurl with one atomic change. No new logic lives here.
 */

#include "rac_http_internal.h"

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_download.h"
#include "rac/infrastructure/http/rac_http_transport.h"

namespace {
constexpr const char* kTag = "rac_http_facade";
}  // namespace

namespace rac {
namespace http {

rac_result_t execute(const rac_http_request_t& req, rac_http_response_t& out_resp) {
    // The curl-backed send path in rac_http_client_curl.cpp already
    // calls rac_internal::get_http_transport() and routes through the
    // adapter's request_send op when one is installed — the facade
    // doesn't need to duplicate that branch.
    rac_http_client_t* client = nullptr;
    rac_result_t rc = rac_http_client_create(&client);
    if (rc != RAC_SUCCESS || client == nullptr) {
        RAC_LOG_ERROR(kTag, "rac_http_client_create failed: rc=%d", static_cast<int>(rc));
        return rc != RAC_SUCCESS ? rc : RAC_ERROR_INTERNAL;
    }

    rc = rac_http_request_send(client, &req, &out_resp);
    rac_http_client_destroy(client);
    return rc;
}

rac_http_download_status_t execute_stream(const rac_http_download_request_t& req,
                                          rac_http_download_progress_fn progress_cb,
                                          void* progress_user_data, int32_t* out_http_status) {
    // rac_http_download_execute drives rac_http_request_stream /
    // rac_http_request_resume under the hood, both of which observe
    // the transport registry. Nothing extra needed here.
    return rac_http_download_execute(&req, progress_cb, progress_user_data, out_http_status);
}

}  // namespace http
}  // namespace rac
