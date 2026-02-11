// =============================================================================
// test_integration.cpp - End-to-End Integration Tests
// =============================================================================
// Tests the full assistant flow with a fake OpenClaw WebSocket server:
//
//   STT → send to fake OpenClaw → waiting chime plays → response arrives
//   → chime stops → TTS synthesizes response
//
// Also tests:
//   - Waiting chime timing (start/stop latency)
//   - Text sanitization for TTS
//   - TTS synthesis on various input texts
//
// Usage:
//   ./test-integration --run-all
//   ./test-integration --test-chime
//   ./test-integration --test-sanitization
//   ./test-integration --test-tts
//   ./test-integration --test-openclaw-flow
//   ./test-integration --test-openclaw-flow --delay <seconds>
// =============================================================================

#include "model_config.h"
#include "voice_pipeline.h"
#include "openclaw_client.h"
#include "waiting_chime.h"

// RAC headers
#include <rac/backends/rac_vad_onnx.h>
#include <rac/backends/rac_wakeword_onnx.h>
#include <rac/features/voice_agent/rac_voice_agent.h>
#include <rac/core/rac_error.h>

#include <iostream>
#include <sstream>
#include <vector>
#include <string>
#include <cstring>
#include <chrono>
#include <thread>
#include <atomic>
#include <mutex>
#include <random>
#include <functional>
#include <algorithm>
#include <cassert>

// Socket/network for fake server
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <poll.h>

// =============================================================================
// Test Result Tracking
// =============================================================================

struct TestResult {
    std::string name;
    bool passed = false;
    std::string details;
};

static void print_result(const TestResult& r) {
    std::cout << "\n" << (r.passed ? "PASS" : "FAIL")
              << ": " << r.name << "\n";
    if (!r.details.empty()) {
        std::cout << "  " << r.details << "\n";
    }
}

// =============================================================================
// Fake OpenClaw WebSocket Server
// =============================================================================
// A minimal WebSocket server that:
//   1. Accepts one client connection
//   2. Completes the WebSocket handshake
//   3. Receives messages (transcriptions)
//   4. After a configurable delay, sends back a "speak" message
//   5. Runs in a background thread
// =============================================================================

class FakeOpenClawServer {
public:
    struct Config {
        int port = 0;                    // 0 = auto-assign
        int response_delay_ms = 5000;    // Delay before sending response
        std::string response_text = "The weather in San Francisco is sunny and 72 degrees.";
        std::string source_channel = "fake-test";
    };

    FakeOpenClawServer() = default;

    explicit FakeOpenClawServer(const Config& config)
        : config_(config) {}

    ~FakeOpenClawServer() { stop(); }

