/**
 * @file test_llm_thinking.cpp
 * @brief Behavioral parity test for rac_llm_thinking C ABI vs Swift
 *        ThinkingContentParser (the type it replaces).
 *
 * Each test mirrors a unit-test scenario from the
 * Swift implementation to lock in byte-equivalent behavior across SDKs.
 */

#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_thinking.h"

// src-internal header (RUN-81): the engine-gated no-think directive helper.
#include "features/llm/llm_thinking_directive_internal.h"
// src-internal headers: the streaming twin of the splitter above, and the
// stream timing arithmetic. Both are header-only and dependency-free precisely
// so they can be exercised here.
#include "features/llm/llm_stream_metrics_internal.h"
#include "features/llm/llm_thinking_stream_internal.h"

#include <vector>

namespace {

#define ASSERT_EQ_STR(actual, expected)                                                           \
    do {                                                                                          \
        if (std::strcmp((actual), (expected)) != 0) {                                             \
            std::fprintf(stderr, "ASSERT FAIL @ %s:%d\n  expected: \"%s\"\n  actual:   \"%s\"\n", \
                         __FILE__, __LINE__, (expected), (actual));                               \
            return 1;                                                                             \
        }                                                                                         \
    } while (0)

#define ASSERT_EQ_INT(a, b)                                                             \
    do {                                                                                \
        if ((a) != (b)) {                                                               \
            std::fprintf(stderr, "ASSERT FAIL @ %s:%d: %d != %d\n", __FILE__, __LINE__, \
                         static_cast<int>(a), static_cast<int>(b));                     \
            return 1;                                                                   \
        }                                                                               \
    } while (0)

#define ASSERT_NULL(p)                                                                   \
    do {                                                                                 \
        if ((p) != nullptr) {                                                            \
            std::fprintf(stderr, "ASSERT FAIL: not NULL @ %s:%d\n", __FILE__, __LINE__); \
            return 1;                                                                    \
        }                                                                                \
    } while (0)

int test_extract_no_think_block() {
    const char* response = nullptr;
    size_t resp_len = 0;
    const char* thinking = nullptr;
    size_t think_len = 0;
    rac_result_t rc =
        rac_llm_extract_thinking("hello world", &response, &resp_len, &thinking, &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(response, "hello world");
    ASSERT_NULL(thinking);
    return 0;
}

int test_extract_basic_block() {
    const char* response = nullptr;
    size_t resp_len = 0;
    const char* thinking = nullptr;
    size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking("before <think>reasoning</think> after", &response,
                                               &resp_len, &thinking, &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(response, "before\nafter");
    ASSERT_EQ_STR(thinking, "reasoning");
    return 0;
}

int test_extract_only_thinking() {
    const char* response = nullptr;
    size_t resp_len = 0;
    const char* thinking = nullptr;
    size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking("<think>just thinking</think>", &response, &resp_len,
                                               &thinking, &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(response, "");
    ASSERT_EQ_STR(thinking, "just thinking");
    return 0;
}

int test_extract_thinking_long_tag() {
    // commons-102: <thinking>...</thinking> must be parsed identically to
    // <think>...</think>, matching the streaming proto path's kOpenTags.
    const char* response = nullptr;
    size_t resp_len = 0;
    const char* thinking = nullptr;
    size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking("Hello <thinking>think</thinking> world", &response,
                                               &resp_len, &thinking, &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(response, "Hello\nworld");
    ASSERT_EQ_STR(thinking, "think");
    return 0;
}

int test_strip_thinking_long_tag() {
    // commons-102: strip must also recognize <thinking>...</thinking>.
    const char* stripped = nullptr;
    size_t slen = 0;
    rac_result_t rc = rac_llm_strip_thinking("first <thinking>a</thinking> middle <think>b</think>",
                                             &stripped, &slen);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(stripped, "first  middle");
    return 0;
}

int test_strip_trailing_unclosed_long_tag() {
    // commons-102: trailing unclosed <thinking>... must also be dropped.
    const char* stripped = nullptr;
    size_t slen = 0;
    rac_result_t rc =
        rac_llm_strip_thinking("answer here <thinking>still streaming", &stripped, &slen);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(stripped, "answer here");
    return 0;
}

int test_extract_close_before_open_no_longer_echoes_tags() {
    // Was `test_extract_malformed_keeps_text`, which asserted the whole string
    // came back verbatim — bare `</think>` and all. That expectation WAS the
    // bug: a closing tag with no opening tag before it is the normal shape of a
    // model whose template prefilled the opening tag, and echoing the delimiter
    // put it on screen. Nothing may return a raw delimiter as answer text.
    const char* response = nullptr;
    size_t resp_len = 0;
    const char* thinking = nullptr;
    size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking("</think>before<think>", &response, &resp_len,
                                               &thinking, &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(response, "before");
    ASSERT_NULL(thinking);
    return 0;
}

// --- the prefilled-opening-tag family -------------------------------------
// maple-preview's manifest sets `gen_prefill: "<think>\n"`, so the opening tag
// is part of the PROMPT and never generated. Generated text is reasoning body,
// closing tag, answer.

int test_extract_prefilled_open_tag() {
    const char* response = nullptr;
    size_t resp_len = 0;
    const char* thinking = nullptr;
    size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking(
        "The answer is Paris. So simple.\n</think>\n\nParis", &response, &resp_len, &thinking,
        &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(response, "Paris");
    ASSERT_EQ_STR(thinking, "The answer is Paris. So simple.");
    return 0;
}

int test_extract_prefilled_open_tag_long_form() {
    // The pair is chosen by the earliest CLOSING tag when no opening tag
    // exists; choosing on the opening tag alone sent this to the `<think>`
    // recognizer, which cannot see `</thinking>`.
    const char* response = nullptr;
    size_t resp_len = 0;
    const char* thinking = nullptr;
    size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking("weighing it up</thinking>Done.", &response,
                                               &resp_len, &thinking, &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(response, "Done.");
    ASSERT_EQ_STR(thinking, "weighing it up");
    return 0;
}

int test_extract_prefilled_with_model_declared_pair() {
    // A model that DOES declare its pattern must split identically to one that
    // does not. That equivalence is the fix: local bundles carry no pattern.
    const char* response = nullptr;
    size_t resp_len = 0;
    const char* thinking = nullptr;
    size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking_with_tags(
        "reasoning body\n</think>\n\nParis", "<think>", "</think>", &response, &resp_len, &thinking,
        &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(response, "Paris");
    ASSERT_EQ_STR(thinking, "reasoning body");
    return 0;
}

int test_extract_whitespace_never_leaks_across_the_boundary() {
    const char* response = nullptr;
    size_t resp_len = 0;
    const char* thinking = nullptr;
    size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking("  \n  reasoning  \n</think>\n\n   Paris.   ",
                                               &response, &resp_len, &thinking, &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(response, "Paris.");
    ASSERT_EQ_STR(thinking, "reasoning");
    return 0;
}

int test_extract_open_never_closed_keeps_every_character() {
    // The generation hit its token cap mid-reasoning. All of it is reasoning,
    // the answer is legitimately empty, and not one character is dropped.
    const char* response = nullptr;
    size_t resp_len = 0;
    const char* thinking = nullptr;
    size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking("<think>still reasoning when the cap hit",
                                               &response, &resp_len, &thinking, &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(response, "");
    ASSERT_EQ_STR(thinking, "still reasoning when the cap hit");
    return 0;
}

int test_extract_no_thinking_is_returned_verbatim() {
    // Not merely "unchanged content" — byte-identical, including the leading
    // and trailing whitespace a trim would have eaten.
    const char* response = nullptr;
    size_t resp_len = 0;
    const char* thinking = nullptr;
    size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking("  a < b, and 3 > 2.  ", &response, &resp_len,
                                               &thinking, &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(response, "  a < b, and 3 > 2.  ");
    ASSERT_NULL(thinking);
    return 0;
}

int test_extract_trailing_unclosed_thinking() {
    const char* response = nullptr;
    size_t resp_len = 0;
    const char* thinking = nullptr;
    size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking(
        "visible answer <think>unfinished private reasoning", &response, &resp_len, &thinking,
        &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(response, "visible answer");
    ASSERT_EQ_STR(thinking, "unfinished private reasoning");
    return 0;
}

int test_strip_multiple_blocks() {
    const char* stripped = nullptr;
    size_t slen = 0;
    rac_result_t rc = rac_llm_strip_thinking("first <think>a</think> middle <think>b</think> end",
                                             &stripped, &slen);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(stripped, "first  middle  end");
    return 0;
}

int test_strip_prefilled_open_tag_region() {
    // The voice agent runs strip before TTS. Without the close-before-open rule
    // a prefilled-reasoning model did not merely display its chain of thought,
    // it SPOKE it — bare `</think>` and all.
    const char* stripped = nullptr;
    size_t slen = 0;
    rac_result_t rc = rac_llm_strip_thinking("The user asks the capital of France.\n</think>\n\nParis.",
                                             &stripped, &slen);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(stripped, "Paris.");
    return 0;
}

int test_strip_never_leaves_a_bare_close_tag() {
    // Same rule as the splitter: the first close-before-open takes the region
    // with it, a later one is dropped as a delimiter while its surrounding text
    // survives. strip and extract must not disagree — they did.
    const char* stripped = nullptr;
    size_t slen = 0;
    rac_result_t rc = rac_llm_strip_thinking("R1</think>A1</think>A2", &stripped, &slen);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(stripped, "A1A2");
    return 0;
}

int test_strip_trailing_unclosed() {
    const char* stripped = nullptr;
    size_t slen = 0;
    rac_result_t rc =
        rac_llm_strip_thinking("answer here <think>still streaming", &stripped, &slen);
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
    rac_result_t rc =
        rac_llm_split_thinking_tokens(90, "abcdefghij", "abcdefghijabcdefghij", &t, &r);
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
    const char* response = nullptr;
    size_t resp_len = 0;
    const char* thinking = nullptr;
    size_t think_len = 0;
    rac_result_t rc =
        rac_llm_extract_thinking(nullptr, &response, &resp_len, &thinking, &think_len);
    ASSERT_EQ_INT(rc, RAC_ERROR_NULL_POINTER);
    rc = rac_llm_strip_thinking(nullptr, &response, &resp_len);
    ASSERT_EQ_INT(rc, RAC_ERROR_NULL_POINTER);
    return 0;
}

// RUN-81: the no-think directive passes TWO gates. The engine gate is an
// ALLOWLIST — only QHexRT suppresses natively, so llama.cpp/onnx/cloud still
// receive the Qwen "/no_think" token. The model gate is the decisive one: the
// token is a Qwen control sequence, so a model that does not reason must never
// see it (LFM2.5-230M answers it with "\n\n" and stops). This locks both at the
// helper level.
int test_no_think_directive_engine_gated() {
    using rac::llm::apply_no_think_directive;
    using rac::llm::engine_handles_disable_thinking_natively;

    ASSERT_EQ_INT(engine_handles_disable_thinking_natively(RAC_FRAMEWORK_QHEXRT), true);
    ASSERT_EQ_INT(engine_handles_disable_thinking_natively(RAC_FRAMEWORK_LLAMACPP), false);
    ASSERT_EQ_INT(engine_handles_disable_thinking_natively(RAC_FRAMEWORK_ONNX), false);
    ASSERT_EQ_INT(engine_handles_disable_thinking_natively(RAC_FRAMEWORK_MLX), false);
    ASSERT_EQ_INT(engine_handles_disable_thinking_natively(RAC_FRAMEWORK_UNKNOWN), false);

    // disable=false is a passthrough regardless of engine or model.
    ASSERT_EQ_STR(apply_no_think_directive("hi", RAC_FALSE, RAC_FRAMEWORK_LLAMACPP, true).c_str(),
                  "hi");
    ASSERT_EQ_STR(apply_no_think_directive("hi", RAC_FALSE, RAC_FRAMEWORK_QHEXRT, true).c_str(),
                  "hi");

    // disable=true on a REASONING model: injected for non-native engines,
    // skipped for QHexRT.
    ASSERT_EQ_STR(apply_no_think_directive("hi", RAC_TRUE, RAC_FRAMEWORK_LLAMACPP, true).c_str(),
                  "/no_think\nhi");
    ASSERT_EQ_STR(apply_no_think_directive("hi", RAC_TRUE, RAC_FRAMEWORK_ONNX, true).c_str(),
                  "/no_think\nhi");
    ASSERT_EQ_STR(apply_no_think_directive("hi", RAC_TRUE, RAC_FRAMEWORK_UNKNOWN, true).c_str(),
                  "/no_think\nhi");
    ASSERT_EQ_STR(apply_no_think_directive("hi", RAC_TRUE, RAC_FRAMEWORK_QHEXRT, true).c_str(),
                  "hi");

    // disable=true on a NON-REASONING model: never injected, on any engine and
    // whether or not the framework is even known. This is what makes
    // ReasoningMode.OFF safe to send from every SDK.
    ASSERT_EQ_STR(apply_no_think_directive("hi", RAC_TRUE, RAC_FRAMEWORK_LLAMACPP, false).c_str(),
                  "hi");
    ASSERT_EQ_STR(apply_no_think_directive("hi", RAC_TRUE, RAC_FRAMEWORK_ONNX, false).c_str(), "hi");
    ASSERT_EQ_STR(apply_no_think_directive("hi", RAC_TRUE, RAC_FRAMEWORK_QHEXRT, false).c_str(),
                  "hi");
    ASSERT_EQ_STR(apply_no_think_directive("hi", RAC_TRUE, RAC_FRAMEWORK_UNKNOWN, false).c_str(),
                  "hi");
    return 0;
}

// --- the STREAMING splitter -----------------------------------------------
// Same rules as the whole-text splitter above, applied delta by delta. The
// interesting failures are all about chunk boundaries, so every case here is
// fed in more than one shape.

struct StreamRun {
    std::string reasoning;
    std::string content;
    int reclassifications = 0;
};

std::string trim_ws(const std::string& s) {
    constexpr const char* kWs = " \t\n\r\v\f";
    const size_t b = s.find_first_not_of(kWs);
    if (b == std::string::npos) {
        return {};
    }
    return s.substr(b, s.find_last_not_of(kWs) - b + 1);
}

/** Mirrors exactly what llm_module.cpp's apply_thinking_segment does with the
 *  segments, including the terminal trim, so this asserts the shipped
 *  behaviour and not a parallel reimplementation of it. */
StreamRun run_stream(const std::vector<std::string>& deltas) {
    StreamRun r;
    rac::llm::ThinkingStreamSplitter splitter;
    std::vector<rac::llm::ThinkingStreamSegment> segments;
    auto apply = [&r](const std::vector<rac::llm::ThinkingStreamSegment>& segs) {
        for (const auto& seg : segs) {
            if (seg.reclassify_prior_content_as_reasoning) {
                r.reasoning.insert(0, r.content);
                r.content.clear();
                ++r.reclassifications;
            }
            (seg.channel == rac::llm::ThinkingChannel::kReasoning ? r.reasoning : r.content) +=
                seg.text;
        }
    };
    for (const auto& delta : deltas) {
        segments.clear();
        splitter.push(delta, &segments);
        apply(segments);
    }
    segments.clear();
    splitter.flush(&segments);
    apply(segments);
    r.reasoning = trim_ws(r.reasoning);
    r.content = trim_ws(r.content);
    return r;
}

std::vector<std::string> one_char_at_a_time(const std::string& s) {
    std::vector<std::string> v;
    for (char c : s) {
        v.push_back(std::string(1, c));
    }
    return v;
}

int test_stream_prefilled_open_tag() {
    const std::string maple = "The answer is Paris. So simple.\n</think>\n\nParis";
    StreamRun whole = run_stream({maple});
    ASSERT_EQ_STR(whole.content.c_str(), "Paris");
    ASSERT_EQ_STR(whole.reasoning.c_str(), "The answer is Paris. So simple.");
    ASSERT_EQ_INT(whole.reclassifications, 1);

    // One character per delta is the harshest chunking that exists, and it is
    // not hypothetical: it is what a per-token callback looks like.
    StreamRun chars = run_stream(one_char_at_a_time(maple));
    ASSERT_EQ_STR(chars.content.c_str(), "Paris");
    ASSERT_EQ_STR(chars.reasoning.c_str(), "The answer is Paris. So simple.");
    return 0;
}

int test_stream_closing_tag_split_at_every_position() {
    // The regression this exists for: a per-delta find() sees neither half of a
    // straddling `</think>`, so reasoning leaks into the answer on SOME runs
    // only — which reads as a flaky model rather than a bug.
    const std::string tag = "</think>";
    for (size_t at = 0; at <= tag.size(); ++at) {
        StreamRun r = run_stream({"reasoning body", tag.substr(0, at), tag.substr(at), "\n\nAnswer."});
        ASSERT_EQ_STR(r.content.c_str(), "Answer.");
        ASSERT_EQ_STR(r.reasoning.c_str(), "reasoning body");
    }
    return 0;
}

int test_stream_opening_tag_split_across_deltas() {
    StreamRun r = run_stream({"<thi", "nk>weighing", " it</thi", "nk>The answer."});
    ASSERT_EQ_STR(r.content.c_str(), "The answer.");
    ASSERT_EQ_STR(r.reasoning.c_str(), "weighing it");
    return 0;
}

int test_stream_matched_pair() {
    StreamRun r = run_stream({"<think>weighing it</think>", "The answer."});
    ASSERT_EQ_STR(r.content.c_str(), "The answer.");
    ASSERT_EQ_STR(r.reasoning.c_str(), "weighing it");
    return 0;
}

int test_stream_no_thinking_is_untouched() {
    StreamRun r = run_stream({"Paris is the capital.", " Nothing else."});
    ASSERT_EQ_STR(r.content.c_str(), "Paris is the capital. Nothing else.");
    ASSERT_EQ_STR(r.reasoning.c_str(), "");
    // A response with no reasoning must never trigger the retroactive move.
    ASSERT_EQ_INT(r.reclassifications, 0);
    return 0;
}

int test_stream_open_never_closed_loses_nothing() {
    StreamRun r = run_stream({"<think>still reasoning ", "when the cap hit"});
    ASSERT_EQ_STR(r.content.c_str(), "");
    ASSERT_EQ_STR(r.reasoning.c_str(), "still reasoning when the cap hit");
    return 0;
}

int test_stream_partial_tag_tail_is_released_at_end_of_stream() {
    // Held back because it could still have become `</think>`; once the stream
    // ends it is ordinary text and must be delivered, not swallowed.
    StreamRun r = run_stream({"a < b and c </"});
    ASSERT_EQ_STR(r.content.c_str(), "a < b and c </");
    return 0;
}

int test_stream_second_stray_close_does_not_eat_the_answer() {
    // Only the FIRST closing tag reclassifies. A later stray one is dropped so
    // no delimiter reaches the answer, but the answer survives.
    StreamRun r = run_stream({"body</think>Answer with </think> inside."});
    ASSERT_EQ_STR(r.content.c_str(), "Answer with inside.");
    ASSERT_EQ_STR(r.reasoning.c_str(), "body");
    ASSERT_EQ_INT(r.reclassifications, 1);
    return 0;
}

// --- the whole-text splitter's loop ---------------------------------------
// It used to consume ONE leading close-before-open plus ONE matched pair and
// then append the remainder verbatim, which is how a bare `</think>` and a whole
// second reasoning block reached the answer on the non-streaming path while the
// streaming twin — which loops — got both right.

int test_extract_second_bare_close_is_swallowed_not_echoed() {
    const char* response = nullptr;
    size_t resp_len = 0;
    const char* thinking = nullptr;
    size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking("R1</think>A1</think>A2", &response, &resp_len,
                                               &thinking, &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    // Only the first close-before-open reclassifies; the second is a delimiter
    // that must not be rendered, but the answer either side of it survives.
    ASSERT_EQ_STR(response, "A1\nA2");
    ASSERT_EQ_STR(thinking, "R1");
    return 0;
}

int test_extract_every_reasoning_block_is_split() {
    const char* response = nullptr;
    size_t resp_len = 0;
    const char* thinking = nullptr;
    size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking("<think>a</think>X<think>b</think>Y", &response,
                                               &resp_len, &thinking, &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(response, "X\nY");
    ASSERT_EQ_STR(thinking, "a\nb");
    return 0;
}

int test_extract_literal_close_tag_never_reaches_the_answer() {
    // A model discussing `</think>` in prose loses the delimiter from the
    // answer. Deliberate, and now identical on both paths: echoing it is the
    // production bug this family exists to stop, and a rendered delimiter is
    // worse than a missing one.
    const char* response = nullptr;
    size_t resp_len = 0;
    const char* thinking = nullptr;
    size_t think_len = 0;
    rac_result_t rc = rac_llm_extract_thinking("<think>plan</think>The tag is </think> literally.",
                                               &response, &resp_len, &thinking, &think_len);
    ASSERT_EQ_INT(rc, RAC_SUCCESS);
    ASSERT_EQ_STR(response, "The tag is\nliterally.");
    ASSERT_EQ_STR(thinking, "plan");
    return 0;
}

// --- the shipped streaming WIRING -----------------------------------------
// Everything above exercises the splitter alone. Three of the defects this file
// pins lived in llm_module.cpp's use of it, not in the splitter: whether a
// declared pattern ASSERTS prefilled reasoning or merely arms a hold, where the
// terminal split comes from, and when the content clock starts. So this harness
// replays the wiring itself.

struct ModuleStream {
    /** What the consumer actually received, in order, per channel. */
    std::string live_content;
    std::string live_reasoning;
    /** LLMGenerationResult.text / .thinking_content on the terminal event. */
    std::string final_content;
    std::string final_reasoning;
    /** Index of the delta that `timing.first_content_token_ms` ends up dated
     *  from; -1 when no content token was ever produced. */
    int first_content_delta = -1;
};

ModuleStream run_module_stream(const std::vector<std::string>& deltas,
                               const std::string& open_tag = "",
                               const std::string& close_tag = "",
                               bool disable_thinking = false) {
    rac::llm::ThinkingStreamSplitter splitter;
    if (!open_tag.empty() && !close_tag.empty()) {
        std::vector<rac::llm::ThinkingTagPair> pairs;
        pairs.push_back({open_tag, close_tag});
        for (auto& builtin : rac::llm::default_thinking_tag_pairs()) {
            pairs.push_back(std::move(builtin));
        }
        splitter.set_pairs(std::move(pairs));
        if (!disable_thinking) {
            splitter.set_hold_ambiguous_prefix(true);
        }
    }

    ModuleStream out;
    std::string raw;
    std::vector<rac::llm::ThinkingStreamSegment> segments;
    int provisional_delta = -1;  // stands in for ctx->provisional_content_ms

    auto apply = [&](const rac::llm::ThinkingStreamSegment& seg, int delta_index) {
        if (seg.reclassify_prior_content_as_reasoning) {
            out.first_content_delta = -1;
            provisional_delta = -1;
        }
        if (seg.text.empty()) {
            return;
        }
        if (seg.channel == rac::llm::ThinkingChannel::kReasoning) {
            provisional_delta = -1;
            out.live_reasoning += seg.text;
        } else {
            if (out.first_content_delta < 0) {
                out.first_content_delta =
                    provisional_delta >= 0 ? provisional_delta : delta_index;
            }
            provisional_delta = -1;
            out.live_content += seg.text;
        }
    };

    for (size_t i = 0; i < deltas.size(); ++i) {
        raw += deltas[i];
        segments.clear();
        splitter.push(deltas[i], &segments);
        for (const auto& seg : segments) {
            apply(seg, static_cast<int>(i));
        }
        if (provisional_delta < 0 && splitter.holding_ambiguous_prefix()) {
            provisional_delta = static_cast<int>(i);
        }
    }
    segments.clear();
    splitter.flush(&segments);
    for (const auto& seg : segments) {
        apply(seg, static_cast<int>(deltas.size()));
    }

    // dispatch_terminal_once: the terminal split is recomputed from the raw text
    // by the whole-text splitter, so it cannot disagree with the unary verb.
    const char* answer = nullptr;
    size_t answer_len = 0;
    const char* reasoning = nullptr;
    size_t reasoning_len = 0;
    (void)rac_llm_extract_thinking_with_tags(raw.c_str(),
                                             open_tag.empty() ? nullptr : open_tag.c_str(),
                                             close_tag.empty() ? nullptr : close_tag.c_str(),
                                             &answer, &answer_len, &reasoning, &reasoning_len);
    out.final_content.assign(answer != nullptr ? answer : "", answer_len);
    out.final_reasoning.assign(reasoning != nullptr ? reasoning : "", reasoning_len);
    return out;
}

int test_declared_pattern_without_reasoning_keeps_the_whole_answer() {
    // THE data-loss case. `normalize_thinking_capability()` gives every model
    // with `supports_thinking` a default `<think>`/`</think>` pattern, so a
    // declared pattern says the model CAN reason, not that its template
    // prefilled the opening tag. When such a model answers without reasoning
    // there is no closing tag at all, and asserting "we began inside reasoning"
    // sent the entire answer to the reasoning channel — which
    // `include_in_output == false` (the default) then discards. Zero deltas,
    // empty text.
    ModuleStream r = run_module_stream({"Just ", "an ", "answer."}, "<think>", "</think>");
    ASSERT_EQ_STR(r.final_content.c_str(), "Just an answer.");
    ASSERT_EQ_STR(r.final_reasoning.c_str(), "");
    // Delivered, not merely reconstructed at the end: the hold released it.
    ASSERT_EQ_STR(r.live_content.c_str(), "Just an answer.");
    ASSERT_EQ_STR(r.live_reasoning.c_str(), "");
    return 0;
}

int test_start_inside_reasoning_is_the_assertion_that_loses_the_answer() {
    // Pins WHY the wiring no longer calls this on a declared pattern. The
    // splitter is not wrong here — the caller would be. Kept as an executable
    // statement of the failure mode so nobody re-derives it in production.
    rac::llm::ThinkingStreamSplitter splitter;
    splitter.start_inside_reasoning();
    std::vector<rac::llm::ThinkingStreamSegment> segments;
    splitter.push("Just an answer.", &segments);
    splitter.flush(&segments);
    std::string content;
    std::string reasoning;
    for (const auto& seg : segments) {
        (seg.channel == rac::llm::ThinkingChannel::kReasoning ? reasoning : content) += seg.text;
    }
    ASSERT_EQ_STR(content.c_str(), "");
    ASSERT_EQ_STR(reasoning.c_str(), "Just an answer.");
    return 0;
}

int test_hold_keeps_prefilled_reasoning_off_the_content_channel() {
    // The requirement the whole split exists for: a consumer reading the answer
    // channel must never be handed the chain of thought, LIVE — not merely
    // corrected at the end. maple-preview's shape, delta for delta.
    ModuleStream r =
        run_module_stream({"The user", " asks 2+2", ".", "</think>", "4"}, "<think>", "</think>");
    ASSERT_EQ_STR(r.live_content.c_str(), "4");
    ASSERT_EQ_STR(r.live_reasoning.c_str(), "The user asks 2+2.");
    ASSERT_EQ_STR(r.final_content.c_str(), "4");
    ASSERT_EQ_STR(r.final_reasoning.c_str(), "The user asks 2+2.");
    return 0;
}

int test_without_model_metadata_the_terminal_result_is_still_right() {
    // No declared pattern means no evidence that a prefilled reasoning block is
    // even possible, so the hold is not armed and deltas stay optimistic. That
    // is a knowing trade — holding every model's answer on no evidence would
    // trade streaming itself for a rare fault — and the terminal result is
    // still correct because it is recomputed, not accumulated.
    ModuleStream r = run_module_stream({"The user", " asks 2+2", ".", "</think>", "4"});
    ASSERT_EQ_STR(r.final_content.c_str(), "4");
    ASSERT_EQ_STR(r.final_reasoning.c_str(), "The user asks 2+2.");
    return 0;
}

int test_disable_thinking_arms_no_hold() {
    // Nothing is coming to hold for, so the answer must stream from delta 0.
    ModuleStream r = run_module_stream({"Just ", "an ", "answer."}, "<think>", "</think>",
                                       /*disable_thinking=*/true);
    ASSERT_EQ_STR(r.live_content.c_str(), "Just an answer.");
    ASSERT_EQ_INT(r.first_content_delta, 0);
    return 0;
}

int test_preamble_before_a_generated_open_tag_stays_in_the_answer() {
    // An opening tag proves the text before it was answer text, not a prefilled
    // reasoning body. Asserting prefilled reasoning misfiled "Hello" as thought
    // and left the answer as just "world".
    ModuleStream r = run_module_stream({"Hello <think>hmm</think> world"}, "<think>", "</think>");
    ASSERT_EQ_STR(r.final_reasoning.c_str(), "hmm");
    ASSERT_EQ_STR(r.final_content.c_str(), "Hello\nworld");
    ASSERT_EQ_STR(r.live_reasoning.c_str(), "hmm");
    // The live channel keeps the model's own spacing; the whole-text splitter
    // reflows regions with '\n' for Swift parity. That is the ONE documented
    // difference between the two, asserted here in both directions.
    ASSERT_EQ_STR(r.live_content.c_str(), "Hello world");
    return 0;
}

int test_first_content_token_is_dated_from_the_content_boundary() {
    // `first_content_token_ms` is stamped on the first non-THOUGHT segment. With
    // no declared pattern that is delta 0, and the retroactive correction used
    // to rewrite the accumulators without resetting the clock — so
    // time-to-first-content silently collapsed into TTFT on exactly the models
    // that prefill their opening tag.
    ModuleStream r = run_module_stream({"The user", " asks 2+2", ".", "</think>", "4"});
    ASSERT_EQ_INT(r.first_content_delta, 4);

    // Same boundary with the pattern declared (the hold path).
    ModuleStream g =
        run_module_stream({"The user", " asks 2+2", ".", "</think>", "4"}, "<think>", "</think>");
    ASSERT_EQ_INT(g.first_content_delta, 4);

    // And text released from the hold is dated from when the ENGINE produced it,
    // not from when the hold let go — otherwise the hold would report itself as
    // latency the model never spent.
    ModuleStream h = run_module_stream({"Just ", "an ", "answer."}, "<think>", "</think>");
    ASSERT_EQ_INT(h.first_content_delta, 0);
    return 0;
}

int test_hold_has_a_backstop() {
    // The hold normally ends at the model's own closing tag. The byte ceiling is
    // there so a pathological stream cannot buffer without bound; past it the
    // splitter falls back to the optimistic rule rather than growing forever.
    std::vector<std::string> deltas;
    const size_t chunk = 4096;
    const size_t total = rac::llm::ThinkingStreamSplitter::kAmbiguousHoldLimitBytes + chunk;
    for (size_t sent = 0; sent < total; sent += chunk) {
        deltas.push_back(std::string(chunk, 'x'));
    }
    ModuleStream r = run_module_stream(deltas, "<think>", "</think>");
    if (r.live_content.size() < total) {
        std::fprintf(stderr, "hold never released: %zu of %zu bytes\n", r.live_content.size(),
                     total);
        return 1;
    }
    ASSERT_EQ_STR(r.final_reasoning.c_str(), "");
    return 0;
}

/** Everything except the visible characters. Used to compare the live channels
 *  with the whole-text split: the two put the same CHARACTERS on the same
 *  channel, and differ only in that the whole-text splitter trims each region
 *  and joins multiple answer regions with '\n' (Swift parity) while the live
 *  channel delivers the model's own spacing. */
std::string strip_ws(const std::string& s) {
    std::string out;
    for (char c : s) {
        if (c != ' ' && c != '\t' && c != '\n' && c != '\r' && c != '\v' && c != '\f') {
            out += c;
        }
    }
    return out;
}

int test_stream_and_unary_agree() {
    // `llm_thinking_stream_internal.h` claims this agreement in its header. It
    // claimed it before too, and named this file as the proof — while no such
    // test existed and the two in fact disagreed about trailing whitespace, a
    // second bare closing tag, and a second reasoning block. This is that test.
    struct Case {
        const char* text;
        const char* expect_content;
        const char* expect_reasoning;
    };
    const Case cases[] = {
        {"The answer is Paris. So simple.\n</think>\n\nParis", "Paris",
         "The answer is Paris. So simple."},
        {"<think>weighing it</think>The answer.", "The answer.", "weighing it"},
        {"<think>\r\nreason\r\n</think>\r\nanswer\r\n", "answer", "reason"},
        {"R1</think>A1</think>A2", "A1\nA2", "R1"},
        {"<think>plan</think>The tag is </think> literally.", "The tag is\nliterally.", "plan"},
        {"Hello <think>hmm</think> world", "Hello\nworld", "hmm"},
        {"Just an answer.", "Just an answer.", ""},
        {"weighing it up</thinking>Done.", "Done.", "weighing it up"},
        {"<think>a</think>X<think>b</think>Y", "X\nY", "a\nb"},
        {"answer so far <think>cut off mid-reason", "answer so far", "cut off mid-reason"},
    };

    for (const auto& c : cases) {
        const std::string text(c.text);
        // Every chunking that matters: whole, one character at a time, and cut
        // at every single byte offset. A delimiter straddling the cut is the
        // failure mode this whole type exists for.
        std::vector<std::vector<std::string>> chunkings;
        chunkings.push_back({text});
        chunkings.push_back(one_char_at_a_time(text));
        for (size_t at = 1; at < text.size(); ++at) {
            chunkings.push_back({text.substr(0, at), text.substr(at)});
        }

        for (const auto& deltas : chunkings) {
            // The declared-pattern wiring: the hold makes the LIVE channels
            // correct, which is the only configuration in which they can be
            // compared to the whole-text split at all.
            ModuleStream r = run_module_stream(deltas, "<think>", "</think>");
            if (r.final_content != c.expect_content || r.final_reasoning != c.expect_reasoning) {
                std::fprintf(stderr,
                             "ASSERT FAIL @ %s:%d terminal split for \"%s\"\n"
                             "  content   expected \"%s\" actual \"%s\"\n"
                             "  reasoning expected \"%s\" actual \"%s\"\n",
                             __FILE__, __LINE__, c.text, c.expect_content,
                             r.final_content.c_str(), c.expect_reasoning,
                             r.final_reasoning.c_str());
                return 1;
            }
            if (strip_ws(r.live_content) != strip_ws(r.final_content) ||
                strip_ws(r.live_reasoning) != strip_ws(r.final_reasoning)) {
                std::fprintf(stderr,
                             "ASSERT FAIL @ %s:%d live vs whole-text for \"%s\"\n"
                             "  live content   \"%s\" vs \"%s\"\n"
                             "  live reasoning \"%s\" vs \"%s\"\n",
                             __FILE__, __LINE__, c.text, r.live_content.c_str(),
                             r.final_content.c_str(), r.live_reasoning.c_str(),
                             r.final_reasoning.c_str());
                return 1;
            }
        }
    }
    return 0;
}

// --- stream timing arithmetic ---------------------------------------------

int test_metrics_known_timings() {
    // Synthetic, exact. 41 tokens, first at +500 ms, last at +3000 ms.
    rac::llm::StreamTokenTiming t;
    t.started_ms = 1000;
    t.first_token_ms = 1500;
    t.first_content_token_ms = 3000;
    t.last_token_ms = 4000;
    t.completed_ms = 4100;
    t.total_tokens = 41;

    rac::llm::StreamTimingMetrics m = rac::llm::compute_stream_timing(t);
    ASSERT_EQ_INT(static_cast<int>(m.wall_ms), 3100);
    ASSERT_EQ_INT(static_cast<int>(m.ttft_ms), 500);
    // The number the old code called TTFT — and the reason its rate read 20x
    // high, since it then used (total − this) as the decode window.
    ASSERT_EQ_INT(static_cast<int>(m.time_to_first_content_token_ms), 2000);
    ASSERT_EQ_INT(static_cast<int>(m.decode_ms), 2500);
    ASSERT_EQ_INT(m.batch_buffered ? 1 : 0, 0);
    // (41 − 1) tokens over 2.5 s = 16.0 exactly.
    ASSERT_EQ_INT(static_cast<int>(m.decode_tokens_per_second * 100.0 + 0.5), 1600);

    // Content rate is a different window (first CONTENT token to last): 5
    // content tokens over 1.0 s = (5 − 1) / 1.0 = 4.0.
    rac::llm::set_content_rate(&m, t, 5);
    ASSERT_EQ_INT(static_cast<int>(m.content_tokens_per_second * 100.0 + 0.5), 400);
    return 0;
}

int test_metrics_single_token_does_not_divide_by_zero() {
    rac::llm::StreamTokenTiming t;
    t.started_ms = 1000;
    t.first_token_ms = 1500;
    t.first_content_token_ms = 1500;
    t.last_token_ms = 1500;  // zero-length decode window
    t.completed_ms = 2000;
    t.total_tokens = 1;

    rac::llm::StreamTimingMetrics m = rac::llm::compute_stream_timing(t);
    ASSERT_EQ_INT(static_cast<int>(m.decode_ms), 0);
    // Falls back to the wall clock rather than dividing by zero or reporting a
    // fabricated rate: 1 token over 1.0 s.
    ASSERT_EQ_INT(static_cast<int>(m.decode_tokens_per_second * 100.0 + 0.5), 100);
    return 0;
}

int test_metrics_no_reasoning_content_time_equals_ttft() {
    rac::llm::StreamTokenTiming t;
    t.started_ms = 0;
    t.first_token_ms = 200;
    t.first_content_token_ms = 200;  // first token was already content
    t.last_token_ms = 1200;
    t.completed_ms = 1300;
    t.total_tokens = 11;

    rac::llm::StreamTimingMetrics m = rac::llm::compute_stream_timing(t);
    ASSERT_EQ_INT(static_cast<int>(m.ttft_ms), 200);
    ASSERT_EQ_INT(static_cast<int>(m.time_to_first_content_token_ms), 200);
    // 10 tokens over 1.0 s.
    ASSERT_EQ_INT(static_cast<int>(m.decode_tokens_per_second * 100.0 + 0.5), 1000);
    return 0;
}

int test_metrics_reasoning_only_reports_no_content_time() {
    // Cap hit before `</think>`: no content token was ever produced, so the
    // honest answer is 0, not a silent fallback to the any-kind figure.
    rac::llm::StreamTokenTiming t;
    t.started_ms = 0;
    t.first_token_ms = 300;
    t.first_content_token_ms = 0;
    t.last_token_ms = 2300;
    t.completed_ms = 2400;
    t.total_tokens = 65;

    rac::llm::StreamTimingMetrics m = rac::llm::compute_stream_timing(t);
    ASSERT_EQ_INT(static_cast<int>(m.ttft_ms), 300);
    ASSERT_EQ_INT(static_cast<int>(m.time_to_first_content_token_ms), 0);
    // 64 tokens over 2.0 s = 32.0 — the reasoning tokens still count, because
    // the accelerator decoded every one of them.
    ASSERT_EQ_INT(static_cast<int>(m.decode_tokens_per_second * 100.0 + 0.5), 3200);
    rac::llm::set_content_rate(&m, t, 0);
    ASSERT_EQ_INT(static_cast<int>(m.content_tokens_per_second * 100.0 + 0.5), 0);
    return 0;
}

int test_metrics_batch_buffered_falls_back_to_wall_clock() {
    // A backend that releases every delta at once has no real decode window.
    rac::llm::StreamTokenTiming t;
    t.started_ms = 0;
    t.first_token_ms = 4000;
    t.first_content_token_ms = 4000;
    t.last_token_ms = 4010;
    t.completed_ms = 4020;
    t.total_tokens = 40;

    rac::llm::StreamTimingMetrics m = rac::llm::compute_stream_timing(t);
    ASSERT_EQ_INT(m.batch_buffered ? 1 : 0, 1);
    // 40 tokens over 4.02 s ≈ 9.95 — errs LOW, the safe direction for a floor.
    // Over the 10 ms window it would have claimed 3900 tok/s.
    ASSERT_EQ_INT(static_cast<int>(m.decode_tokens_per_second * 100.0 + 0.5), 995);
    return 0;
}

}  // namespace

int main() {
    int failures = 0;
#define RUN(name)                                \
    do {                                         \
        std::printf("[ RUN  ] %s\n", #name);     \
        int rc = name();                         \
        if (rc == 0)                             \
            std::printf("[  OK  ] %s\n", #name); \
        else {                                   \
            std::printf("[ FAIL ] %s\n", #name); \
            ++failures;                          \
        }                                        \
    } while (0)

    RUN(test_extract_no_think_block);
    RUN(test_extract_basic_block);
    RUN(test_extract_only_thinking);
    RUN(test_extract_thinking_long_tag);
    RUN(test_strip_thinking_long_tag);
    RUN(test_strip_trailing_unclosed_long_tag);
    RUN(test_extract_close_before_open_no_longer_echoes_tags);
    RUN(test_extract_prefilled_open_tag);
    RUN(test_extract_prefilled_open_tag_long_form);
    RUN(test_extract_prefilled_with_model_declared_pair);
    RUN(test_extract_whitespace_never_leaks_across_the_boundary);
    RUN(test_extract_open_never_closed_keeps_every_character);
    RUN(test_extract_no_thinking_is_returned_verbatim);
    RUN(test_extract_trailing_unclosed_thinking);
    RUN(test_stream_prefilled_open_tag);
    RUN(test_stream_closing_tag_split_at_every_position);
    RUN(test_stream_opening_tag_split_across_deltas);
    RUN(test_stream_matched_pair);
    RUN(test_stream_no_thinking_is_untouched);
    RUN(test_stream_open_never_closed_loses_nothing);
    RUN(test_stream_partial_tag_tail_is_released_at_end_of_stream);
    RUN(test_stream_second_stray_close_does_not_eat_the_answer);
    RUN(test_extract_second_bare_close_is_swallowed_not_echoed);
    RUN(test_extract_every_reasoning_block_is_split);
    RUN(test_extract_literal_close_tag_never_reaches_the_answer);
    RUN(test_declared_pattern_without_reasoning_keeps_the_whole_answer);
    RUN(test_start_inside_reasoning_is_the_assertion_that_loses_the_answer);
    RUN(test_hold_keeps_prefilled_reasoning_off_the_content_channel);
    RUN(test_without_model_metadata_the_terminal_result_is_still_right);
    RUN(test_disable_thinking_arms_no_hold);
    RUN(test_preamble_before_a_generated_open_tag_stays_in_the_answer);
    RUN(test_first_content_token_is_dated_from_the_content_boundary);
    RUN(test_hold_has_a_backstop);
    RUN(test_stream_and_unary_agree);
    RUN(test_metrics_known_timings);
    RUN(test_metrics_single_token_does_not_divide_by_zero);
    RUN(test_metrics_no_reasoning_content_time_equals_ttft);
    RUN(test_metrics_reasoning_only_reports_no_content_time);
    RUN(test_metrics_batch_buffered_falls_back_to_wall_clock);
    RUN(test_strip_multiple_blocks);
    RUN(test_strip_prefilled_open_tag_region);
    RUN(test_strip_never_leaves_a_bare_close_tag);
    RUN(test_strip_trailing_unclosed);
    RUN(test_split_tokens_no_thinking);
    RUN(test_split_tokens_proportional);
    RUN(test_split_tokens_zero_total);
    RUN(test_null_inputs_rejected);
    RUN(test_no_think_directive_engine_gated);

    std::printf("\n%d test(s) failed\n", failures);
    return failures == 0 ? 0 : 1;
}
