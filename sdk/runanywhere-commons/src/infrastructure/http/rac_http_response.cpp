/**
 * @file rac_http_response.cpp
 * @brief Shared implementation of `rac_http_response_free`.
 *
 * The same body was duplicated in
 * `rac_http_client_default.cpp` and `rac_http_client_emscripten.cpp`.
 * Since the function is platform-independent (relies only on std::free,
 * which both TUs already use for the allocations they hand back), it
 * lives in this dedicated TU that's compiled on every target.
 *
 * Both client TUs use std::malloc/std::free (or the matching strdup helper)
 * for the body bytes, header array, header name/value strdups, and the
 * redirected_url field — so the free path is identical regardless of which
 * client TU produced the response. The JNI OkHttp adapter and any other
 * platform transport must also free with std::free (see comment in
 * `okhttp_transport_adapter.cpp::copy_jbytes_to_malloc` and
 * `copy_jstring_headers`).
 */

#include <cstdlib>

#include "rac/infrastructure/http/rac_http_client.h"

extern "C" void rac_http_response_free(rac_http_response_t* resp) {
    if (!resp) {
        return;
    }
    if (resp->body_bytes) {
        std::free(resp->body_bytes);
        resp->body_bytes = nullptr;
    }
    resp->body_len = 0;
    if (resp->headers) {
        for (size_t i = 0; i < resp->header_count; ++i) {
            if (resp->headers[i].name) {
                std::free(const_cast<char*>(resp->headers[i].name));
            }
            if (resp->headers[i].value) {
                std::free(const_cast<char*>(resp->headers[i].value));
            }
        }
        std::free(resp->headers);
        resp->headers = nullptr;
    }
    resp->header_count = 0;
    if (resp->redirected_url) {
        std::free(resp->redirected_url);
        resp->redirected_url = nullptr;
    }
    resp->status = 0;
    resp->elapsed_ms = 0;
}