    // Start the server (non-blocking, runs in background thread)
    bool start() {
        server_fd_ = socket(AF_INET, SOCK_STREAM, 0);
        if (server_fd_ < 0) {
            std::cerr << "[FakeServer] Failed to create socket\n";
            return false;
        }

        int opt = 1;
        setsockopt(server_fd_, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

        struct sockaddr_in addr = {};
        addr.sin_family = AF_INET;
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        addr.sin_port = htons(config_.port);

        if (bind(server_fd_, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
            std::cerr << "[FakeServer] Failed to bind\n";
            close(server_fd_);
            server_fd_ = -1;
            return false;
        }

        // Get assigned port
        socklen_t addr_len = sizeof(addr);
        getsockname(server_fd_, (struct sockaddr*)&addr, &addr_len);
        assigned_port_ = ntohs(addr.sin_port);

        if (listen(server_fd_, 1) < 0) {
            std::cerr << "[FakeServer] Failed to listen\n";
            close(server_fd_);
            server_fd_ = -1;
            return false;
        }

        running_.store(true);
        server_thread_ = std::thread(&FakeOpenClawServer::run, this);

        std::cout << "[FakeServer] Listening on port " << assigned_port_ << "\n";
        return true;
    }

    void stop() {
        running_.store(false);
        if (server_fd_ >= 0) {
            shutdown(server_fd_, SHUT_RDWR);
            close(server_fd_);
            server_fd_ = -1;
        }
        if (client_fd_ >= 0) {
            shutdown(client_fd_, SHUT_RDWR);
            close(client_fd_);
            client_fd_ = -1;
        }
        if (server_thread_.joinable()) {
            server_thread_.join();
        }
    }

    int port() const { return assigned_port_; }
    bool received_transcription() const { return transcription_received_.load(); }
    std::string last_transcription() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return last_transcription_;
    }
    int messages_received() const { return messages_received_.load(); }

private:
    Config config_;
    int server_fd_ = -1;
    int client_fd_ = -1;
    int assigned_port_ = 0;
    std::atomic<bool> running_{false};
    std::atomic<bool> transcription_received_{false};
    std::atomic<int> messages_received_{0};
    std::string last_transcription_;
    mutable std::mutex mutex_;
    std::thread server_thread_;

    void run() {
        // Wait for client connection (with timeout)
        struct pollfd pfd = {server_fd_, POLLIN, 0};
        int ret = poll(&pfd, 1, 30000);  // 30s timeout
        if (ret <= 0 || !running_.load()) return;

        struct sockaddr_in client_addr = {};
        socklen_t client_len = sizeof(client_addr);
        client_fd_ = accept(server_fd_, (struct sockaddr*)&client_addr, &client_len);
        if (client_fd_ < 0) return;

        std::cout << "[FakeServer] Client connected\n";

        // Disable Nagle
        int flag = 1;
        setsockopt(client_fd_, IPPROTO_TCP, TCP_NODELAY, &flag, sizeof(flag));

        // WebSocket handshake (server side)
        if (!do_ws_handshake()) {
            close(client_fd_);
            client_fd_ = -1;
            return;
        }

        std::cout << "[FakeServer] WebSocket handshake complete\n";

        // Send "connected" response
        send_ws_text("{\"type\":\"connected\",\"sessionId\":\"test-session\",\"serverVersion\":\"fake-1.0\"}");

        // Message loop
        while (running_.load()) {
            std::string payload;
            uint8_t opcode;
            if (!read_ws_frame(payload, opcode)) {
                if (!running_.load()) break;
                continue;
            }

            if (opcode == 0x08) {
                // Close frame
                std::cout << "[FakeServer] Client sent close frame\n";
                break;
            }

            if (opcode == 0x01) {
                // Text frame
                handle_message(payload);
            }
        }

        if (client_fd_ >= 0) {
            close(client_fd_);
            client_fd_ = -1;
        }
    }

    void handle_message(const std::string& payload) {
        messages_received_.fetch_add(1);
        std::cout << "[FakeServer] Received: " << payload.substr(0, 120) << "\n";

        // Check if it's a transcription
        if (payload.find("\"type\":\"transcription\"") != std::string::npos) {
            // Extract text (simple JSON parse)
            std::string text = extract_json_string(payload, "text");
            {
                std::lock_guard<std::mutex> lock(mutex_);
                last_transcription_ = text;
            }
            transcription_received_.store(true);

            std::cout << "[FakeServer] Got transcription: \"" << text << "\"\n";
            std::cout << "[FakeServer] Waiting " << config_.response_delay_ms << "ms before responding...\n";

            // Wait for the configured delay (simulating OpenClaw processing)
            auto delay_start = std::chrono::steady_clock::now();
            while (running_.load()) {
                auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                    std::chrono::steady_clock::now() - delay_start
                ).count();
                if (elapsed >= config_.response_delay_ms) break;
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
            }

            if (!running_.load()) return;

            // Send speak response
            std::ostringstream json;
            json << "{\"type\":\"speak\",\"text\":\"" << escape_json(config_.response_text)
                 << "\",\"sourceChannel\":\"" << config_.source_channel << "\""
                 << ",\"priority\":1,\"interrupt\":false}";

            std::cout << "[FakeServer] Sending speak response\n";
            send_ws_text(json.str());
        }
    }

    // --- WebSocket server-side handshake ---
    // The client checks for "101" in the response but doesn't validate the
    // Sec-WebSocket-Accept header, so we can send a simplified response.
    bool do_ws_handshake() {
        // Read HTTP request
        std::string request;
        char buf[1];
        int timeout_count = 0;
        while (timeout_count < 5000) {
            struct pollfd pfd = {client_fd_, POLLIN, 0};
            int ret = poll(&pfd, 1, 1);
            if (ret > 0) {
                ssize_t n = recv(client_fd_, buf, 1, 0);
                if (n <= 0) return false;
                request += buf[0];
                if (request.size() >= 4 && request.substr(request.size() - 4) == "\r\n\r\n") {
                    break;
                }
            } else {
                timeout_count++;
            }
        }

        if (request.find("Upgrade: websocket") == std::string::npos &&
            request.find("upgrade: websocket") == std::string::npos) {
            std::cerr << "[FakeServer] Not a WebSocket upgrade request\n";
            return false;
        }

        // Send 101 Switching Protocols (simplified - no proper accept key)
        std::string response =
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            "Sec-WebSocket-Accept: fake-accept-key\r\n"
            "\r\n";

        return send_all(response.data(), response.size());
    }

