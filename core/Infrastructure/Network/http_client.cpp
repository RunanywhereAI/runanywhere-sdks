// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "http_client.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include <curl/curl.h>

namespace ra::core::net {

namespace {

class CurlHttpClient final : public HttpClient {
public:
    CurlHttpClient() {
        std::call_once(init_flag_, [] { ::curl_global_init(CURL_GLOBAL_DEFAULT); });
    }

    HttpResponse send(const HttpRequest& req) override {
        HttpResponse rsp;
        const auto t0 = std::chrono::steady_clock::now();
        CURL* h = ::curl_easy_init();
        if (!h) {
            rsp.error_message = "curl_easy_init failed";
            return rsp;
        }

        ::curl_easy_setopt(h, CURLOPT_URL,             req.url.c_str());
        ::curl_easy_setopt(h, CURLOPT_FOLLOWLOCATION,  req.max_redirects > 0 ? 1L : 0L);
        ::curl_easy_setopt(h, CURLOPT_MAXREDIRS,       static_cast<long>(req.max_redirects));
        ::curl_easy_setopt(h, CURLOPT_TIMEOUT,         static_cast<long>(req.timeout_s));
        ::curl_easy_setopt(h, CURLOPT_CONNECTTIMEOUT,  static_cast<long>(req.connect_s));
        ::curl_easy_setopt(h, CURLOPT_NOPROGRESS,      1L);
        ::curl_easy_setopt(h, CURLOPT_USERAGENT,       "RunAnywhere/2.0");

        // Method.
        switch (req.method) {
            case HttpMethod::kGet:
                ::curl_easy_setopt(h, CURLOPT_HTTPGET, 1L);
                break;
            case HttpMethod::kPost:
                ::curl_easy_setopt(h, CURLOPT_POST, 1L);
                ::curl_easy_setopt(h, CURLOPT_POSTFIELDS, req.body.c_str());
                ::curl_easy_setopt(h, CURLOPT_POSTFIELDSIZE,
                                    static_cast<long>(req.body.size()));
                break;
            case HttpMethod::kPut:
                ::curl_easy_setopt(h, CURLOPT_CUSTOMREQUEST, "PUT");
                ::curl_easy_setopt(h, CURLOPT_POSTFIELDS, req.body.c_str());
                ::curl_easy_setopt(h, CURLOPT_POSTFIELDSIZE,
                                    static_cast<long>(req.body.size()));
                break;
            case HttpMethod::kDelete:
                ::curl_easy_setopt(h, CURLOPT_CUSTOMREQUEST, "DELETE");
                break;
            case HttpMethod::kPatch:
                ::curl_easy_setopt(h, CURLOPT_CUSTOMREQUEST, "PATCH");
                ::curl_easy_setopt(h, CURLOPT_POSTFIELDS, req.body.c_str());
                ::curl_easy_setopt(h, CURLOPT_POSTFIELDSIZE,
                                    static_cast<long>(req.body.size()));
                break;
        }

        // Headers.
        struct curl_slist* hlist = nullptr;
        for (const auto& [k, v] : req.headers) {
            const std::string line = k + ": " + v;
            hlist = ::curl_slist_append(hlist, line.c_str());
        }
        if (hlist) ::curl_easy_setopt(h, CURLOPT_HTTPHEADER, hlist);

        // Body accumulator.
        ::curl_easy_setopt(h, CURLOPT_WRITEFUNCTION, &CurlHttpClient::write_cb);
        ::curl_easy_setopt(h, CURLOPT_WRITEDATA,     &rsp.body);

        // Header accumulator.
        ::curl_easy_setopt(h, CURLOPT_HEADERFUNCTION, &CurlHttpClient::header_cb);
        ::curl_easy_setopt(h, CURLOPT_HEADERDATA,     &rsp.headers);

        const CURLcode rc = ::curl_easy_perform(h);
        long http_code = 0;
        ::curl_easy_getinfo(h, CURLINFO_RESPONSE_CODE, &http_code);
        rsp.status = static_cast<int>(http_code);

        if (rc != CURLE_OK) {
            rsp.error_message = ::curl_easy_strerror(rc);
        }
        rsp.elapsed_s = std::chrono::duration<double>(
            std::chrono::steady_clock::now() - t0).count();

        ::curl_easy_cleanup(h);
        if (hlist) ::curl_slist_free_all(hlist);
        return rsp;
    }

private:
    static std::size_t write_cb(char* data, std::size_t, std::size_t nmemb,
                                 void* userp) {
        auto* out = static_cast<std::string*>(userp);
        out->append(data, nmemb);
        return nmemb;
    }

    static std::size_t header_cb(char* data, std::size_t size, std::size_t nmemb,
                                  void* userp) {
        auto* m = static_cast<std::map<std::string, std::string>*>(userp);
        const std::size_t n = size * nmemb;
        const std::string line(data, n);
        const auto colon = line.find(':');
        if (colon != std::string::npos) {
            std::string k = line.substr(0, colon);
            std::string v = line.substr(colon + 1);
            auto trim = [](std::string& s) {
                while (!s.empty() && (s.back() == '\r' || s.back() == '\n' ||
                                       s.back() == ' ' || s.back() == '\t')) s.pop_back();
                std::size_t i = 0;
                while (i < s.size() && (s[i] == ' ' || s[i] == '\t')) ++i;
                if (i > 0) s.erase(0, i);
            };
            trim(k);
            trim(v);
            if (!k.empty()) (*m)[k] = v;
        }
        return n;
    }

    static inline std::once_flag init_flag_;
};

}  // namespace

std::unique_ptr<HttpClient> HttpClient::create() {
    return std::make_unique<CurlHttpClient>();
}

}  // namespace ra::core::net
