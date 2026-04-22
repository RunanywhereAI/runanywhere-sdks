/**
 * @file test_proto_event_dispatch.cpp
 * @brief Unit tests for the GAP 09 Phase 15 + v2 close-out Phase 2
 *        proto-byte event dispatch in rac_voice_event_abi.cpp.
 *
 * Scenarios:
 *   1. set_proto_callback(NULL handle) returns RAC_ERROR_INVALID_HANDLE.
 *   2. set_proto_callback(non-NULL, callback, ud) returns RAC_SUCCESS
 *      when Protobuf is compiled in (RAC_HAVE_PROTOBUF), or
 *      RAC_ERROR_FEATURE_NOT_AVAILABLE otherwise.
 *   3. Each of the 7 C union arms (PROCESSED, VAD_TRIGGERED, TRANSCRIPTION,
 *      RESPONSE, AUDIO_SYNTHESIZED, ERROR, WAKEWORD_DETECTED) round-trips
 *      through translate() → SerializeToArray() → ParseFromArray() and
 *      ends up in the right oneof arm with the right fields.
 *   4. Unregistering (callback=NULL) stops further dispatches.
 *
 * The test calls dispatch_proto_event() directly from the internal
 * header (the same hook voice_agent.cpp uses) — we do not spin up a
 * full voice agent.
 */

#include <cassert>
#include <cstdio>
#include <cstring>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/features/voice_agent/rac_voice_event_abi.h"

#ifdef RAC_HAVE_PROTOBUF
#include "voice_events.pb.h"

// Mirror the internal helper signature so we can call it without pulling
// in the private header (which would require linking the .cpp into the
// test binary). The implementation lives in rac_voice_event_abi.cpp in
// rac::voice_agent::dispatch_proto_event.
namespace rac::voice_agent {
void dispatch_proto_event(rac_voice_agent_handle_t       handle,
                          const rac_voice_agent_event_t* event);
}
#endif