    // --- WebSocket frame I/O (server side - frames are masked by client) ---
    bool read_ws_frame(std::string& out_payload, uint8_t& out_opcode) {
        uint8_t header[2];
        if (!recv_bytes(header, 2, 500)) return false;

        out_opcode = header[0] & 0x0F;
        bool masked = (header[1] & 0x80) != 0;
        uint64_t payload_len = header[1] & 0x7F;

        if (payload_len == 126) {
            uint8_t ext[2];
            if (!recv_bytes(ext, 2, 500)) return false;
            payload_len = ((uint64_t)ext[0] << 8) | ext[1];
        } else if (payload_len == 127) {
            uint8_t ext[8];
            if (!recv_bytes(ext, 8, 500)) return false;
            payload_len = 0;
            for (int i = 0; i < 8; i++) payload_len = (payload_len << 8) | ext[i];
        }

        if (payload_len > 1024 * 1024) return false;

        uint8_t mask_key[4] = {};
        if (masked) {
            if (!recv_bytes(mask_key, 4, 500)) return false;
        }

        out_payload.resize(payload_len);
        if (payload_len > 0) {
            if (!recv_bytes(reinterpret_cast<uint8_t*>(&out_payload[0]), payload_len, 2000)) return false;
            if (masked) {
                for (size_t i = 0; i < payload_len; i++) {
                    out_payload[i] ^= mask_key[i % 4];
                }
            }
        }
        return true;
    }

    void send_ws_text(const std::string& payload) {
        std::vector<uint8_t> frame;
        frame.push_back(0x81);  // FIN + text

        size_t len = payload.size();
        if (len <= 125) {
            frame.push_back(static_cast<uint8_t>(len));  // Server frames are NOT masked
        } else if (len <= 65535) {
            frame.push_back(126);
            frame.push_back((len >> 8) & 0xFF);
            frame.push_back(len & 0xFF);
        } else {
            frame.push_back(127);
            for (int i = 7; i >= 0; i--) {
                frame.push_back((len >> (8 * i)) & 0xFF);
            }
        }

        frame.insert(frame.end(), payload.begin(), payload.end());
        send_all(frame.data(), frame.size());
    }

    bool recv_bytes(void* buf, size_t len, int timeout_ms) {
        size_t total = 0;
        auto* p = static_cast<uint8_t*>(buf);
        while (total < len) {
            struct pollfd pfd = {client_fd_, POLLIN, 0};
            int ret = poll(&pfd, 1, timeout_ms);
            if (ret <= 0) return false;
            ssize_t n = recv(client_fd_, p + total, len - total, 0);
            if (n <= 0) return false;
            total += n;
        }
        return true;
    }

    bool send_all(const void* buf, size_t len) {
        size_t total = 0;
        auto* p = static_cast<const uint8_t*>(buf);
        while (total < len) {
            ssize_t n = send(client_fd_, p + total, len - total, MSG_NOSIGNAL);
            if (n <= 0) return false;
            total += n;
        }
        return true;
    }

    static std::string extract_json_string(const std::string& json, const std::string& key) {
        std::string pattern = "\"" + key + "\":\"";
        size_t pos = json.find(pattern);
        if (pos == std::string::npos) return "";
        pos += pattern.size();
        size_t end = json.find('"', pos);
        if (end == std::string::npos) return "";
        return json.substr(pos, end - pos);
    }

    static std::string escape_json(const std::string& s) {
        std::string out;
        out.reserve(s.size());
        for (char c : s) {
            if (c == '"') out += "\\\"";
            else if (c == '\\') out += "\\\\";
            else if (c == '\n') out += "\\n";
            else out += c;
        }
        return out;
    }
};

// =============================================================================
// Audio Capture Buffer (replaces ALSA for testing)
// =============================================================================

struct AudioCapture {
    std::vector<int16_t> captured_samples;
    std::mutex mutex;
    int sample_rate = 0;
    size_t total_chunks = 0;

    void on_audio(const int16_t* samples, size_t num_samples, int sr) {
        std::lock_guard<std::mutex> lock(mutex);
        captured_samples.insert(captured_samples.end(), samples, samples + num_samples);
        sample_rate = sr;
        total_chunks++;
    }

    size_t total_samples() {
        std::lock_guard<std::mutex> lock(mutex);
        return captured_samples.size();
    }

    float duration_seconds() {
        std::lock_guard<std::mutex> lock(mutex);
        if (sample_rate <= 0 || captured_samples.empty()) return 0.0f;
        return static_cast<float>(captured_samples.size()) / sample_rate;
    }

    void clear() {
        std::lock_guard<std::mutex> lock(mutex);
        captured_samples.clear();
        total_chunks = 0;
    }
};

// =============================================================================
// Test: Waiting Chime Timing
// =============================================================================
// Verifies:
//   - Chime starts producing audio immediately after start()
//   - Chime stops within ~100ms after stop()
//   - Chime produces the expected amount of audio per loop iteration
// =============================================================================

