/**
 * @file parity_test.cpp
 * @brief Golden producer for the GAP 09 / v2 close-out cross-SDK parity test.
 *
 * Phase 4 of v2 close-out. Generates a deterministic event sequence by
 * registering a proto-byte callback on a fake voice agent handle and
 * dispatching a fixed script of events. The output golden file is what
 * the per-language parity_test.{swift,kt,dart,ts} compares its captured
 * stream against.
 *
 * Usage:
 *     parity_test_cpp                   # write golden_events.txt
 *     parity_test_cpp --check           # read fixtures/golden_events.txt
 *                                       and verify the C++ output matches
 *
 * The synthetic input avoids the need for a recorded WAV file (deferred
 * to v3 per docs/v2_remaining_work.md). The deterministic schedule covers
 * every C union arm the proto-byte ABI translates, in a realistic order.
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
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

struct CapturedLine {
    std::string text;
};

std::vector<CapturedLine> g_captured;

/* Format one VoiceEvent as a single deterministic line. The line schema is
 * the wire contract the per-language tests compare against.
 *   "<arm>:<key1>=<value1>,<key2>=<value2>"
 * `seq` and `timestamp_us` are intentionally NOT in the line because they
 * are non-deterministic across runs. */
std::string format_event(const runanywhere::v1::VoiceEvent& e) {
    std::ostringstream os;
    if (e.has_user_said()) {
        os << "user_said:text=" << e.user_said().text()
           << ",is_final=" << (e.user_said().is_final() ? "true" : "false");
    } else if (e.has_assistant_token()) {
        os << "assistant_token:text=" << e.assistant_token().text()
           << ",is_final=" << (e.assistant_token().is_final() ? "true" : "false")
           << ",kind=" << static_cast<int>(e.assistant_token().kind());
    } else if (e.has_audio()) {
        os << "audio:bytes=" << e.audio().pcm().size()
           << ",sample_rate=" << e.audio().sample_rate_hz()
           << ",channels=" << e.audio().channels()
           << ",encoding=" << static_cast<int>(e.audio().encoding());
    } else if (e.has_vad()) {
        os << "vad:type=" << static_cast<int>(e.vad().type());
    } else if (e.has_state()) {
        os << "state:previous=" << static_cast<int>(e.state().previous())
           << ",current=" << static_cast<int>(e.state().current());
    } else if (e.has_error()) {
        os << "error:code=" << e.error().code()
           << ",component=" << e.error().component();
    } else if (e.has_metrics()) {
        os << "metrics:tokens_generated=" << e.metrics().tokens_generated()
           << ",is_over_budget=" << (e.metrics().is_over_budget() ? "true" : "false");
    } else if (e.has_interrupted()) {
        os << "interrupted:reason=" << static_cast<int>(e.interrupted().reason());
    } else {
        os << "unknown_arm";
    }
    return os.str();
}

void capture_callback(const uint8_t* bytes, size_t size, void* /*user_data*/) {
    runanywhere::v1::VoiceEvent ev;
    if (!ev.ParseFromArray(bytes, static_cast<int>(size))) {
        g_captured.push_back({"PARSE_ERROR"});
        return;
    }
    g_captured.push_back({format_event(ev)});
}

rac_voice_agent_handle_t fake_handle() {
    static int sentinel = 0;
    return reinterpret_cast<rac_voice_agent_handle_t>(&sentinel);
}

/* The fixed event script. Same order, same data, on every run.
 *
 * Mirrors a typical voice-agent turn:
 *   1. user starts speaking          → vad VOICE_START
 *   2. user stops speaking           → vad VOICE_END_OF_UTTERANCE
 *   3. STT finalizes                 → user_said
 *   4. LLM responds                  → assistant_token (final)
 *   5. TTS emits audio               → audio
 *   6. pipeline reports              → metrics
 *   7. terminal error                → error
 *   8. wake word fires               → state IDLE→LISTENING
 */