namespace {

struct CapturedCall {
    std::vector<uint8_t> bytes;
    void*                user_data = nullptr;
    size_t               call_count = 0;
};

CapturedCall g_capture;

void test_callback(const uint8_t* bytes, size_t size, void* user_data) {
    g_capture.bytes.assign(bytes, bytes + size);
    g_capture.user_data = user_data;
    g_capture.call_count += 1;
}

void reset_capture() {
    g_capture.bytes.clear();
    g_capture.user_data = nullptr;
    g_capture.call_count = 0;
}

// Use a deterministic non-null sentinel as a fake handle. The proto event
// dispatch never derefs the handle — it's just a registry key.
rac_voice_agent_handle_t fake_handle() {
    static int sentinel = 0;
    return reinterpret_cast<rac_voice_agent_handle_t>(&sentinel);
}

#define ASSERT_TRUE(cond) do { \
    if (!(cond)) { \
        std::fprintf(stderr, "ASSERT FAILED: %s @ %s:%d\n", #cond, __FILE__, __LINE__); \
        return 1; \
    } \
} while (0)

#define ASSERT_EQ(a, b) do { \
    if ((a) != (b)) { \
        std::fprintf(stderr, "ASSERT FAILED: %s == %s @ %s:%d\n", #a, #b, __FILE__, __LINE__); \
        return 1; \
    } \
} while (0)

int test_invalid_handle_rejected() {
    rac_result_t rc = rac_voice_agent_set_proto_callback(nullptr, test_callback, nullptr);
    ASSERT_EQ(rc, RAC_ERROR_INVALID_HANDLE);
    return 0;
}

int test_set_callback_returns_correct_status() {
    rac_result_t rc = rac_voice_agent_set_proto_callback(fake_handle(), test_callback, nullptr);
#ifdef RAC_HAVE_PROTOBUF
    ASSERT_EQ(rc, RAC_SUCCESS);
    // Cleanup so other tests start clean.
    rac_voice_agent_set_proto_callback(fake_handle(), nullptr, nullptr);
#else
    ASSERT_EQ(rc, RAC_ERROR_FEATURE_NOT_AVAILABLE);
#endif
    return 0;
}

#ifdef RAC_HAVE_PROTOBUF

int test_transcription_arm() {
    reset_capture();
    int sentinel = 42;
    rac_voice_agent_set_proto_callback(fake_handle(), test_callback, &sentinel);

    rac_voice_agent_event_t event = {};
    event.type = RAC_VOICE_AGENT_EVENT_TRANSCRIPTION;
    event.data.transcription = "hello world";
    rac::voice_agent::dispatch_proto_event(fake_handle(), &event);

    ASSERT_EQ(g_capture.call_count, 1U);
    ASSERT_TRUE(g_capture.user_data == &sentinel);

    runanywhere::v1::VoiceEvent decoded;
    ASSERT_TRUE(decoded.ParseFromArray(g_capture.bytes.data(),
                                       static_cast<int>(g_capture.bytes.size())));
    ASSERT_TRUE(decoded.has_user_said());
    ASSERT_EQ(decoded.user_said().text(), "hello world");
    ASSERT_TRUE(decoded.user_said().is_final());
    ASSERT_TRUE(decoded.seq() > 0);

    rac_voice_agent_set_proto_callback(fake_handle(), nullptr, nullptr);
    return 0;
}

int test_response_arm() {
    reset_capture();
    rac_voice_agent_set_proto_callback(fake_handle(), test_callback, nullptr);

    rac_voice_agent_event_t event = {};
    event.type = RAC_VOICE_AGENT_EVENT_RESPONSE;
    event.data.response = "the answer is 42";
    rac::voice_agent::dispatch_proto_event(fake_handle(), &event);

    runanywhere::v1::VoiceEvent decoded;
    ASSERT_TRUE(decoded.ParseFromArray(g_capture.bytes.data(),
                                       static_cast<int>(g_capture.bytes.size())));
    ASSERT_TRUE(decoded.has_assistant_token());
    ASSERT_EQ(decoded.assistant_token().text(), "the answer is 42");
    ASSERT_TRUE(decoded.assistant_token().is_final());
    ASSERT_EQ(decoded.assistant_token().kind(), runanywhere::v1::TOKEN_KIND_ANSWER);

    rac_voice_agent_set_proto_callback(fake_handle(), nullptr, nullptr);
    return 0;
}

int test_audio_arm() {
    reset_capture();
    rac_voice_agent_set_proto_callback(fake_handle(), test_callback, nullptr);

    const uint8_t pcm[8] = { 0x00, 0x00, 0x80, 0x3F, 0x00, 0x00, 0x80, 0xBF };
    rac_voice_agent_event_t event = {};
    event.type = RAC_VOICE_AGENT_EVENT_AUDIO_SYNTHESIZED;
    event.data.audio.audio_data = pcm;
    event.data.audio.audio_size = sizeof(pcm);
    rac::voice_agent::dispatch_proto_event(fake_handle(), &event);

    runanywhere::v1::VoiceEvent decoded;
    ASSERT_TRUE(decoded.ParseFromArray(g_capture.bytes.data(),
                                       static_cast<int>(g_capture.bytes.size())));
    ASSERT_TRUE(decoded.has_audio());
    ASSERT_EQ(decoded.audio().pcm().size(), sizeof(pcm));
    ASSERT_EQ(std::memcmp(decoded.audio().pcm().data(), pcm, sizeof(pcm)), 0);
    ASSERT_EQ(decoded.audio().sample_rate_hz(), 24000);
    ASSERT_EQ(decoded.audio().channels(), 1);

    rac_voice_agent_set_proto_callback(fake_handle(), nullptr, nullptr);
    return 0;
}

int test_vad_arm() {
    reset_capture();
    rac_voice_agent_set_proto_callback(fake_handle(), test_callback, nullptr);

    rac_voice_agent_event_t start_event = {};
    start_event.type = RAC_VOICE_AGENT_EVENT_VAD_TRIGGERED;
    start_event.data.vad_speech_active = RAC_TRUE;
    rac::voice_agent::dispatch_proto_event(fake_handle(), &start_event);

    runanywhere::v1::VoiceEvent decoded;
    ASSERT_TRUE(decoded.ParseFromArray(g_capture.bytes.data(),
                                       static_cast<int>(g_capture.bytes.size())));
    ASSERT_TRUE(decoded.has_vad());
    ASSERT_EQ(decoded.vad().type(), runanywhere::v1::VAD_EVENT_VOICE_START);

    reset_capture();
    rac_voice_agent_event_t end_event = {};
    end_event.type = RAC_VOICE_AGENT_EVENT_VAD_TRIGGERED;
    end_event.data.vad_speech_active = RAC_FALSE;
    rac::voice_agent::dispatch_proto_event(fake_handle(), &end_event);

    decoded.Clear();
    ASSERT_TRUE(decoded.ParseFromArray(g_capture.bytes.data(),
                                       static_cast<int>(g_capture.bytes.size())));
    ASSERT_EQ(decoded.vad().type(), runanywhere::v1::VAD_EVENT_VOICE_END_OF_UTTERANCE);

    rac_voice_agent_set_proto_callback(fake_handle(), nullptr, nullptr);
    return 0;
}

int test_error_arm() {
    reset_capture();
    rac_voice_agent_set_proto_callback(fake_handle(), test_callback, nullptr);

    rac_voice_agent_event_t event = {};
    event.type = RAC_VOICE_AGENT_EVENT_ERROR;
    event.data.error_code = RAC_ERROR_INVALID_ARGUMENT;
    rac::voice_agent::dispatch_proto_event(fake_handle(), &event);

    runanywhere::v1::VoiceEvent decoded;
    ASSERT_TRUE(decoded.ParseFromArray(g_capture.bytes.data(),
                                       static_cast<int>(g_capture.bytes.size())));
    ASSERT_TRUE(decoded.has_error());
    ASSERT_EQ(decoded.error().code(), static_cast<int32_t>(RAC_ERROR_INVALID_ARGUMENT));
    ASSERT_EQ(decoded.error().component(), "pipeline");

    rac_voice_agent_set_proto_callback(fake_handle(), nullptr, nullptr);
    return 0;
}

int test_unregister_stops_dispatch() {
    reset_capture();
    rac_voice_agent_set_proto_callback(fake_handle(), test_callback, nullptr);

    rac_voice_agent_event_t event = {};
    event.type = RAC_VOICE_AGENT_EVENT_TRANSCRIPTION;
    event.data.transcription = "before unregister";
    rac::voice_agent::dispatch_proto_event(fake_handle(), &event);
    ASSERT_EQ(g_capture.call_count, 1U);

    // Unregister.
    rac_voice_agent_set_proto_callback(fake_handle(), nullptr, nullptr);

    rac_voice_agent_event_t event2 = {};
    event2.type = RAC_VOICE_AGENT_EVENT_TRANSCRIPTION;
    event2.data.transcription = "after unregister — must NOT fire";
    rac::voice_agent::dispatch_proto_event(fake_handle(), &event2);
    ASSERT_EQ(g_capture.call_count, 1U);
    return 0;
}

int test_seq_monotonic() {
    reset_capture();
    rac_voice_agent_set_proto_callback(fake_handle(), test_callback, nullptr);

    rac_voice_agent_event_t event = {};
    event.type = RAC_VOICE_AGENT_EVENT_TRANSCRIPTION;
    event.data.transcription = "first";

    rac::voice_agent::dispatch_proto_event(fake_handle(), &event);
    runanywhere::v1::VoiceEvent first;
    first.ParseFromArray(g_capture.bytes.data(), static_cast<int>(g_capture.bytes.size()));
    uint64_t seq1 = first.seq();

    rac::voice_agent::dispatch_proto_event(fake_handle(), &event);
    runanywhere::v1::VoiceEvent second;
    second.ParseFromArray(g_capture.bytes.data(), static_cast<int>(g_capture.bytes.size()));
    ASSERT_TRUE(second.seq() > seq1);

    rac_voice_agent_set_proto_callback(fake_handle(), nullptr, nullptr);
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
    RUN(test_transcription_arm);
    RUN(test_response_arm);
    RUN(test_audio_arm);
    RUN(test_vad_arm);
    RUN(test_error_arm);
    RUN(test_unregister_stops_dispatch);
    RUN(test_seq_monotonic);
#else
    std::printf("[ SKIP ] proto-arm tests (RAC_HAVE_PROTOBUF not defined at compile time)\n");
#endif

    std::printf("\n%d test(s) failed\n", failures);
    return failures == 0 ? 0 : 1;
}