TestResult test_waiting_chime_timing() {
    TestResult result;
    result.name = "Waiting Chime - Start/Stop Timing";

    AudioCapture capture;
    openclaw::WaitingChimeConfig config;
    config.sample_rate = 22050;
    config.tone_duration_ms = 1500;
    config.silence_duration_ms = 1000;
    config.volume = 0.2f;

    openclaw::WaitingChime chime(config, [&capture](const int16_t* samples, size_t n, int sr) {
        capture.on_audio(samples, n, sr);
    });

    // Test 1: Chime should not be playing initially
    if (chime.is_playing()) {
        result.details = "Chime is playing before start() was called";
        return result;
    }

    // Test 2: Start the chime, verify audio arrives quickly
    auto start_time = std::chrono::steady_clock::now();
    chime.start();

    // Wait up to 500ms for first audio
    bool got_audio = false;
    for (int i = 0; i < 50; i++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
        if (capture.total_samples() > 0) {
            got_audio = true;
            break;
        }
    }

    auto first_audio_time = std::chrono::steady_clock::now();
    auto latency_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        first_audio_time - start_time
    ).count();

    if (!got_audio) {
        chime.stop();
        result.details = "No audio received within 500ms of start()";
        return result;
    }

    if (!chime.is_playing()) {
        chime.stop();
        result.details = "is_playing() returned false after start()";
        return result;
    }

    // Test 3: Let it play for 3 seconds, verify audio accumulates
    std::this_thread::sleep_for(std::chrono::milliseconds(3000));
    float duration_before_stop = capture.duration_seconds();

    // Test 4: Stop the chime, measure stop latency
    auto stop_start = std::chrono::steady_clock::now();
    chime.stop();
    auto stop_end = std::chrono::steady_clock::now();
    auto stop_latency_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        stop_end - stop_start
    ).count();

    if (chime.is_playing()) {
        result.details = "is_playing() returned true after stop()";
        return result;
    }

    // Test 5: Verify no more audio after stop
    size_t samples_at_stop = capture.total_samples();
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    size_t samples_after_wait = capture.total_samples();

    if (samples_after_wait != samples_at_stop) {
        result.details = "Audio still being produced after stop() ("
                       + std::to_string(samples_after_wait - samples_at_stop) + " extra samples)";
        return result;
    }

    // Test 6: Verify double-start is safe
    chime.start();
    chime.start();  // Should be no-op
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    chime.stop();

    // Test 7: Verify double-stop is safe
    chime.stop();  // Should be no-op

    // All checks passed
    result.passed = true;

    std::ostringstream details;
    details << "First audio latency: " << latency_ms << "ms"
            << ", Audio duration (3s play): " << duration_before_stop << "s"
            << ", Stop latency: " << stop_latency_ms << "ms"
            << ", Samples produced: " << samples_at_stop;
    result.details = details.str();

    return result;
}

// =============================================================================
// Test: Waiting Chime Audio Content
// =============================================================================
// Verifies the generated chime buffer contains non-silent audio with
// the expected structure (tone followed by silence).
// =============================================================================

TestResult test_waiting_chime_audio_content() {
    TestResult result;
    result.name = "Waiting Chime - Audio Content Quality";

    AudioCapture capture;
    openclaw::WaitingChimeConfig config;
    config.sample_rate = 22050;
    config.tone_duration_ms = 1000;
    config.silence_duration_ms = 500;
    config.volume = 0.3f;

    openclaw::WaitingChime chime(config, [&capture](const int16_t* samples, size_t n, int sr) {
        capture.on_audio(samples, n, sr);
    });

    // Play for one full loop iteration (~1.5 seconds)
    chime.start();
    std::this_thread::sleep_for(std::chrono::milliseconds(1800));
    chime.stop();

    auto samples = capture.captured_samples;
    if (samples.empty()) {
        result.details = "No audio samples captured";
        return result;
    }

    // Check that the tone portion has non-zero samples
    int tone_samples = config.sample_rate * config.tone_duration_ms / 1000;
    int check_count = std::min(static_cast<int>(samples.size()), tone_samples);

    int non_zero_count = 0;
    int16_t max_amplitude = 0;
    for (int i = 0; i < check_count; i++) {
        if (samples[i] != 0) non_zero_count++;
        int16_t abs_val = std::abs(samples[i]);
        if (abs_val > max_amplitude) max_amplitude = abs_val;
    }

    float non_zero_ratio = static_cast<float>(non_zero_count) / check_count;

    // The tone portion should be mostly non-zero (except at zero crossings)
    if (non_zero_ratio < 0.8f) {
        result.details = "Tone portion is too quiet - only " + std::to_string(non_zero_ratio * 100) + "% non-zero";
        return result;
    }

    // Max amplitude should be reasonable (not clipping, not silent)
    // At 30% volume: max should be around 0.3 * 32767 ≈ 9830
    if (max_amplitude < 1000) {
        result.details = "Max amplitude too low: " + std::to_string(max_amplitude);
        return result;
    }
    if (max_amplitude > 32000) {
        result.details = "Max amplitude near clipping: " + std::to_string(max_amplitude);
        return result;
    }

    // Check the silence portion (if we have enough samples)
    int silence_start = tone_samples;
    int total_expected = tone_samples + (config.sample_rate * config.silence_duration_ms / 1000);
    if (static_cast<int>(samples.size()) >= total_expected) {
        int silence_non_zero = 0;
        for (int i = silence_start; i < total_expected; i++) {
            if (samples[i] != 0) silence_non_zero++;
        }
        if (silence_non_zero > 0) {
            result.details = "Silence portion has " + std::to_string(silence_non_zero) + " non-zero samples";
            return result;
        }
    }

    result.passed = true;
    std::ostringstream details;
    details << "Samples: " << samples.size()
            << ", Non-zero in tone: " << (non_zero_ratio * 100) << "%"
            << ", Max amplitude: " << max_amplitude
            << ", Duration: " << capture.duration_seconds() << "s";
    result.details = details.str();

    return result;
}

