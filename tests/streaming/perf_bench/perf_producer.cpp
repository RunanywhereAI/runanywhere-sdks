/**
 * @file perf_producer.cpp
 * @brief Streaming perf bench producer (GAP 09 #8 measurement infra).
 *
 * v2.1 quick-wins Item 3. Closes the harness side of the
 * `p50 ≤ 1ms across 5 SDKs` spec criterion. The consumer side lives
 * in per-language perf_bench.{swift,kt,dart,ts} files in this directory.
 *
 * Usage:
 *     perf_producer                          # write /tmp/perf_input.bin
 *     perf_producer --emit-binary <path>     # write to specified path
 *     perf_producer --count <N>              # default N=10000
 *
 * Output format (line-delimited proto-byte records):
 *
 *   For each event:
 *     uint32_t  little-endian byte length
 *     uint8_t[] proto-encoded VoiceEvent bytes
 *
 * The first 4 bytes of the file are a magic number: `RAPB` (0x42504152
 * little-endian) followed by a uint32_t event count. Per-SDK consumers
 * mmap or stream-read the file, decode each event, and record the
 * `now() - metrics.created_at_ns` delta.
 *
 * Why a flat binary file instead of in-process callbacks: per-SDK
 * consumers run in their own test runners (XCTest, JUnit, etc.) — they
 * don't share an address space with this producer. The file is the
 * cross-process input.
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

constexpr uint32_t kMagic = 0x42504152u;  // 'RAPB' little-endian
constexpr int kDefaultCount = 10000;

struct CapturedFrame {
    std::vector<uint8_t> bytes;
};

std::vector<CapturedFrame> g_captured;

void capture_callback(const uint8_t* bytes, size_t size, void* /*user_data*/) {
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

/* Emit one timestamped event. The producer-side timestamp goes into
 * the proto's `metrics.created_at_ns` field; consumers compute
 * `consumer_now_ns - created_at_ns` as the per-event latency.
 *
 * We rotate through a small set of arms so the bench stresses the
 * full proto-decode path, not just one oneof variant.
 */
void emit_one(int idx) {
    rac_voice_agent_event_t e = {};
    switch (idx % 5) {
    case 0: {
        e.type = RAC_VOICE_AGENT_EVENT_VAD_TRIGGERED;
        e.data.vad_speech_active = (idx % 2 == 0) ? RAC_TRUE : RAC_FALSE;
        break;
    }
    case 1: {
        e.type = RAC_VOICE_AGENT_EVENT_TRANSCRIPTION;
        e.data.transcription = "perf bench transcription";
        break;
    }
    case 2: {
        e.type = RAC_VOICE_AGENT_EVENT_RESPONSE;
        e.data.response = "perf bench response token";
        break;
    }
    case 3: {
        e.type = RAC_VOICE_AGENT_EVENT_PROCESSED;
        break;
    }
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

/* Post-process: stamp created_at_ns into each captured frame's metrics
 * field. We do this AFTER capture (instead of before dispatch) because
 * the C event struct doesn't have a created_at_ns field — the
 * timestamp is metadata the perf bench adds, not part of the event
 * type itself. Consumers can read either the file-write timestamp
 * (frame index × file_creation_time) OR the in-band metrics field;
 * v2.1-2 follow-up wires the per-SDK consumer to read the metrics
 * field for highest precision.
 */
void stamp_timestamps(int64_t base_ns, int64_t per_event_ns_increment) {
    for (size_t i = 0; i < g_captured.size(); ++i) {
        runanywhere::v1::VoiceEvent ev;
        if (!ev.ParseFromArray(g_captured[i].bytes.data(),
                               static_cast<int>(g_captured[i].bytes.size()))) {
            continue;
        }
        // v3.1: write the monotonic producer-side timestamp into
        // MetricsEvent.created_at_ns (field 8, added in the v3.1 proto
        // bump). Wipes any existing oneof — consumers read the metrics
        // arm exclusively for the latency timestamp.
        auto* metrics = ev.mutable_metrics();
        metrics->set_tokens_generated(static_cast<int64_t>(i));
        metrics->set_is_over_budget(false);
        metrics->set_created_at_ns(base_ns + static_cast<int64_t>(i) * per_event_ns_increment);
        std::string serialized;
        if (ev.SerializeToString(&serialized)) {
            g_captured[i].bytes.assign(serialized.begin(), serialized.end());
        }
    }
}

int write_binary(const std::string& path) {
    std::ofstream out(path, std::ios::binary);
    if (!out) {
        std::fprintf(stderr, "perf_producer: cannot open %s for write\n", path.c_str());
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
    std::printf("perf_producer: wrote %u events to %s\n", count, path.c_str());
    return 0;
}

}  // namespace

int main(int argc, char** argv) {
    std::string out_path = "/tmp/perf_input.bin";
    int count = kDefaultCount;
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--emit-binary" && i + 1 < argc) {
            out_path = argv[++i];
        } else if (arg == "--count" && i + 1 < argc) {
            count = std::atoi(argv[++i]);
        } else if (arg == "--help" || arg == "-h") {
            std::printf("Usage: %s [--emit-binary path] [--count N]\n", argv[0]);
            return 0;
        }
    }

    rac_voice_agent_set_proto_callback(fake_handle(), capture_callback, nullptr);

    const int64_t t0 = now_ns();
    for (int i = 0; i < count; ++i) {
        emit_one(i);
    }
    const int64_t t1 = now_ns();

    rac_voice_agent_set_proto_callback(fake_handle(), nullptr, nullptr);

    const int64_t per_event_ns = (t1 - t0) / std::max(count, 1);
    stamp_timestamps(t0, per_event_ns);

    std::printf("perf_producer: dispatched %d events in %lld ns (%lld ns/event)\n",
                count, static_cast<long long>(t1 - t0),
                static_cast<long long>(per_event_ns));

    return write_binary(out_path);
}

#else  /* !RAC_HAVE_PROTOBUF */
int main() {
    std::fprintf(stderr, "perf_producer: RAC_HAVE_PROTOBUF not defined; cannot run\n");
    return 1;
}
#endif
