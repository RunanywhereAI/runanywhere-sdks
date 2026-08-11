/**
 * @file test_voice_agent_response_policy.cpp
 * @brief Host-only tests for voice-turn LLM policy and speakable-answer gating.
 */

#include <cstdio>
#include <cstring>

#include "features/voice_agent/voice_agent_internal.h"
#include "features/voice_agent/voice_agent_internal_helpers.h"

namespace {

#define CHECK(condition)                                                                         \
    do {                                                                                         \
        if (!(condition)) {                                                                      \
            std::fprintf(stderr, "CHECK failed at %s:%d: %s\n", __FILE__, __LINE__, #condition); \
            return 1;                                                                            \
        }                                                                                        \
    } while (0)

using rac::voice_agent::detail::make_voice_llm_options;
using rac::voice_agent::detail::split_voice_response;
using rac::voice_agent::detail::validate_voice_response;

int test_short_deterministic_no_thinking_policy() {
    const rac_llm_options_t options = make_voice_llm_options();
    CHECK(options.max_tokens == 96);
    CHECK(options.temperature == 0.0f);
    CHECK(options.top_p == 1.0f);
    CHECK(options.top_k == 1);
    CHECK(options.seed == 1);
    CHECK(options.disable_thinking == RAC_TRUE);
    CHECK(options.streaming_enabled == RAC_FALSE);
    CHECK(options.system_prompt != nullptr);
    CHECK(std::strlen(options.system_prompt) > 0);
    return 0;
}

int test_answer_is_stripped_and_sanitized() {
    const auto response =
        split_voice_response(" \n<think>private reasoning</think>\tHello,\n  world.\x01 ");
    CHECK(response.thinking == "private reasoning");
    CHECK(response.answer == "Hello, world.");
    CHECK(validate_voice_response(response) == RAC_SUCCESS);
    return 0;
}

int test_reasoning_only_output_is_rejected() {
    const auto complete = split_voice_response("<think>spent the whole budget</think>");
    CHECK(complete.answer.empty());
    CHECK(validate_voice_response(complete) == RAC_ERROR_GENERATION_FAILED);

    const auto long_tag = split_voice_response("<thinking>still no answer</thinking>");
    CHECK(long_tag.answer.empty());
    CHECK(validate_voice_response(long_tag) == RAC_ERROR_GENERATION_FAILED);

    const auto truncated = split_voice_response("<think>unfinished hidden reasoning");
    CHECK(truncated.answer.empty());
    CHECK(validate_voice_response(truncated) == RAC_ERROR_GENERATION_FAILED);
    return 0;
}

int test_blank_or_null_output_is_rejected() {
    const auto blank = split_voice_response(" \t\n\r\x01\x7f ");
    CHECK(blank.answer.empty());
    CHECK(validate_voice_response(blank) == RAC_ERROR_GENERATION_FAILED);

    const auto null_output = split_voice_response(nullptr);
    CHECK(null_output.answer.empty());
    CHECK(validate_voice_response(null_output) == RAC_ERROR_GENERATION_FAILED);
    return 0;
}

}  // namespace

int main() {
    int failures = 0;
#define RUN(test)                                \
    do {                                         \
        std::printf("[ RUN  ] %s\n", #test);     \
        const int result = test();               \
        if (result == 0) {                       \
            std::printf("[  OK  ] %s\n", #test); \
        } else {                                 \
            std::printf("[ FAIL ] %s\n", #test); \
            ++failures;                          \
        }                                        \
    } while (0)

    RUN(test_short_deterministic_no_thinking_policy);
    RUN(test_answer_is_stripped_and_sanitized);
    RUN(test_reasoning_only_output_is_rejected);
    RUN(test_blank_or_null_output_is_rejected);
    return failures == 0 ? 0 : 1;
}