// =============================================================================
// Test: TTS Synthesis
// =============================================================================
// Verifies TTS can synthesize text and produces valid audio output.
// =============================================================================

TestResult test_tts_synthesis() {
    TestResult result;
    result.name = "TTS Synthesis - Various Texts";

    // Create voice agent for TTS
    rac_voice_agent_handle_t agent = nullptr;
    rac_result_t res = rac_voice_agent_create_standalone(&agent);
    if (res != RAC_SUCCESS) {
        result.details = "Failed to create voice agent";
        return result;
    }

    // Load STT model (required for init)
    std::string stt_path = openclaw::get_stt_model_path();
    res = rac_voice_agent_load_stt_model(agent, stt_path.c_str(), openclaw::STT_MODEL_ID, "Parakeet");
    if (res != RAC_SUCCESS) {
        result.details = "Failed to load STT model";
        rac_voice_agent_destroy(agent);
        return result;
    }

    // Load TTS model
    std::string tts_path = openclaw::get_tts_model_path();
    res = rac_voice_agent_load_tts_voice(agent, tts_path.c_str(), "piper", "Piper");
    if (res != RAC_SUCCESS) {
        result.details = "Failed to load TTS model";
        rac_voice_agent_destroy(agent);
        return result;
    }

    res = rac_voice_agent_initialize_with_loaded_models(agent);
    if (res != RAC_SUCCESS) {
        result.details = "Failed to initialize voice agent";
        rac_voice_agent_destroy(agent);
        return result;
    }

    // Test texts - these simulate various OpenClaw responses
    struct TTSTestCase {
        std::string description;
        std::string text;
        bool expect_audio;
    };

    std::vector<TTSTestCase> test_cases = {
        {"Simple sentence", "The weather is sunny today.", true},
        {"Longer response", "I found several results for your query. The top recommendation is a restaurant called Blue Fin Sushi, located downtown. They have excellent reviews and are open until ten PM.", true},
        {"With numbers", "The temperature is 72 degrees, and there is a 30 percent chance of rain.", true},
        {"Short response", "Sure!", true},
        {"Question response", "Would you like me to set a reminder for that?", true},
    };

    int passed = 0;
    int total = static_cast<int>(test_cases.size());
    std::ostringstream details;

    for (const auto& tc : test_cases) {
        void* audio_data = nullptr;
        size_t audio_size = 0;

        res = rac_voice_agent_synthesize_speech(agent, tc.text.c_str(), &audio_data, &audio_size);

        bool has_audio = (res == RAC_SUCCESS && audio_data != nullptr && audio_size > 0);

        if (has_audio == tc.expect_audio) {
            passed++;
            size_t num_samples = audio_size / sizeof(int16_t);
            float duration = num_samples / 22050.0f;
            details << "  OK: " << tc.description
                    << " (" << num_samples << " samples, " << duration << "s)\n";
        } else {
            details << "  FAIL: " << tc.description
                    << " (expected audio=" << tc.expect_audio
                    << ", got audio=" << has_audio << ")\n";
        }

        if (audio_data) free(audio_data);
    }

    rac_voice_agent_destroy(agent);

    result.passed = (passed == total);
    result.details = std::to_string(passed) + "/" + std::to_string(total) + " TTS tests passed:\n" + details.str();

    return result;
}

// =============================================================================
// Test: Text Sanitization for TTS
// =============================================================================
// Tests the sanitize_text_for_tts function through VoicePipeline::speak_text.
// We verify that special characters, emojis, and markdown are properly
// handled before reaching TTS synthesis.
// =============================================================================

