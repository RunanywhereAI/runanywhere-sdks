/**
 * @file cancel_producer.cpp
 * @brief GAP 09 #7 cancel-parity harness — producer side.
 *
 * v3.1 Phase 5.1. Emits 1,000 VoiceEvents + injects a synthetic
 * "cancel requested" marker at event index 500 by setting an
 * InterruptedEvent in the proto payload. Consumers in each SDK
 * subscribe, count events seen up to the cancel marker, invoke
 * their cancel path, and verify the stop is observed within 50 ms.
 *
 * Output format (identical to perf_producer):
 *   uint32_t magic = 0x43504152 ('CPAR' — cancel parity)
 *   uint32_t count
 *   count × { uint32_t len; uint8_t[len] proto_bytes }
 *
 * The cancel marker is encoded as VoiceEvent.interrupted with
 * reason=REASON_CANCELLED at index 500 (0-indexed). Every other
 * event rotates through 5 non-terminal arms (userSaid, assistantToken,
 * audio, vad, state) so consumers exercise the full decode path.
 *
 * Usage:
 *   cancel_producer                  # /tmp/cancel_input.bin
 *   cancel_producer --out <path>
 *   cancel_producer --count <N>      # default 1000
 *   cancel_producer --cancel-at <I>  # default 500
 */

#include <chrono>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/features/voice_agent/rac_voice_event_abi.h"

#ifdef RAC_HAVE_PROTOBUF
#include "voice_events.pb.h"

namespace rac::voice_agent {
void dispatch_proto_event(rac_voice_agent_handle_t       handle,
                          const rac_voice_agent_event_t* event);
}

namespace {

constexpr uint32_t kMagic = 0x43504152u;  // 'CPAR'
constexpr int kDefaultCount = 1000;
constexpr int kDefaultCancelAt = 500;

struct CapturedFrame {
    std::vector<uint8_t> bytes;
};
std::vector<CapturedFrame> g_captured;

void capture_callback(const uint8_t* bytes, size_t size, void*) {
    g_captured.push_back({std::vector<uint8_t>(bytes, bytes + size)});
}

rac_voice_agent_handle_t fake_handle() {
    static int sentinel = 0;
    return reinterpret_cast<rac_voice_agent_handle_t>(&sentinel);
}

int64_t now_ns() {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

void emit_regular(int idx) {
    rac_voice_agent_event_t e = {};
    switch (idx % 5) {
    case 0:
        e.type = RAC_VOICE_AGENT_EVENT_TRANSCRIPTION;
        e.data.transcription = "cancel-parity transcription";
        break;
    case 1:
        e.type = RAC_VOICE_AGENT_EVENT_RESPONSE;
        e.data.response = "cancel-parity response token";
        break;
    case 2:
        e.type = RAC_VOICE_AGENT_EVENT_VAD_TRIGGERED;
        e.data.vad_speech_active = RAC_TRUE;
        break;
    case 3:
        e.type = RAC_VOICE_AGENT_EVENT_PROCESSED;
        break;
    case 4: {
        static const uint8_t pcm[16] = {
            0x00, 0x00, 0x80, 0x3F, 0x00, 0x00, 0x80, 0xBF,
            0x00, 0x00, 0x40, 0x40, 0x00, 0x00, 0xC0, 0xC0,
        };
        e.type = RAC_VOICE_AGENT_EVENT_AUDIO_SYNTHESIZED;
        e.data.audio.audio_data = pcm;
        e.data.audio.audio_size = sizeof(pcm);
        break;
    }
    }
    rac::voice_agent::dispatch_proto_event(fake_handle(), &e);
}

/** Emit a VoiceEvent with InterruptedEvent payload = REASON_CANCELLED.
 *  The dispatcher API doesn't have a direct interrupted event type, so we
 *  post-process the captured frames instead (stamp_cancel_marker below). */
void emit_cancel_placeholder() {
    // Placeholder event so the frame count matches count. Replaced in
    // stamp_cancel_marker with a real InterruptedEvent proto.
    emit_regular(3);  // PROCESSED arm; will be overwritten.
}

void stamp_cancel_marker(int cancel_idx, int64_t base_ns) {
    for (size_t i = 0; i < g_captured.size(); ++i) {
        runanywhere::v1::VoiceEvent ev;
        if (!ev.ParseFromArray(g_captured[i].bytes.data(),
                               static_cast<int>(g_captured[i].bytes.size()))) {
            continue;
        }
        // Inject produce-time timestamp for latency measurement.
        ev.mutable_metrics()->set_created_at_ns(base_ns + static_cast<int64_t>(i) * 1000);

        if (static_cast<int>(i) == cancel_idx) {
            // Replace payload with InterruptedEvent (reason = APP_STOP).
            ev.clear_payload();
            auto* interrupted = ev.mutable_interrupted();
            interrupted->set_reason(runanywhere::v1::INTERRUPT_REASON_APP_STOP);
        }

        std::string serialized;
        if (ev.SerializeToString(&serialized)) {
            g_captured[i].bytes.assign(serialized.begin(), serialized.end());
        }
    }
}

int write_binary(const std::string& path) {
    std::ofstream out(path, std::ios::binary);
    if (!out) {
        std::fprintf(stderr, "cancel_producer: cannot open %s for write\n", path.c_str());
        return 1;
    }
    const uint32_t count = static_cast<uint32_t>(g_captured.size());
    out.write(reinterpret_cast<const char*>(&kMagic), sizeof(kMagic));
    out.write(reinterpret_cast<const char*>(&count), sizeof(count));
    for (const auto& frame : g_captured) {
        const uint32_t len = static_cast<uint32_t>(frame.bytes.size());
        out.write(reinterpret_cast<const char*>(&len), sizeof(len));
        out.write(reinterpret_cast<const char*>(frame.bytes.data()), len);
    }
    out.close();
    std::printf("cancel_producer: wrote %u events to %s (cancel at index varies)\n",
                count, path.c_str());
    return 0;
}

}  // namespace

int main(int argc, char** argv) {
    std::string out_path = "/tmp/cancel_input.bin";
    int count = kDefaultCount;
    int cancel_at = kDefaultCancelAt;
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--out" && i + 1 < argc) out_path = argv[++i];
        else if (arg == "--count" && i + 1 < argc) count = std::atoi(argv[++i]);
        else if (arg == "--cancel-at" && i + 1 < argc) cancel_at = std::atoi(argv[++i]);
        else if (arg == "--help" || arg == "-h") {
            std::printf("Usage: %s [--out path] [--count N] [--cancel-at I]\n", argv[0]);
            return 0;
        }
    }

    if (cancel_at < 0 || cancel_at >= count) {
        std::fprintf(stderr, "cancel_producer: --cancel-at %d out of range [0, %d)\n",
                     cancel_at, count);
        return 1;
    }

    rac_voice_agent_set_proto_callback(fake_handle(), capture_callback, nullptr);

    const int64_t t0 = now_ns();
    for (int i = 0; i < count; ++i) {
        if (i == cancel_at) emit_cancel_placeholder();
        else emit_regular(i);
    }
    const int64_t t1 = now_ns();

    rac_voice_agent_set_proto_callback(fake_handle(), nullptr, nullptr);

    stamp_cancel_marker(cancel_at, t0);

    std::printf("cancel_producer: dispatched %d events in %lld ns, cancel marker at idx %d\n",
                count, static_cast<long long>(t1 - t0), cancel_at);

    return write_binary(out_path);
}

#else
int main() {
    std::fprintf(stderr, "cancel_producer: RAC_HAVE_PROTOBUF not defined; cannot run\n");
    return 1;
}
#endif
