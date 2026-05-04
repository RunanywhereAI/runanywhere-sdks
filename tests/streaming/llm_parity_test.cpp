/**
 * @file llm_parity_test.cpp
 * @brief Golden producer for the v2 close-out Phase G-2 LLM streaming
 *        parity test.
 *
 * Mirrors `parity_test.cpp` (voice agent). Generates a deterministic
 * LLMStreamEvent sequence by registering a proto-byte stream callback
 * on a fake LLM handle and dispatching a fixed token schedule. The
 * output golden file is what the per-language llm_parity tests compare
 * against.
 *
 * Usage:
 *     llm_parity_test_cpp                   # write llm_golden_events.txt
 *     llm_parity_test_cpp --check           # read fixtures/llm_golden_events.txt
 *                                           and verify the C++ output matches
 */

#include <cstdio>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_stream.h"

#ifdef RAC_HAVE_PROTOBUF
#include "llm_service.pb.h"

// Mirror the internal dispatcher signature (same symbol llm_component.cpp
// links against). Defined in rac_llm_stream.cpp.
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

namespace {

struct CapturedLine {
    std::string text;
};

std::vector<CapturedLine> g_captured;

/* Format one LLMStreamEvent as a single deterministic line.
 * Schema: "<token>|<is_final>|<kind>|<token_id>|<finish_reason>|<error_message>"
 * `seq` and `timestamp_us` are intentionally NOT in the line because they
 * are non-deterministic across runs. `logprob` is also excluded because
 * proto3 float serialization round-trip has platform-dependent precision
 * in text representations. */
std::string format_event(const runanywhere::v1::LLMStreamEvent& e) {
    std::ostringstream os;
    os << "token=" << e.token()
       << "|is_final=" << (e.is_final() ? "true" : "false")
       << "|kind="     << static_cast<int>(e.kind())
       << "|token_id=" << e.token_id()
       << "|finish_reason=" << e.finish_reason()
       << "|error_message=" << e.error_message();
    return os.str();
}

void capture_callback(const uint8_t* bytes, size_t size, void* /*user_data*/) {
    runanywhere::v1::LLMStreamEvent ev;
    if (!ev.ParseFromArray(bytes, static_cast<int>(size))) {
        g_captured.push_back({"PARSE_ERROR"});
        return;
    }
    g_captured.push_back({format_event(ev)});
}

rac_handle_t fake_handle() {
    static int sentinel = 0;
    return reinterpret_cast<rac_handle_t>(&sentinel);
}

/* The fixed token schedule. Same order, same data, on every run.
 *
 * Mirrors a typical LLM generation turn:
 *   1. "The"                 → non-final ANSWER
 *   2. " weather"            → non-final ANSWER
 *   3. " is"                 → non-final ANSWER
 *   4. " sunny."             → non-final ANSWER
 *   5. (thought token)       → non-final THOUGHT with token_id
 *   6. (terminal stop)       → is_final=true, finish_reason="stop"
 *   7. (separate stream, error path)
 *      - "partial"           → non-final ANSWER
 *      - terminal error      → is_final=true, finish_reason="error"
 */
void emit_golden_sequence() {
    rac::llm::dispatch_llm_stream_event(fake_handle(), "The",
                                        false, 1, 0, 0.0f, nullptr, nullptr);
    rac::llm::dispatch_llm_stream_event(fake_handle(), " weather",
                                        false, 1, 0, 0.0f, nullptr, nullptr);
    rac::llm::dispatch_llm_stream_event(fake_handle(), " is",
                                        false, 1, 0, 0.0f, nullptr, nullptr);
    rac::llm::dispatch_llm_stream_event(fake_handle(), " sunny.",
                                        false, 1, 0, 0.0f, nullptr, nullptr);
    rac::llm::dispatch_llm_stream_event(fake_handle(), "think",
                                        false, 2, 12345, 0.0f, nullptr, nullptr);
    rac::llm::dispatch_llm_stream_event(fake_handle(), "",
                                        true, 1, 0, 0.0f, "stop", nullptr);

    /* error-path sub-sequence */
    rac::llm::dispatch_llm_stream_event(fake_handle(), "partial",
                                        false, 1, 0, 0.0f, nullptr, nullptr);
    rac::llm::dispatch_llm_stream_event(fake_handle(), "",
                                        true, 0, 0, 0.0f, "error",
                                        "engine backend vanished");
}

int run_produce(const std::string& out_path) {
    g_captured.clear();
    rac_result_t rc = rac_llm_set_stream_proto_callback(fake_handle(),
                                                        capture_callback, nullptr);
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "set_stream_proto_callback failed: %d\n",
                     static_cast<int>(rc));
        return 1;
    }

    emit_golden_sequence();
    rac_llm_unset_stream_proto_callback(fake_handle());

    std::ofstream out(out_path);
    if (!out) {
        std::fprintf(stderr, "cannot open %s for write\n", out_path.c_str());
        return 1;
    }
    out << "# v2 close-out Phase G-2 LLM parity test golden output\n";
    out << "# Generated by tests/streaming/llm_parity_test_cpp\n";
    out << "# Schema: token=<text>|is_final=<bool>|kind=<int>|token_id=<int>|finish_reason=<str>|error_message=<str>\n";
    out << "# seq + timestamp_us + logprob excluded — non-deterministic or platform-sensitive.\n";
    for (const auto& line : g_captured) out << line.text << "\n";
    std::printf("Wrote %zu events to %s\n", g_captured.size(), out_path.c_str());
    return 0;
}

int run_check(const std::string& golden_path) {
    g_captured.clear();
    rac_llm_set_stream_proto_callback(fake_handle(), capture_callback, nullptr);
    emit_golden_sequence();
    rac_llm_unset_stream_proto_callback(fake_handle());

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
    std::string path = "tests/streaming/fixtures/llm_golden_events.txt";
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
                 "llm_parity_test_cpp: skipped (RAC_HAVE_PROTOBUF not defined "
                 "at compile time).\n");
    return 0;
}

#endif
