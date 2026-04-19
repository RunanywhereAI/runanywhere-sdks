// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Synchronous HTTP client — platform-agnostic wrapper around libcurl.
// Ports the capability surface from `sdk/runanywhere-commons/include/rac/
// infrastructure/network/rac_http_client.h`. Replaces the caller-provided
// HTTP callback model with a direct libcurl-backed implementation so
// every SDK shares the same transport.

#ifndef RA_CORE_NET_HTTP_CLIENT_H
#define RA_CORE_NET_HTTP_CLIENT_H

#include <map>
#include <memory>
#include <string>
#include <string_view>

#include "../abi/ra_primitives.h"

namespace ra::core::net {

enum class HttpMethod { kGet, kPost, kPut, kDelete, kPatch };

struct HttpRequest {
    HttpMethod                          method  = HttpMethod::kGet;
    std::string                         url;
    std::map<std::string, std::string>  headers;
    std::string                         body;          // empty for GET/DELETE
    int                                 timeout_s      = 30;
    int                                 connect_s      = 10;
    int                                 max_redirects  = 8;
};

struct HttpResponse {
    int                                 status     = 0;
    std::string                         body;
    std::map<std::string, std::string>  headers;
    std::string                         error_message;  // non-empty on transport error
    double                              elapsed_s  = 0.0;
};

class HttpClient {
public:
    virtual ~HttpClient() = default;

    // Synchronous request. Returns a populated HttpResponse. A non-zero
    // status always accompanies a non-empty body; transport-level failures
    // (dns, timeout, tls) set error_message and leave status=0.
    virtual HttpResponse send(const HttpRequest& req) = 0;

    // Factory — returns a libcurl-backed default implementation. Frontends
    // may subclass to route through platform-native stacks (NSURLSession,
    // OkHttp) if policy requires.
    static std::unique_ptr<HttpClient> create();
};

}  // namespace ra::core::net

#endif  // RA_CORE_NET_HTTP_CLIENT_H