TestResult test_text_sanitization() {
    TestResult result;
    result.name = "Text Sanitization for TTS";

    // Create a pipeline just to test speak_text (which runs sanitization)
    openclaw::VoicePipelineConfig pipeline_config;

    AudioCapture capture;
    pipeline_config.on_audio_output = [&capture](const int16_t* samples, size_t n, int sr) {
        capture.on_audio(samples, n, sr);
    };
    pipeline_config.on_error = [](const std::string& err) {
        std::cerr << "[Sanitization Test] Error: " << err << "\n";
    };

    openclaw::VoicePipeline pipeline(pipeline_config);
    if (!pipeline.initialize()) {
        result.details = "Failed to initialize pipeline: " + pipeline.last_error();
        return result;
    }

    // Test cases with various problematic inputs
    struct SanitizeTestCase {
        std::string description;
        std::string input;
        bool should_produce_audio;  // false = entirely stripped (empty)
    };

    std::vector<SanitizeTestCase> test_cases = {
        // Should produce audio (cleaned text is non-empty)
        {"Clean text", "Hello, how are you?", true},
        {"Markdown bold", "This is **really** important.", true},
        {"Markdown code", "Use the `print` function.", true},
        {"Markdown headers", "# Main Heading\n## Subheading\nContent here.", true},
        {"Emoji in text", "Great job! \xF0\x9F\x98\x80 Keep it up!", true},
        {"Mixed markdown + emoji", "**Note**: Check the docs \xF0\x9F\x93\x9A for details.", true},
        {"Special symbols", "Cost is $100 & tax is 8%.", true},
        {"HTML-like tags", "Use <b>bold</b> for emphasis.", true},
        {"Brackets and pipes", "Options: [A] | [B] | [C]", true},
        {"Multiple dashes", "Section one --- Section two", true},
        {"Backslashes", "Path: C:\\Users\\test\\file.txt", true},

        // Should NOT produce audio (entirely stripped)
        {"Only emoji", "\xF0\x9F\x98\x80\xF0\x9F\x98\x82\xF0\x9F\x98\x8D", false},
        {"Only markdown symbols", "**__``##~~", false},
        {"Only special chars", "[]{}|\\^@~<>", false},
    };

    int passed = 0;
    int total = static_cast<int>(test_cases.size());
    std::ostringstream details;

    for (const auto& tc : test_cases) {
        capture.clear();

        bool spoke = pipeline.speak_text(tc.input);
        bool produced_audio = capture.total_samples() > 0;

        bool test_ok;
        if (tc.should_produce_audio) {
            // We expect speak_text to return true and produce some audio
            test_ok = spoke && produced_audio;
        } else {
            // We expect speak_text to return true (not an error) but produce no audio
            // OR return true with the text fully stripped
            test_ok = !produced_audio;
        }

        if (test_ok) {
            passed++;
            details << "  OK: " << tc.description;
            if (produced_audio) {
                details << " (" << capture.total_samples() << " samples)";
            } else {
                details << " (correctly stripped)";
            }
            details << "\n";
        } else {
            details << "  FAIL: " << tc.description
                    << " (expected_audio=" << tc.should_produce_audio
                    << ", got_audio=" << produced_audio
                    << ", spoke=" << spoke << ")\n";
        }
    }

    result.passed = (passed == total);
    result.details = std::to_string(passed) + "/" + std::to_string(total) + " sanitization tests passed:\n" + details.str();

    return result;
}

// =============================================================================
// Test: Full OpenClaw Flow with Fake Server
// =============================================================================
// End-to-end test:
//   1. Start fake OpenClaw server with configurable delay
//   2. Connect OpenClawClient to fake server
//   3. Send transcription (triggers waiting chime)
//   4. Verify chime plays during the wait
//   5. Fake server sends response after delay
//   6. Verify chime stops and TTS speaks the response
// =============================================================================

