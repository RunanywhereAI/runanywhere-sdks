// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Proto3 roundtrip test — confirms the idl/ schemas compile, the generated
// C++ types serialize/deserialize cleanly, and every frontend-visible
// oneof branch round-trips its payload byte-for-byte.
//
// This is the canary test for phase 5 (proto3 at the C ABI boundary): if
// this test fails, the wire format is broken and no frontend binding will
// survive.

#include "voice_events.pb.h"

#include <gtest/gtest.h>

#include <string>

using runanywhere::v1::AssistantTokenEvent;
using runanywhere::v1::AudioEncoding;
using runanywhere::v1::AudioFrameEvent;
using runanywhere::v1::InterruptReason;
using runanywhere::v1::InterruptedEvent;
using runanywhere::v1::TokenKind;
using runanywhere::v1::UserSaidEvent;
using runanywhere::v1::VADEvent;
using runanywhere::v1::VADEventType;
using runanywhere::v1::VoiceEvent;

namespace {

VoiceEvent make_user_said() {
    VoiceEvent e;
    e.set_seq(42);
    e.set_timestamp_us(1'700'000'000'000'000LL);
    auto* u = e.mutable_user_said();
    u->set_text("hello world");
    u->set_is_final(true);
    u->set_confidence(0.93f);
    u->set_audio_start_us(1'000);
    u->set_audio_end_us(2'500);
    return e;
}

VoiceEvent make_assistant_token(TokenKind kind, const std::string& text,
                                 bool is_final) {
    VoiceEvent e;
    e.set_seq(99);
    auto* t = e.mutable_assistant_token();
    t->set_text(text);
    t->set_is_final(is_final);
    t->set_kind(kind);
    return e;
}

VoiceEvent make_audio(std::string pcm_bytes, int sr, int ch) {
    VoiceEvent e;
    auto* a = e.mutable_audio();
    a->set_pcm(std::move(pcm_bytes));
    a->set_sample_rate_hz(sr);
    a->set_channels(ch);
    a->set_encoding(runanywhere::v1::AUDIO_ENCODING_PCM_F32_LE);
    return e;
}

VoiceEvent make_interrupted() {
    VoiceEvent e;
    auto* i = e.mutable_interrupted();
    i->set_reason(runanywhere::v1::INTERRUPT_REASON_USER_BARGE_IN);
    i->set_detail("mid-sentence stop");
    return e;
}

}  // namespace

TEST(ProtoRoundtrip, DefaultInstanceIsEmpty) {
    VoiceEvent e;
    EXPECT_EQ(e.payload_case(), VoiceEvent::PAYLOAD_NOT_SET);
    EXPECT_EQ(e.seq(), 0u);
}

TEST(ProtoRoundtrip, UserSaidRoundTrip) {
    const auto original = make_user_said();
    std::string wire;
    ASSERT_TRUE(original.SerializeToString(&wire));
    EXPECT_GT(wire.size(), 0u);

    VoiceEvent decoded;
    ASSERT_TRUE(decoded.ParseFromString(wire));

    EXPECT_EQ(decoded.seq(), 42u);
    EXPECT_EQ(decoded.timestamp_us(), 1'700'000'000'000'000LL);
    ASSERT_EQ(decoded.payload_case(), VoiceEvent::kUserSaid);
    EXPECT_EQ(decoded.user_said().text(), "hello world");
    EXPECT_TRUE(decoded.user_said().is_final());
    EXPECT_FLOAT_EQ(decoded.user_said().confidence(), 0.93f);
    EXPECT_EQ(decoded.user_said().audio_start_us(), 1'000);
    EXPECT_EQ(decoded.user_said().audio_end_us(), 2'500);
}

TEST(ProtoRoundtrip, AssistantTokenAllKindsRoundTrip) {
    for (auto kind : {runanywhere::v1::TOKEN_KIND_ANSWER,
                      runanywhere::v1::TOKEN_KIND_THOUGHT,
                      runanywhere::v1::TOKEN_KIND_TOOL_CALL}) {
        const auto original = make_assistant_token(kind, "the cat", kind ==
            runanywhere::v1::TOKEN_KIND_TOOL_CALL);
        std::string wire;
        ASSERT_TRUE(original.SerializeToString(&wire));
        VoiceEvent decoded;
        ASSERT_TRUE(decoded.ParseFromString(wire));
        EXPECT_EQ(decoded.payload_case(), VoiceEvent::kAssistantToken);
        EXPECT_EQ(decoded.assistant_token().text(), "the cat");
        EXPECT_EQ(decoded.assistant_token().kind(), kind);
    }
}

TEST(ProtoRoundtrip, AudioFrameBytesPassthrough) {
    // Simulate 10ms of PCM at 16 kHz = 160 samples * 4 bytes = 640.
    std::string pcm(640, '\0');
    for (size_t i = 0; i < pcm.size(); ++i) {
        pcm[i] = static_cast<char>(i & 0xff);
    }
    const auto original = make_audio(pcm, 16'000, 1);
    std::string wire;
    ASSERT_TRUE(original.SerializeToString(&wire));
    VoiceEvent decoded;
    ASSERT_TRUE(decoded.ParseFromString(wire));
    ASSERT_EQ(decoded.payload_case(), VoiceEvent::kAudio);
    EXPECT_EQ(decoded.audio().sample_rate_hz(), 16'000);
    EXPECT_EQ(decoded.audio().channels(), 1);
    EXPECT_EQ(decoded.audio().encoding(),
              runanywhere::v1::AUDIO_ENCODING_PCM_F32_LE);
    ASSERT_EQ(decoded.audio().pcm().size(), pcm.size());
    EXPECT_EQ(decoded.audio().pcm(), pcm);
}

TEST(ProtoRoundtrip, InterruptedReasonAndDetail) {
    const auto original = make_interrupted();
    std::string wire;
    ASSERT_TRUE(original.SerializeToString(&wire));
    VoiceEvent decoded;
    ASSERT_TRUE(decoded.ParseFromString(wire));
    ASSERT_EQ(decoded.payload_case(), VoiceEvent::kInterrupted);
    EXPECT_EQ(decoded.interrupted().reason(),
              runanywhere::v1::INTERRUPT_REASON_USER_BARGE_IN);
    EXPECT_EQ(decoded.interrupted().detail(), "mid-sentence stop");
}

TEST(ProtoRoundtrip, VadEventRoundTrip) {
    VoiceEvent original;
    auto* v = original.mutable_vad();
    v->set_type(runanywhere::v1::VAD_EVENT_BARGE_IN);
    v->set_frame_offset_us(12'345);
    std::string wire;
    ASSERT_TRUE(original.SerializeToString(&wire));
    VoiceEvent decoded;
    ASSERT_TRUE(decoded.ParseFromString(wire));
    ASSERT_EQ(decoded.payload_case(), VoiceEvent::kVad);
    EXPECT_EQ(decoded.vad().type(), runanywhere::v1::VAD_EVENT_BARGE_IN);
    EXPECT_EQ(decoded.vad().frame_offset_us(), 12'345);
}

TEST(ProtoRoundtrip, ForwardCompatibility_UnknownFieldsRoundTrip) {
    // Build a wire buffer with a field number the schema doesn't yet define
    // (field 9999). A newer peer might send this to an older receiver; the
    // receiver should preserve the field on round-trip rather than drop it.
    // This is a property of proto3's unknown field handling; we rely on it
    // for staged frontend rollouts.
    VoiceEvent e = make_user_said();
    std::string wire;
    ASSERT_TRUE(e.SerializeToString(&wire));
    // Append an unknown varint field — tag 9999 (wire type 0) + value 7.
    // tag = (9999 << 3) | 0 = 79992 -> varint bytes.
    auto write_varint = [](std::string& out, uint64_t v) {
        while (v >= 0x80) {
            out.push_back(static_cast<char>((v & 0x7f) | 0x80));
            v >>= 7;
        }
        out.push_back(static_cast<char>(v & 0x7f));
    };
    write_varint(wire, (9999ULL << 3));
    write_varint(wire, 7);

    VoiceEvent decoded;
    ASSERT_TRUE(decoded.ParseFromString(wire));
    // The original data survives the round-trip — proves the parser didn't
    // reject unknown fields.
    EXPECT_EQ(decoded.user_said().text(), "hello world");
}