void emit_golden_sequence() {
    /* 1 */ {
        rac_voice_agent_event_t e = {};
        e.type = RAC_VOICE_AGENT_EVENT_VAD_TRIGGERED;
        e.data.vad_speech_active = RAC_TRUE;
        rac::voice_agent::dispatch_proto_event(fake_handle(), &e);
    }
    /* 2 */ {
        rac_voice_agent_event_t e = {};
        e.type = RAC_VOICE_AGENT_EVENT_VAD_TRIGGERED;
        e.data.vad_speech_active = RAC_FALSE;
        rac::voice_agent::dispatch_proto_event(fake_handle(), &e);
    }
    /* 3 */ {
        rac_voice_agent_event_t e = {};
        e.type = RAC_VOICE_AGENT_EVENT_TRANSCRIPTION;
        e.data.transcription = "what is the weather today";
        rac::voice_agent::dispatch_proto_event(fake_handle(), &e);
    }
    /* 4 */ {
        rac_voice_agent_event_t e = {};
        e.type = RAC_VOICE_AGENT_EVENT_RESPONSE;
        e.data.response = "the weather is sunny and 72 degrees";
        rac::voice_agent::dispatch_proto_event(fake_handle(), &e);
    }
    /* 5 */ {
        static const uint8_t pcm[16] = {
            0x00, 0x00, 0x80, 0x3F, 0x00, 0x00, 0x80, 0xBF,
            0x00, 0x00, 0x40, 0x40, 0x00, 0x00, 0xC0, 0xC0,
        };
        rac_voice_agent_event_t e = {};
        e.type = RAC_VOICE_AGENT_EVENT_AUDIO_SYNTHESIZED;
        e.data.audio.audio_data = pcm;
        e.data.audio.audio_size = sizeof(pcm);
        rac::voice_agent::dispatch_proto_event(fake_handle(), &e);
    }
    /* 6 */ {
        rac_voice_agent_event_t e = {};
        e.type = RAC_VOICE_AGENT_EVENT_PROCESSED;
        rac::voice_agent::dispatch_proto_event(fake_handle(), &e);
    }
    /* 7 */ {
        rac_voice_agent_event_t e = {};
        e.type = RAC_VOICE_AGENT_EVENT_ERROR;
        e.data.error_code = RAC_ERROR_INVALID_ARGUMENT;
        rac::voice_agent::dispatch_proto_event(fake_handle(), &e);
    }
    /* 8 */ {
        rac_voice_agent_event_t e = {};
        e.type = RAC_VOICE_AGENT_EVENT_WAKEWORD_DETECTED;
        rac::voice_agent::dispatch_proto_event(fake_handle(), &e);
    }
}

int run_produce(const std::string& out_path) {
    g_captured.clear();
    rac_result_t rc = rac_voice_agent_set_proto_callback(fake_handle(),
                                                          capture_callback, nullptr);
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "set_proto_callback failed: %d\n", static_cast<int>(rc));
        return 1;
    }

    emit_golden_sequence();
    rac_voice_agent_set_proto_callback(fake_handle(), nullptr, nullptr);

    std::ofstream out(out_path);
    if (!out) {
        std::fprintf(stderr, "cannot open %s for write\n", out_path.c_str());
        return 1;
    }
    out << "# GAP 09 / v2 close-out parity test golden output\n";
    out << "# Generated by tests/streaming/parity_test_cpp\n";
    out << "# Schema: <oneof_arm>:<key>=<value>,...\n";
    out << "# Lines below are the literal proto VoiceEvent.payload arms emitted\n";
    out << "# in order. seq + timestamp_us excluded — non-deterministic.\n";
    for (const auto& line : g_captured) out << line.text << "\n";
    std::printf("Wrote %zu events to %s\n", g_captured.size(), out_path.c_str());
    return 0;
}

int run_check(const std::string& golden_path) {
    g_captured.clear();
    rac_voice_agent_set_proto_callback(fake_handle(), capture_callback, nullptr);
    emit_golden_sequence();
    rac_voice_agent_set_proto_callback(fake_handle(), nullptr, nullptr);

    std::ifstream in(golden_path);
    if (!in) {
        std::fprintf(stderr, "cannot open %s for read\n", golden_path.c_str());
        return 1;
    }
    std::vector<std::string> expected;
    std::string line;
    while (std::getline(in, line)) {
        if (line.empty() || line[0] == '#') continue;
        expected.push_back(line);
    }

    if (expected.size() != g_captured.size()) {
        std::fprintf(stderr, "FAIL: expected %zu events, got %zu\n",
                     expected.size(), g_captured.size());
        return 1;
    }
    for (size_t i = 0; i < expected.size(); ++i) {
        if (expected[i] != g_captured[i].text) {
            std::fprintf(stderr,
                         "FAIL @ event %zu:\n  expected: %s\n  got:      %s\n",
                         i, expected[i].c_str(), g_captured[i].text.c_str());
            return 1;
        }
    }
    std::printf("PASS: %zu events match golden\n", expected.size());
    return 0;
}

}  // namespace

int main(int argc, char** argv) {
    bool check = false;
    std::string path = "tests/streaming/fixtures/golden_events.txt";
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--check") check = true;
        else if (arg.rfind("--path=", 0) == 0) path = arg.substr(7);
        else if (arg[0] != '-') path = arg;
    }
    return check ? run_check(path) : run_produce(path);
}

#else /* RAC_HAVE_PROTOBUF not defined */

int main() {
    std::fprintf(stderr,
                 "parity_test_cpp: skipped (RAC_HAVE_PROTOBUF not defined "
                 "at compile time — build with Protobuf installed).\n");
    return 0;
}

#endif