TestResult test_openclaw_flow(int response_delay_ms) {
    TestResult result;
    result.name = "OpenClaw Flow - " + std::to_string(response_delay_ms / 1000) + "s delay";

    std::string response_text = "Based on my research, the best Italian restaurant nearby is Trattoria Roma. "
                                "They have excellent pasta and a cozy atmosphere. "
                                "They're open until 10 PM tonight.";

    // --- Step 1: Start fake server ---
    FakeOpenClawServer::Config server_config;
    server_config.response_delay_ms = response_delay_ms;
    server_config.response_text = response_text;
    server_config.source_channel = "integration-test";

    FakeOpenClawServer server(server_config);
    if (!server.start()) {
        result.details = "Failed to start fake server";
        return result;
    }

    // Give server a moment to be ready
    std::this_thread::sleep_for(std::chrono::milliseconds(100));

    // --- Step 2: Set up audio capture (instead of ALSA) ---
    AudioCapture chime_capture;  // Captures chime audio
    AudioCapture tts_capture;    // Captures TTS audio

    // --- Step 3: Create waiting chime ---
    openclaw::WaitingChimeConfig chime_config;
    chime_config.sample_rate = 22050;

    openclaw::WaitingChime waiting_chime(chime_config, [&chime_capture](const int16_t* samples, size_t n, int sr) {
        chime_capture.on_audio(samples, n, sr);
    });

    // --- Step 4: Create voice pipeline (for TTS) ---
    openclaw::VoicePipelineConfig pipeline_config;
    pipeline_config.on_audio_output = [&tts_capture](const int16_t* samples, size_t n, int sr) {
        tts_capture.on_audio(samples, n, sr);
    };
    pipeline_config.on_error = [](const std::string& err) {
        std::cerr << "[Integration] Pipeline error: " << err << "\n";
    };

    openclaw::VoicePipeline pipeline(pipeline_config);
    if (!pipeline.initialize()) {
        result.details = "Failed to initialize pipeline: " + pipeline.last_error();
        server.stop();
        return result;
    }

    // --- Step 5: Connect to fake OpenClaw ---
    openclaw::OpenClawClientConfig client_config;
    client_config.url = "ws://127.0.0.1:" + std::to_string(server.port());
    client_config.device_id = "integration-test";

    openclaw::OpenClawClient openclaw_client(client_config);
    if (!openclaw_client.connect()) {
        result.details = "Failed to connect to fake server: " + openclaw_client.last_error();
        server.stop();
        return result;
    }

    // Give connection a moment to stabilize
    std::this_thread::sleep_for(std::chrono::milliseconds(200));

    // --- Step 6: Send transcription and start chime ---
    std::string transcription = "What's the best Italian restaurant nearby?";
    std::cout << "[Integration] Sending transcription: \"" << transcription << "\"\n";

    openclaw_client.send_transcription(transcription, true);
    waiting_chime.start();

    auto send_time = std::chrono::steady_clock::now();

    // --- Step 7: Poll for response while chime plays ---
    bool response_received = false;
    openclaw::SpeakMessage received_message;
    size_t chime_samples_at_response = 0;

    // Poll loop (same pattern as main.cpp)
    const auto poll_interval = std::chrono::milliseconds(200);
    auto last_poll = std::chrono::steady_clock::now();
    int max_wait_ms = response_delay_ms + 10000;  // Extra 10s buffer
    auto deadline = send_time + std::chrono::milliseconds(max_wait_ms);

    while (std::chrono::steady_clock::now() < deadline) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));

        auto now = std::chrono::steady_clock::now();
        if (now - last_poll >= poll_interval) {
            last_poll = now;

            openclaw::SpeakMessage message;
            if (openclaw_client.poll_speak_queue(message)) {
                // Stop chime and record timing
                chime_samples_at_response = chime_capture.total_samples();
                waiting_chime.stop();

                auto response_time = std::chrono::steady_clock::now();
                auto total_wait_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                    response_time - send_time
                ).count();

                received_message = message;
                response_received = true;

                std::cout << "[Integration] Response received after " << total_wait_ms << "ms\n";
                std::cout << "[Integration] Chime played " << chime_capture.duration_seconds() << "s of audio\n";
                break;
            }
        }
    }

    if (!response_received) {
        waiting_chime.stop();
        openclaw_client.disconnect();
        server.stop();
        result.details = "No response received within " + std::to_string(max_wait_ms) + "ms";
        return result;
    }

    // --- Step 8: Verify chime played during the wait ---
    float chime_duration = chime_capture.duration_seconds();

    // Chime should have played for at least some portion of the delay
    float expected_min_chime_seconds = response_delay_ms / 1000.0f * 0.5f;  // At least 50% of delay
    if (chime_duration < expected_min_chime_seconds && response_delay_ms >= 2000) {
        result.details = "Chime didn't play long enough: " + std::to_string(chime_duration) + "s"
                       + " (expected at least " + std::to_string(expected_min_chime_seconds) + "s)";
        openclaw_client.disconnect();
        server.stop();
        return result;
    }

    // --- Step 9: Verify chime stopped after response ---
    size_t samples_after_stop = chime_capture.total_samples();
    std::this_thread::sleep_for(std::chrono::milliseconds(300));
    size_t samples_after_wait = chime_capture.total_samples();

    if (samples_after_wait != samples_after_stop) {
        result.details = "Chime still producing audio after stop()";
        openclaw_client.disconnect();
        server.stop();
        return result;
    }

    // --- Step 10: Speak the response via TTS ---
    std::cout << "[Integration] Speaking response via TTS...\n";
    bool spoke = pipeline.speak_text(received_message.text);

    if (!spoke) {
        result.details = "TTS failed to speak the response";
        openclaw_client.disconnect();
        server.stop();
        return result;
    }

    float tts_duration = tts_capture.duration_seconds();
    if (tts_duration <= 0) {
        result.details = "TTS produced no audio output";
        openclaw_client.disconnect();
        server.stop();
        return result;
    }

    // --- Step 11: Verify the received message matches what the server sent ---
    if (received_message.text != response_text) {
        result.details = "Response text mismatch. Got: \"" + received_message.text.substr(0, 80) + "...\"";
        openclaw_client.disconnect();
        server.stop();
        return result;
    }

    if (received_message.source_channel != "integration-test") {
        result.details = "Source channel mismatch. Got: \"" + received_message.source_channel + "\"";
        openclaw_client.disconnect();
        server.stop();
        return result;
    }

    // --- Cleanup ---
    openclaw_client.disconnect();
    server.stop();

    // All checks passed!
    result.passed = true;

    std::ostringstream details;
    details << "Server delay: " << response_delay_ms << "ms"
            << ", Chime audio: " << chime_duration << "s"
            << " (" << chime_samples_at_response << " samples)"
            << ", TTS audio: " << tts_duration << "s"
            << " (" << tts_capture.total_samples() << " samples)"
            << ", Response text matched, Source channel matched";
    result.details = details.str();

    return result;
}

