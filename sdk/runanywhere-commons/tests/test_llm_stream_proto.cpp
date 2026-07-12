/**
 * @file test_llm_stream_proto.cpp
 * @brief Unit tests for the LLM proto-byte stream
 *        ABI in rac_llm_stream.cpp.
 *
 * Scenarios:
 *   1. set_stream_proto_callback(NULL handle) returns RAC_ERROR_INVALID_HANDLE.
 *   2. set_stream_proto_callback(non-NULL, callback, ud) returns RAC_SUCCESS
 *      both with Protobuf and with the hand-encoded fallback.
 *   3. Register a callback, drive the dispatcher with a synthetic token
 *      schedule, decode the bytes, assert:
 *        - per-token seq is monotonic and starts > 0
 *        - non-final token events carry the text + is_final=false
 *        - the terminal event carries is_final=true + finish_reason="stop"
 *   4. Error termination round-trips finish_reason="error" + error_message.
 *   5. Unregistering stops further dispatches.
 *
 * Mirrors the shape of test_proto_event_dispatch.cpp (voice agent).
 */

#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_stream.h"

#ifdef RAC_HAVE_PROTOBUF
#include "llm_service.pb.h"

#include "features/llm/rac_llm_stream_internal.h"
#endif

namespace {

struct CapturedCall {
    std::vector<std::vector<uint8_t>> events;
    void* user_data = nullptr;
    size_t call_count = 0;
};

CapturedCall g_capture;

void test_callback(const uint8_t* bytes, size_t size, void* user_data) {
    g_capture.events.emplace_back(bytes, bytes + size);
    g_capture.user_data = user_data;
    g_capture.call_count += 1;
}

void reset_capture() {
    g_capture.events.clear();
    g_capture.user_data = nullptr;
    g_capture.call_count = 0;
}

rac_handle_t fake_handle() {
    static int sentinel = 0;
    return reinterpret_cast<rac_handle_t>(&sentinel);
}

#define ASSERT_TRUE(cond)                                                                   \
    do {                                                                                    \
        if (!(cond)) {                                                                      \
            std::fprintf(stderr, "ASSERT FAILED: %s @ %s:%d\n", #cond, __FILE__, __LINE__); \
            return 1;                                                                       \
        }                                                                                   \
    } while (0)

#define ASSERT_EQ(a, b)                                                                            \
    do {                                                                                           \
        if (!((a) == (b))) {                                                                       \
            std::fprintf(stderr, "ASSERT FAILED: %s == %s @ %s:%d\n", #a, #b, __FILE__, __LINE__); \
            return 1;                                                                              \
        }                                                                                          \
    } while (0)

int test_invalid_handle_rejected() {
    rac_result_t rc = rac_llm_set_stream_proto_callback(nullptr, test_callback, nullptr);
    ASSERT_EQ(rc, RAC_ERROR_INVALID_HANDLE);
    rc = rac_llm_unset_stream_proto_callback(nullptr);
    ASSERT_EQ(rc, RAC_ERROR_INVALID_HANDLE);
    return 0;
}

int test_set_callback_returns_correct_status() {
    rac_result_t rc = rac_llm_set_stream_proto_callback(fake_handle(), test_callback, nullptr);
    ASSERT_EQ(rc, RAC_SUCCESS);
    rac_llm_unset_stream_proto_callback(fake_handle());
    return 0;
}

#ifdef RAC_HAVE_PROTOBUF

rac::llm::LLMStreamEventParams token_event(const char* token, int kind = 1, uint32_t token_id = 0,
                                           float logprob = 0.0f) {
    rac::llm::LLMStreamEventParams event;
    event.token = token;
    event.kind = kind;
    event.token_id = token_id;
    event.logprob = logprob;
    return event;
}

rac::llm::LLMStreamEventParams terminal_event(const char* finish_reason, int kind = 1,
                                              const char* error_message = nullptr) {
    rac::llm::LLMStreamEventParams event;
    event.is_final = true;
    event.kind = kind;
    event.finish_reason = finish_reason;
    event.error_message = error_message;
    return event;
}

int test_synthetic_token_schedule() {
    reset_capture();
    int sentinel = 7;
    rac_llm_set_stream_proto_callback(fake_handle(), test_callback, &sentinel);

    // Synthetic 3-token generation ending with a terminal stop event.
    rac::llm::dispatch_llm_stream_event(fake_handle(), token_event("Hello"));
    rac::llm::dispatch_llm_stream_event(fake_handle(), token_event(" "));
    rac::llm::dispatch_llm_stream_event(fake_handle(), token_event("world"));
    rac::llm::dispatch_llm_stream_event(fake_handle(), terminal_event("stop"));

    ASSERT_EQ(g_capture.call_count, 4U);
    ASSERT_TRUE(g_capture.user_data == &sentinel);

    uint64_t prev_seq = 0;
    for (size_t i = 0; i < g_capture.events.size(); ++i) {
        runanywhere::v1::LLMStreamEvent decoded;
        ASSERT_TRUE(decoded.ParseFromArray(g_capture.events[i].data(),
                                           static_cast<int>(g_capture.events[i].size())));
        ASSERT_TRUE(decoded.seq() > prev_seq);
        prev_seq = decoded.seq();
        ASSERT_EQ(decoded.kind(), runanywhere::v1::TOKEN_KIND_ANSWER);
        if (i == 0)
            ASSERT_EQ(decoded.token(), "Hello");
        if (i == 1)
            ASSERT_EQ(decoded.token(), " ");
        if (i == 2)
            ASSERT_EQ(decoded.token(), "world");
        if (i < 3) {
            ASSERT_EQ(decoded.is_final(), false);
            ASSERT_TRUE(decoded.finish_reason().empty());
        } else {
            ASSERT_EQ(decoded.is_final(), true);
            ASSERT_EQ(decoded.finish_reason(), "stop");
            ASSERT_TRUE(decoded.token().empty());
        }
    }

    rac_llm_unset_stream_proto_callback(fake_handle());
    return 0;
}

int test_error_termination() {
    reset_capture();
    rac_llm_set_stream_proto_callback(fake_handle(), test_callback, nullptr);

    rac::llm::dispatch_llm_stream_event(fake_handle(), token_event("partial"));
    rac::llm::dispatch_llm_stream_event(
        fake_handle(), terminal_event("error", /*kind=*/0, "engine backend vanished"));

    ASSERT_EQ(g_capture.call_count, 2U);

    runanywhere::v1::LLMStreamEvent terminal;
    ASSERT_TRUE(terminal.ParseFromArray(g_capture.events.back().data(),
                                        static_cast<int>(g_capture.events.back().size())));
    ASSERT_EQ(terminal.is_final(), true);
    ASSERT_EQ(terminal.finish_reason(), "error");
    ASSERT_EQ(terminal.error_message(), "engine backend vanished");

    rac_llm_unset_stream_proto_callback(fake_handle());
    return 0;
}

int test_unregister_stops_dispatch() {
    reset_capture();
    rac_llm_set_stream_proto_callback(fake_handle(), test_callback, nullptr);

    rac::llm::dispatch_llm_stream_event(fake_handle(), token_event("first"));
    ASSERT_EQ(g_capture.call_count, 1U);

    rac_llm_unset_stream_proto_callback(fake_handle());

    rac::llm::dispatch_llm_stream_event(fake_handle(), token_event("must-not-fire"));
    ASSERT_EQ(g_capture.call_count, 1U);
    return 0;
}

// Max-token exhaust must emit finish_reason="length"
// (matches OpenAI chat.completions contract).
int test_finish_reason_length_on_max_tokens() {
    reset_capture();
    rac_llm_set_stream_proto_callback(fake_handle(), test_callback, nullptr);

    rac::llm::dispatch_llm_stream_event(fake_handle(), terminal_event("length"));

    runanywhere::v1::LLMStreamEvent terminal;
    ASSERT_TRUE(terminal.ParseFromArray(g_capture.events.back().data(),
                                        static_cast<int>(g_capture.events.back().size())));
    ASSERT_EQ(terminal.is_final(), true);
    ASSERT_EQ(terminal.finish_reason(), "length");

    rac_llm_unset_stream_proto_callback(fake_handle());
    return 0;
}

int test_optional_fields_round_trip() {
    reset_capture();
    rac_llm_set_stream_proto_callback(fake_handle(), test_callback, nullptr);

    rac::llm::dispatch_llm_stream_event(
        fake_handle(), token_event("think", /*kind=*/2, /*token_id=*/12345, /*logprob=*/-0.5f));

    runanywhere::v1::LLMStreamEvent decoded;
    ASSERT_TRUE(decoded.ParseFromArray(g_capture.events.back().data(),
                                       static_cast<int>(g_capture.events.back().size())));
    ASSERT_EQ(decoded.kind(), runanywhere::v1::TOKEN_KIND_THOUGHT);
    ASSERT_EQ(decoded.token_id(), 12345U);
    ASSERT_TRUE(decoded.logprob() < 0.0f);

    rac_llm_unset_stream_proto_callback(fake_handle());
    return 0;
}

#endif /* RAC_HAVE_PROTOBUF */

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

    RUN(test_invalid_handle_rejected);
    RUN(test_set_callback_returns_correct_status);

#ifdef RAC_HAVE_PROTOBUF
    RUN(test_synthetic_token_schedule);
    RUN(test_error_termination);
    RUN(test_finish_reason_length_on_max_tokens);
    RUN(test_unregister_stops_dispatch);
    RUN(test_optional_fields_round_trip);
#else
    std::printf("[ SKIP ] dispatch tests (RAC_HAVE_PROTOBUF not defined at compile time)\n");
#endif

    std::printf("\n%d test(s) failed\n", failures);
    return failures == 0 ? 0 : 1;
}
