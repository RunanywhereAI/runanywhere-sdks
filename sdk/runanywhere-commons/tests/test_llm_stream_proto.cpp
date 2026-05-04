/**
 * @file test_llm_stream_proto.cpp
 * @brief Unit tests for the v2 close-out Phase G-2 LLM proto-byte stream
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

// Forward-declare the internal dispatcher (same symbol llm_component.cpp
// links against). Matches rac_llm_stream.cpp's declaration.
namespace rac::llm {
void dispatch_llm_stream_event(rac_handle_t handle,
                               const char*  token,
                               bool         is_final,
                               int          kind,
                               uint32_t     token_id,
                               float        logprob,
                               const char*  finish_reason,
                               const char*  error_message);
}
#endif

namespace {

struct CapturedCall {
    std::vector<std::vector<uint8_t>> events;
    void*  user_data  = nullptr;
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

#define ASSERT_TRUE(cond) do { \
    if (!(cond)) { \
        std::fprintf(stderr, "ASSERT FAILED: %s @ %s:%d\n", #cond, __FILE__, __LINE__); \
        return 1; \
    } \
} while (0)

#define ASSERT_EQ(a, b) do { \
    if (!((a) == (b))) { \
        std::fprintf(stderr, "ASSERT FAILED: %s == %s @ %s:%d\n", #a, #b, __FILE__, __LINE__); \
        return 1; \
    } \
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

int test_synthetic_token_schedule() {
    reset_capture();
    int sentinel = 7;
    rac_llm_set_stream_proto_callback(fake_handle(), test_callback, &sentinel);

    // Synthetic 3-token generation ending with a terminal stop event.
    rac::llm::dispatch_llm_stream_event(fake_handle(), "Hello",
                                        /*is_final*/ false, /*kind*/ 1,
                                        0, 0.0f, nullptr, nullptr);
    rac::llm::dispatch_llm_stream_event(fake_handle(), " ",
                                        /*is_final*/ false, /*kind*/ 1,
                                        0, 0.0f, nullptr, nullptr);
    rac::llm::dispatch_llm_stream_event(fake_handle(), "world",
                                        /*is_final*/ false, /*kind*/ 1,
                                        0, 0.0f, nullptr, nullptr);
    rac::llm::dispatch_llm_stream_event(fake_handle(), "",
                                        /*is_final*/ true, /*kind*/ 1,
                                        0, 0.0f, "stop", nullptr);

    ASSERT_EQ(g_capture.call_count, 4U);
    ASSERT_TRUE(g_capture.user_data == &sentinel);

    uint64_t prev_seq = 0;
    for (size_t i = 0; i < g_capture.events.size(); ++i) {
        runanywhere::v1::LLMStreamEvent decoded;
        ASSERT_TRUE(decoded.ParseFromArray(g_capture.events[i].data(),
                                           static_cast<int>(g_capture.events[i].size())));
        ASSERT_TRUE(decoded.seq() > prev_seq);
        prev_seq = decoded.seq();
        ASSERT_EQ(decoded.kind(), runanywhere::v1::LLM_TOKEN_KIND_ANSWER);
        if (i == 0) ASSERT_EQ(decoded.token(), "Hello");
        if (i == 1) ASSERT_EQ(decoded.token(), " ");
        if (i == 2) ASSERT_EQ(decoded.token(), "world");
        if (i < 3) {
            ASSERT_EQ(decoded.is_final(), false);
            ASSERT_TRUE(decoded.finish_reason().empty());
        } else {
            ASSERT_EQ(decoded.is_final(), true);
            ASSERT_EQ(decoded.finish_reason(), "stop");
            ASSERT_EQ(decoded.token(), "");
        }
    }

    rac_llm_unset_stream_proto_callback(fake_handle());
    return 0;
}

int test_error_termination() {
    reset_capture();
    rac_llm_set_stream_proto_callback(fake_handle(), test_callback, nullptr);

    rac::llm::dispatch_llm_stream_event(fake_handle(), "partial",
                                        /*is_final*/ false, /*kind*/ 1,
                                        0, 0.0f, nullptr, nullptr);
    rac::llm::dispatch_llm_stream_event(fake_handle(), "",
                                        /*is_final*/ true, /*kind*/ 0,
                                        0, 0.0f, "error",
                                        "engine backend vanished");

    ASSERT_EQ(g_capture.call_count, 2U);

    runanywhere::v1::LLMStreamEvent terminal;
    ASSERT_TRUE(terminal.ParseFromArray(
        g_capture.events.back().data(),
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

    rac::llm::dispatch_llm_stream_event(fake_handle(), "first", false, 1,
                                        0, 0.0f, nullptr, nullptr);
    ASSERT_EQ(g_capture.call_count, 1U);

    rac_llm_unset_stream_proto_callback(fake_handle());

    rac::llm::dispatch_llm_stream_event(fake_handle(), "must-not-fire", false,
                                        1, 0, 0.0f, nullptr, nullptr);
    ASSERT_EQ(g_capture.call_count, 1U);
    return 0;
}

int test_optional_fields_round_trip() {
    reset_capture();
    rac_llm_set_stream_proto_callback(fake_handle(), test_callback, nullptr);

    rac::llm::dispatch_llm_stream_event(fake_handle(), "think",
                                        /*is_final*/ false, /*kind*/ 2,
                                        /*token_id*/ 12345,
                                        /*logprob*/ -0.5f,
                                        nullptr, nullptr);

    runanywhere::v1::LLMStreamEvent decoded;
    ASSERT_TRUE(decoded.ParseFromArray(
        g_capture.events.back().data(),
        static_cast<int>(g_capture.events.back().size())));
    ASSERT_EQ(decoded.kind(), runanywhere::v1::LLM_TOKEN_KIND_THOUGHT);
    ASSERT_EQ(decoded.token_id(), 12345U);
    ASSERT_TRUE(decoded.logprob() < 0.0f);

    rac_llm_unset_stream_proto_callback(fake_handle());
    return 0;
}

#endif /* RAC_HAVE_PROTOBUF */

}  // namespace

int main() {
    int failures = 0;

#define RUN(name) do { \
    std::printf("[ RUN  ] %s\n", #name); \
    int rc = name(); \
    if (rc == 0) std::printf("[  OK  ] %s\n", #name); \
    else        { std::printf("[ FAIL ] %s\n", #name); ++failures; } \
} while (0)

    RUN(test_invalid_handle_rejected);
    RUN(test_set_callback_returns_correct_status);

#ifdef RAC_HAVE_PROTOBUF
    RUN(test_synthetic_token_schedule);
    RUN(test_error_termination);
    RUN(test_unregister_stops_dispatch);
    RUN(test_optional_fields_round_trip);
#else
    std::printf("[ SKIP ] dispatch tests (RAC_HAVE_PROTOBUF not defined at compile time)\n");
#endif

    std::printf("\n%d test(s) failed\n", failures);
    return failures == 0 ? 0 : 1;
}