// =============================================================================
// Main
// =============================================================================

void print_usage(const char* prog) {
    std::cout << "OpenClaw Integration Tests\n\n"
              << "Usage: " << prog << " [options]\n\n"
              << "Options:\n"
              << "  --run-all                Run all integration tests\n"
              << "  --test-chime             Test waiting chime timing and audio\n"
              << "  --test-sanitization      Test text sanitization for TTS\n"
              << "  --test-tts               Test TTS synthesis on various texts\n"
              << "  --test-openclaw-flow     Test full flow with fake OpenClaw server\n"
              << "  --delay <seconds>        Response delay for --test-openclaw-flow (default: 5)\n"
              << "  --help                   Show this help\n";
}

// Helper: Initialize model system and ONNX backends (expensive - only call when needed)
static bool g_backends_initialized = false;
static bool ensure_backends_initialized() {
    if (g_backends_initialized) return true;

    if (!openclaw::init_model_system()) {
        std::cerr << "Failed to initialize model system\n";
        return false;
    }
    rac_backend_onnx_register();
    rac_backend_wakeword_onnx_register();
    g_backends_initialized = true;
    return true;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    std::vector<TestResult> results;
    int flow_delay_seconds = 5;

    // Parse optional delay
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--delay") == 0 && i + 1 < argc) {
            flow_delay_seconds = std::atoi(argv[++i]);
            if (flow_delay_seconds < 1) flow_delay_seconds = 1;
            if (flow_delay_seconds > 60) flow_delay_seconds = 60;
        }
    }

    for (int i = 1; i < argc; i++) {
        std::string arg = argv[i];

        if (arg == "--help" || arg == "-h") {
            print_usage(argv[0]);
            return 0;
        }
        else if (arg == "--test-chime") {
            // Chime tests need NO model/backend infrastructure
            results.push_back(test_waiting_chime_timing());
            results.push_back(test_waiting_chime_audio_content());
        }
        else if (arg == "--test-sanitization") {
            if (!ensure_backends_initialized()) return 1;
            results.push_back(test_text_sanitization());
        }
        else if (arg == "--test-tts") {
            if (!ensure_backends_initialized()) return 1;
            results.push_back(test_tts_synthesis());
        }
        else if (arg == "--test-openclaw-flow") {
            if (!ensure_backends_initialized()) return 1;
            results.push_back(test_openclaw_flow(flow_delay_seconds * 1000));
        }
        else if (arg == "--run-all") {
            std::cout << "\n" << std::string(60, '=') << "\n"
                      << "  INTEGRATION TEST SUITE\n"
                      << "  OpenClaw Hybrid Assistant\n"
                      << std::string(60, '=') << "\n\n";

            // --- Section 1: Waiting Chime (NO backend init needed) ---
            std::cout << "--- Section 1: Waiting Chime ---\n\n";
            results.push_back(test_waiting_chime_timing());
            results.push_back(test_waiting_chime_audio_content());

            // --- Initialize backends for remaining tests ---
            if (!ensure_backends_initialized()) return 1;

            // --- Section 2: Text Sanitization ---
            std::cout << "\n--- Section 2: Text Sanitization ---\n\n";
            results.push_back(test_text_sanitization());

            // --- Section 3: TTS Synthesis ---
            std::cout << "\n--- Section 3: TTS Synthesis ---\n\n";
            results.push_back(test_tts_synthesis());

            // --- Section 4: Full OpenClaw Flow ---
            std::cout << "\n--- Section 4: Full OpenClaw Flow ---\n\n";

            // Test with 5-second delay (moderate wait)
            std::cout << "Test 4.1: 5-second response delay\n";
            results.push_back(test_openclaw_flow(5000));

            // Test with 15-second delay (long wait - multiple chime loops)
            std::cout << "\nTest 4.2: 15-second response delay\n";
            results.push_back(test_openclaw_flow(15000));

            // Test with 1-second delay (fast response)
            std::cout << "\nTest 4.3: 1-second response delay (fast response)\n";
            results.push_back(test_openclaw_flow(1000));
        }
        else if (arg == "--delay") {
            i++;  // Skip value (already parsed above)
        }
    }

    // Print summary
    std::cout << "\n" << std::string(60, '=') << "\n"
              << "  TEST RESULTS SUMMARY\n"
              << std::string(60, '=') << "\n";

    int passed = 0, failed = 0;
    for (const auto& r : results) {
        print_result(r);
        if (r.passed) passed++;
        else failed++;
    }

    std::cout << "\n" << std::string(60, '-') << "\n"
              << "  TOTAL: " << passed << " passed, " << failed << " failed\n"
              << std::string(60, '-') << "\n";

    return failed > 0 ? 1 : 0;
}
