/**
 * @file test_hf_auth.cpp
 * @brief Tests for the commons-side Hugging Face bearer auth
 *        (rac_http_hf_token_set + the dispatch-layer header composition).
 *
 * Ports the semantics of the retired Kotlin OkHttpHttpTransport HF tests:
 * exact-host matching, subdomain rejection, caller-Authorization precedence,
 * and set/clear behavior — now covered once in C++ for every platform.
 */

#include "test_common.h"

#include <string>
#include <vector>

#include "../src/infrastructure/http/rac_http_hf_auth.h"
#include "rac/infrastructure/http/rac_http_client.h"

namespace {

TestResult expect(const std::string& name, bool condition, const std::string& details = "") {
    TestResult r;
    r.test_name = name;
    r.passed = condition;
    r.details = details;
    return r;
}

void test_host_matching(std::vector<TestResult>& results) {
    results.push_back(expect("huggingface.co matches",
                             rac::http::is_hf_host("https://huggingface.co/org/repo")));
    results.push_back(
        expect("hf.co matches", rac::http::is_hf_host("https://hf.co/org/repo?x=1")));
    results.push_back(expect("case-insensitive host",
                             rac::http::is_hf_host("https://HuggingFace.co/org/repo")));
    results.push_back(expect("subdomain rejected",
                             !rac::http::is_hf_host("https://cdn.huggingface.co/f.bin")));
    results.push_back(expect("lookalike rejected",
                             !rac::http::is_hf_host("https://nothuggingface.co/f.bin")));
    results.push_back(expect("suffix-lookalike rejected",
                             !rac::http::is_hf_host("https://huggingface.co.evil.com/f")));
    results.push_back(
        expect("plain http rejected", !rac::http::is_hf_host("http://huggingface.co/f")));
    results.push_back(expect("userinfo rejected",
                             !rac::http::is_hf_host("https://a@huggingface.co/f")));
    results.push_back(expect("NULL rejected", !rac::http::is_hf_host(nullptr)));
}

void test_bearer_composition(std::vector<TestResult>& results) {
    // Explicit token set.
    rac_http_hf_token_set("  hf_test_token  ");
    results.push_back(expect(
        "bearer attached on HF host",
        rac::http::hf_bearer_for_url("https://huggingface.co/org/repo/resolve/main/f.bin",
                                     false) == "Bearer hf_test_token"));
    results.push_back(expect("bearer trimmed", rac::http::hf_bearer_for_url(
                                                    "https://hf.co/api/models/org/repo/tree/main",
                                                    false) == "Bearer hf_test_token"));
    results.push_back(expect("no bearer on other hosts",
                             rac::http::hf_bearer_for_url("https://example.com/f.bin", false)
                                 .empty()));
    results.push_back(expect("caller Authorization wins",
                             rac::http::hf_bearer_for_url("https://huggingface.co/f", true)
                                 .empty()));

    // Explicit empty set() clears (and disables the env fallback).
    rac_http_hf_token_set("");
    results.push_back(expect("cleared token adds nothing",
                             rac::http::hf_bearer_for_url("https://huggingface.co/f", false)
                                 .empty()));
    // Restore the default state for other tests in this process.
    rac_http_hf_token_set(nullptr);
}

}  // namespace

int main() {
    std::vector<TestResult> results;
    test_host_matching(results);
    test_bearer_composition(results);
    for (const TestResult& r : results) {
        print_result(r);
    }
    return print_summary(results);
}
