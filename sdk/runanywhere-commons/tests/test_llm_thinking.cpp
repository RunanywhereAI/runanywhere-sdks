/**
 * @file test_llm_thinking.cpp
 * @brief Behavioral parity test for rac_llm_thinking C ABI vs Swift
 *        ThinkingContentParser (the type it replaces).
 *
 * v2 close-out Phase 5. Each test mirrors a unit-test scenario from the
 * Swift implementation to lock in byte-equivalent behavior across SDKs.
 */

#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_thinking.h"

namespace {

#define ASSERT_EQ_STR(actual, expected) do { \
    if (std::strcmp((actual), (expected)) != 0) { \
        std::fprintf(stderr, "ASSERT FAIL @ %s:%d\n  expected: \"%s\"\n  actual:   \"%s\"\n", \
                     __FILE__, __LINE__, (expected), (actual)); \
        return 1; \
    } \
} while (0)

#define ASSERT_EQ_INT(a, b) do { \
    if ((a) != (b)) { \
        std::fprintf(stderr, "ASSERT FAIL @ %s:%d: %d != %d\n", \
                     __FILE__, __LINE__, static_cast<int>(a), static_cast<int>(b)); \
        return 1; \
    } \
} while (0)

#define ASSERT_NULL(p) do { \
    if ((p) != nullptr) { std::fprintf(stderr, "ASSERT FAIL: not NULL @ %s:%d\n", __FILE__, __LINE__); return 1; } \
} while (0)

int test_extract_no_think_block() {
    const char* response = nullptr; size_t resp_len = 0;
    const char* thinking = nullptr; size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking("hello world",
                                                &response, &resp_len,
                                                &thinking, &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(response, "hello world");
    ASSERT_NULL(thinking);
    return 0;
}

int test_extract_basic_block() {
    const char* response = nullptr; size_t resp_len = 0;
    const char* thinking = nullptr; size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking(
        "before <think>reasoning</think> after",
        &response, &resp_len, &thinking, &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(response, "before\nafter");
    ASSERT_EQ_STR(thinking, "reasoning");
    return 0;
}

int test_extract_only_thinking() {
    const char* response = nullptr; size_t resp_len = 0;
    const char* thinking = nullptr; size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking("<think>just thinking</think>",
                                                &response, &resp_len,
                                                &thinking, &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(response, "");
    ASSERT_EQ_STR(thinking, "just thinking");
    return 0;
}

int test_extract_malformed_keeps_text() {
    const char* response = nullptr; size_t resp_len = 0;
    const char* thinking = nullptr; size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking("</think>before<think>",
                                                &response, &resp_len,
                                                &thinking, &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(response, "</think>before<think>");
    ASSERT_NULL(thinking);
    return 0;
}

int test_strip_multiple_blocks() {
    const char* stripped = nullptr; size_t slen = 0;
    rac_result_t rc = rac_llm_strip_thinking(
        "first <think>a</think> middle <think>b</think> end",
        &stripped, &slen);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(stripped, "first  middle  end");
    return 0;
}

int test_strip_trailing_unclosed() {
    const char* stripped = nullptr; size_t slen = 0;
    rac_result_t rc = rac_llm_strip_thinking(
        "answer here <think>still streaming",
        &stripped, &slen);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(stripped, "answer here");
    return 0;
}

int test_split_tokens_no_thinking() {
    int32_t t = -1, r = -1;
    rac_result_t rc = rac_llm_split_thinking_tokens(100, "answer", nullptr, &t, &r);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(t, 0);
    ASSERT_EQ_INT(r, 100);
    return 0;
}

int test_split_tokens_proportional() {
    int32_t t = -1, r = -1;
    // thinking=20 chars, response=10 chars → ratio 2/3 of 90 = 60
    rac_result_t rc = rac_llm_split_thinking_tokens(
        90, "abcdefghij", "abcdefghijabcdefghij", &t, &r);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(t, 60);
    ASSERT_EQ_INT(r, 30);
    ASSERT_EQ_INT(t + r, 90);
    return 0;
}

int test_split_tokens_zero_total() {
    int32_t t = -1, r = -1;
    rac_result_t rc = rac_llm_split_thinking_tokens(0, "a", "b", &t, &r);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_INT(t, 0);
    ASSERT_EQ_INT(r, 0);
    return 0;
}

int test_null_inputs_rejected() {
    const char* response = nullptr; size_t resp_len = 0;
    const char* thinking = nullptr; size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking(nullptr, &response, &resp_len,
                                                &thinking, &think_len);
    ASSERT_EQ_INT(rc, RAC_ERROR_NULL_POINTER);
    rc = rac_llm_strip_thinking(nullptr, &response, &resp_len);
    ASSERT_EQ_INT(rc, RAC_ERROR_NULL_POINTER);
    return 0;
}

}  // namespace

int main() {
    int failures = 0;
#define RUN(name) do { \
    std::printf("[ RUN  ] %s\n", #name); \
    int rc = name(); \
    if (rc == 0) std::printf("[  OK  ] %s\n", #name); \
    else { std::printf("[ FAIL ] %s\n", #name); ++failures; } \
} while (0)

    RUN(test_extract_no_think_block);
    RUN(test_extract_basic_block);
    RUN(test_extract_only_thinking);
    RUN(test_extract_malformed_keeps_text);
    RUN(test_strip_multiple_blocks);
    RUN(test_strip_trailing_unclosed);
    RUN(test_split_tokens_no_thinking);
    RUN(test_split_tokens_proportional);
    RUN(test_split_tokens_zero_total);
    RUN(test_null_inputs_rejected);

    std::printf("\n%d test(s) failed\n", failures);
    return failures == 0 ? 0 : 1;
}
