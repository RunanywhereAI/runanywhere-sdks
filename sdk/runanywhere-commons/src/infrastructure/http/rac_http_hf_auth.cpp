/**
 * @file rac_http_hf_auth.cpp
 * @brief Process-wide Hugging Face token + bearer-header composition
 *        (see rac_http_hf_auth.h).
 */

#include "rac_http_hf_auth.h"

#include <cctype>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <mutex>

#include "rac/infrastructure/http/rac_http_client.h"

namespace {

std::mutex g_token_mutex;
std::string g_token;       // explicit token from rac_http_hf_token_set
bool g_token_set = false;  // true once set() was called (even with empty/clear)

// Read a token file written by `hf auth login`. Returns "" when absent.
std::string read_token_file(const std::string& path) {
    if (path.empty()) {
        return {};
    }
    std::ifstream f(path, std::ios::binary);
    if (!f) {
        return {};
    }
    std::string value((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    return value;
}

// HF_TOKEN environment fallback, captured once on first use so a plain env
// var works with no call-site change (mirrors the retired OkHttp behavior).
//
// ALSO reads the token FILE that `hf auth login` writes, because that is how essentially every
// developer on a workstation is authenticated — the env var is the CI shape, not the desktop one.
// Without this, `rcli pull` on a private repo failed with "gated-repo tokens are not wired up yet"
// on a machine where `hf auth whoami` worked fine. Resolution order matches huggingface_hub:
// HF_TOKEN, then $HF_TOKEN_PATH, then $HF_HOME/token, then ~/.cache/huggingface/token.
std::string env_token() {
    static const std::string captured = [] {
        const char* raw = std::getenv("HF_TOKEN");
        std::string value = raw ? raw : "";
        if (value.empty()) {
            const char* tok_path = std::getenv("HF_TOKEN_PATH");
            if (tok_path && *tok_path) {
                value = read_token_file(tok_path);
            }
        }
        if (value.empty()) {
            const char* hf_home = std::getenv("HF_HOME");
            if (hf_home && *hf_home) {
                value = read_token_file(std::string(hf_home) + "/token");
            }
        }
        if (value.empty()) {
            const char* home = std::getenv("HOME");
            if (home && *home) {
                value = read_token_file(std::string(home) + "/.cache/huggingface/token");
            }
        }
        // trim whitespace
        const auto is_space = [](unsigned char c) { return std::isspace(c) != 0; };
        while (!value.empty() && is_space(value.front())) {
            value.erase(value.begin());
        }
        while (!value.empty() && is_space(value.back())) {
            value.pop_back();
        }
        return value;
    }();
    return captured;
}

std::string current_token() {
    std::lock_guard<std::mutex> lock(g_token_mutex);
    if (g_token_set) {
        return g_token;
    }
    return env_token();
}

bool iequals(const std::string& a, const char* b) {
    size_t i = 0;
    for (; i < a.size(); ++i) {
        if (b[i] == '\0' || std::tolower(static_cast<unsigned char>(a[i])) !=
                                std::tolower(static_cast<unsigned char>(b[i]))) {
            return false;
        }
    }
    return b[i] == '\0';
}

}  // namespace

namespace rac::http {

bool is_hf_host(const char* url) {
    if (url == nullptr) {
        return false;
    }
    std::string s(url);
    const size_t scheme = s.find("://");
    if (scheme == std::string::npos) {
        return false;
    }
    // Scheme must be https — never send the token in cleartext.
    if (!iequals(s.substr(0, scheme), "https")) {
        return false;
    }
    size_t host_start = scheme + 3;
    size_t host_end = s.find_first_of("/?#", host_start);
    if (host_end == std::string::npos) {
        host_end = s.size();
    }
    std::string host = s.substr(host_start, host_end - host_start);
    // Strip an explicit port; reject userinfo outright.
    if (host.find('@') != std::string::npos) {
        return false;
    }
    const size_t colon = host.find(':');
    if (colon != std::string::npos) {
        host = host.substr(0, colon);
    }
    // Exact hosts only — subdomains (CDN/LFS mirrors) never get the token.
    return iequals(host, "huggingface.co") || iequals(host, "hf.co");
}

std::string hf_bearer_for_url(const char* url, bool has_auth_header) {
    if (has_auth_header || !is_hf_host(url)) {
        return {};
    }
    const std::string token = current_token();
    if (token.empty()) {
        return {};
    }
    return "Bearer " + token;
}

}  // namespace rac::http

extern "C" void rac_http_hf_token_set(const char* token) {
    std::string value = token ? token : "";
    const auto is_space = [](unsigned char c) { return std::isspace(c) != 0; };
    while (!value.empty() && is_space(value.front())) {
        value.erase(value.begin());
    }
    while (!value.empty() && is_space(value.back())) {
        value.pop_back();
    }
    std::lock_guard<std::mutex> lock(g_token_mutex);
    // An explicit empty set() clears the token AND disables the env fallback
    // until the next non-empty set(), restoring public no-auth behavior.
    g_token = value;
    g_token_set = true;
    if (value.empty() && token == nullptr) {
        // set(NULL) fully resets to the default (env-fallback) state.
        g_token_set = false;
    }
}

extern "C" rac_bool_t rac_http_hf_token_is_configured(void) {
    return current_token().empty() ? RAC_FALSE : RAC_TRUE;
}
