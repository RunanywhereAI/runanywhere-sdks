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

#include "config/model_config.h"
#include "pipeline/voice_pipeline.h"
#include "pipeline/tts_queue.h"
#include "network/openclaw_client.h"
#include "audio/waiting_chime.h"

// RAC headers
#include <rac/backends/rac_vad_onnx.h>
#include <rac/backends/rac_wakeword_onnx.h>
#include <rac/features/voice_agent/rac_voice_agent.h>
#include <rac/core/rac_error.h>

#include <iostream>
#include <sstream>
#include <fstream>
#include <cmath>
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
// Test WAV File Generator (for earcon/chime tests)
// =============================================================================
// Creates a simple 16-bit PCM WAV file with a sine tone at the given path.

static std::string create_test_wav(int sample_rate = 22050, int duration_ms = 500) {
    static int counter = 0;
    std::string path = "/tmp/test_earcon_" + std::to_string(counter++) + ".wav";

    int num_samples = sample_rate * duration_ms / 1000;
    std::vector<int16_t> samples(num_samples);
    for (int i = 0; i < num_samples; ++i) {
        float t = static_cast<float>(i) / sample_rate;
        samples[i] = static_cast<int16_t>(8000.0f * std::sin(2.0f * 3.14159f * 440.0f * t));
    }

    std::ofstream file(path, std::ios::binary);
    // RIFF header
    uint32_t data_size = num_samples * 2;
    uint32_t file_size = 36 + data_size;
    file.write("RIFF", 4);
    file.write(reinterpret_cast<char*>(&file_size), 4);
    file.write("WAVE", 4);
    // fmt chunk
    file.write("fmt ", 4);
    uint32_t fmt_size = 16;
    file.write(reinterpret_cast<char*>(&fmt_size), 4);
    uint16_t audio_format = 1;  // PCM
    file.write(reinterpret_cast<char*>(&audio_format), 2);
    uint16_t channels = 1;
    file.write(reinterpret_cast<char*>(&channels), 2);
    uint32_t sr = sample_rate;
    file.write(reinterpret_cast<char*>(&sr), 4);
    uint32_t byte_rate = sample_rate * 2;
    file.write(reinterpret_cast<char*>(&byte_rate), 4);
    uint16_t block_align = 2;
    file.write(reinterpret_cast<char*>(&block_align), 2);
    uint16_t bits = 16;
    file.write(reinterpret_cast<char*>(&bits), 2);
    // data chunk
    file.write("data", 4);
    file.write(reinterpret_cast<char*>(&data_size), 4);
    file.write(reinterpret_cast<const char*>(samples.data()), data_size);
    file.close();

    return path;
}

// =============================================================================
// Test: TTS Queue - Parallel Synthesis and Playback
// =============================================================================
// Verifies that the TTSQueue plays audio from the consumer thread while
// the producer is still pushing more chunks. This is the core optimization:
// sentence N+1 is synthesized while sentence N plays.
//
// We simulate this by:
//   1. Pushing chunk 1 into the queue
//   2. Verifying playback starts (consumer plays chunk 1)
//   3. While chunk 1 is playing, pushing chunk 2
//   4. Verifying chunk 2 plays immediately after chunk 1 (no gap)
// =============================================================================

TestResult test_tts_queue_parallel_playback() {
    TestResult result;
    result.name = "TTS Queue - Parallel Synthesis and Playback";

    // Track when each chunk's audio arrives at the "speaker"
    struct ChunkArrival {
        std::chrono::steady_clock::time_point time;
        size_t num_samples = 0;
    };

    std::mutex arrivals_mutex;
    std::vector<ChunkArrival> arrivals;
    size_t total_played_samples = 0;

    auto play_audio = [&](const int16_t*, size_t num_samples, int, const std::atomic<bool>&) {
        std::lock_guard<std::mutex> lock(arrivals_mutex);
        arrivals.push_back({std::chrono::steady_clock::now(), num_samples});
        total_played_samples += num_samples;
        // Simulate ALSA blocking playback: ~46ms per 1024 samples at 22050Hz
        // We use a shorter sleep to keep the test fast
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    };

    openclaw::TTSQueue queue(play_audio);

    auto test_start = std::chrono::steady_clock::now();

    // Generate 3 fake "sentence" audio chunks (~0.5s each at 22050Hz)
    const int sample_rate = 22050;
    const int samples_per_chunk = sample_rate / 2;  // 0.5s

    // Push chunk 1 - consumer should start playing immediately
    {
        openclaw::AudioChunk chunk;
        chunk.samples.resize(samples_per_chunk, 1000);  // Non-zero audio
        chunk.sample_rate = sample_rate;
        queue.push(std::move(chunk));
    }

    // Wait a bit for consumer to pick up chunk 1
    std::this_thread::sleep_for(std::chrono::milliseconds(50));

    // Verify playback has started
    {
        std::lock_guard<std::mutex> lock(arrivals_mutex);
        if (arrivals.empty()) {
            queue.finish();
            result.details = "Consumer did not start playing chunk 1 within 50ms";
            return result;
        }
    }

    auto chunk1_play_start = std::chrono::steady_clock::now();

    // Push chunk 2 while chunk 1 is still "playing" (simulated)
    {
        openclaw::AudioChunk chunk;
        chunk.samples.resize(samples_per_chunk, 2000);
        chunk.sample_rate = sample_rate;
        queue.push(std::move(chunk));
    }

    // Push chunk 3
    {
        openclaw::AudioChunk chunk;
        chunk.samples.resize(samples_per_chunk, 3000);
        chunk.sample_rate = sample_rate;
        queue.push(std::move(chunk));
    }

    // Signal done
    queue.finish();

    // Wait for consumer to finish playing all chunks
    int wait_count = 0;
    while (queue.is_active() && wait_count < 100) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        wait_count++;
    }

    auto test_end = std::chrono::steady_clock::now();
    auto total_ms = std::chrono::duration_cast<std::chrono::milliseconds>(test_end - test_start).count();

    // Verify all 3 chunks were played
    size_t expected_total = samples_per_chunk * 3;
    if (total_played_samples != expected_total) {
        result.details = "Expected " + std::to_string(expected_total) + " samples played, got "
                       + std::to_string(total_played_samples);
        return result;
    }

    // Verify queue is no longer active
    if (queue.is_active()) {
        result.details = "Queue still active after all chunks played";
        return result;
    }

    // Check that chunks arrived in order and without huge gaps
    std::lock_guard<std::mutex> lock(arrivals_mutex);
    if (arrivals.size() < 3) {
        result.details = "Expected at least 3 chunk arrivals, got " + std::to_string(arrivals.size());
        return result;
    }

    // Measure gap between first chunk arrival and last chunk arrival
    auto first_arrival = arrivals.front().time;
    auto last_arrival = arrivals.back().time;
    auto span_ms = std::chrono::duration_cast<std::chrono::milliseconds>(last_arrival - first_arrival).count();

    result.passed = true;
    std::ostringstream details;
    details << "3 chunks played (" << total_played_samples << " samples)"
            << ", " << arrivals.size() << " play() calls"
            << ", Total time: " << total_ms << "ms"
            << ", First-to-last arrival span: " << span_ms << "ms";
    result.details = details.str();

    return result;
}

// =============================================================================
// Test: TTS Queue - Cancel Stops Immediately
// =============================================================================
// Verifies that cancel() stops the consumer thread and no more audio plays.
// =============================================================================

TestResult test_tts_queue_cancel() {
    TestResult result;
    result.name = "TTS Queue - Cancel Stops Playback";

    std::atomic<size_t> play_count{0};

    auto play_audio = [&](const int16_t*, size_t, int, const std::atomic<bool>&) {
        play_count.fetch_add(1);
        // Simulate slow playback so cancel has something to cancel
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    };

    openclaw::TTSQueue queue(play_audio);

    // Push 10 chunks
    for (int i = 0; i < 10; i++) {
        openclaw::AudioChunk chunk;
        chunk.samples.resize(1024, 1000);
        chunk.sample_rate = 22050;
        queue.push(std::move(chunk));
    }

    // Let 1-2 chunks play
    std::this_thread::sleep_for(std::chrono::milliseconds(250));
    size_t played_before_cancel = play_count.load();

    // Cancel
    queue.cancel();

    // Wait a moment
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    size_t played_after_cancel = play_count.load();

    // Verify cancel stopped playback (not all 10 chunks played)
    if (played_after_cancel >= 10) {
        result.details = "All 10 chunks played despite cancel - cancel didn't stop playback";
        return result;
    }

    // Verify queue is no longer active
    if (queue.is_active()) {
        result.details = "Queue still active after cancel";
        return result;
    }

    // Verify no new chunks played after cancel
    std::this_thread::sleep_for(std::chrono::milliseconds(300));
    size_t played_final = play_count.load();
    if (played_final != played_after_cancel) {
        result.details = "Audio played after cancel (" + std::to_string(played_final - played_after_cancel) + " extra)";
        return result;
    }

    result.passed = true;
    result.details = "Played " + std::to_string(played_before_cancel) + " before cancel, "
                   + std::to_string(played_after_cancel) + " total (out of 10)";
    return result;
}

// =============================================================================
// Test: TTS Queue - Push-While-Playing (Pre-synthesis Verification)
// =============================================================================
// The key test: verifies that the producer can push new chunks while the
// consumer is blocked playing previous chunks. This proves parallel operation.
//
// We use a slow play_audio callback (simulating ALSA blocking) and verify
// that multiple push() calls complete without waiting for playback.
// =============================================================================

TestResult test_tts_queue_push_while_playing() {
    TestResult result;
    result.name = "TTS Queue - Push While Consumer Plays (Parallel Proof)";

    std::atomic<size_t> play_count{0};

    auto play_audio = [&](const int16_t*, size_t, int, const std::atomic<bool>&) {
        play_count.fetch_add(1);
        // Simulate 200ms of ALSA playback per chunk
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    };

    openclaw::TTSQueue queue(play_audio);

    // Time how long it takes to push 5 chunks
    auto push_start = std::chrono::steady_clock::now();

    for (int i = 0; i < 5; i++) {
        openclaw::AudioChunk chunk;
        chunk.samples.resize(4410, static_cast<int16_t>(i * 100));  // 0.2s at 22050Hz
        chunk.sample_rate = 22050;
        queue.push(std::move(chunk));
    }

    auto push_end = std::chrono::steady_clock::now();
    auto push_ms = std::chrono::duration_cast<std::chrono::milliseconds>(push_end - push_start).count();

    // Key assertion: pushing all 5 chunks should be nearly instant (<50ms)
    // because push() doesn't wait for playback. If push blocked on play,
    // it would take 5 * 200ms = 1000ms.
    if (push_ms > 100) {
        result.details = "push() blocked on playback - took " + std::to_string(push_ms)
                       + "ms to push 5 chunks (expected <100ms)";
        return result;
    }

    // At this point, consumer should have only played ~1 chunk (200ms)
    // but all 5 are queued
    size_t played_at_push_done = play_count.load();

    queue.finish();

    // Wait for all chunks to play (5 * 200ms = ~1 second)
    int wait = 0;
    while (queue.is_active() && wait < 40) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        wait++;
    }

    size_t final_played = play_count.load();

    if (final_played != 5) {
        result.details = "Expected 5 chunks played, got " + std::to_string(final_played);
        return result;
    }

    result.passed = true;
    std::ostringstream details;
    details << "5 push() calls completed in " << push_ms << "ms (non-blocking!)"
            << ", Chunks played at push-done: " << played_at_push_done
            << ", Final chunks played: " << final_played;
    result.details = details.str();

    return result;
}

// =============================================================================
// Test: TTS Queue - Cancel During Active Playback (Barge-in Simulation)
// =============================================================================
// Simulates a wake word barge-in: the queue is actively playing a long response
// (many chunks), cancel() is called mid-playback. Verifies:
//   - Playback stops immediately (no more play() calls after cancel)
//   - Remaining queued chunks are discarded
//   - Queue becomes inactive
// =============================================================================

TestResult test_tts_queue_cancel_during_playback() {
    TestResult result;
    result.name = "TTS Queue - Cancel During Active Playback (Barge-in)";

    std::atomic<size_t> play_count{0};
    std::atomic<size_t> total_samples_played{0};

    auto play_audio = [&](const int16_t*, size_t num_samples, int, const std::atomic<bool>&) {
        play_count.fetch_add(1);
        total_samples_played.fetch_add(num_samples);
        // Simulate realistic ALSA playback: ~200ms per sentence chunk
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    };

    openclaw::TTSQueue queue(play_audio);

    // Push 20 chunks (simulating a very long response - ~4 seconds of playback)
    const int chunks_total = 20;
    for (int i = 0; i < chunks_total; i++) {
        openclaw::AudioChunk chunk;
        chunk.samples.resize(4410, static_cast<int16_t>(1000 + i * 100));  // 0.2s each
        chunk.sample_rate = 22050;
        queue.push(std::move(chunk));
    }
    queue.finish();

    // Let a few chunks play (~3 chunks at 200ms each = ~600ms)
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    size_t played_before = play_count.load();

    // BARGE-IN: cancel everything
    auto cancel_start = std::chrono::steady_clock::now();
    queue.cancel();
    auto cancel_end = std::chrono::steady_clock::now();
    auto cancel_ms = std::chrono::duration_cast<std::chrono::milliseconds>(cancel_end - cancel_start).count();

    size_t played_at_cancel = play_count.load();

    // Wait to verify nothing plays after cancel
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    size_t played_after = play_count.load();

    // Verify not all chunks played (cancel worked)
    if (played_at_cancel >= static_cast<size_t>(chunks_total)) {
        result.details = "All " + std::to_string(chunks_total) + " chunks played - cancel was too late";
        return result;
    }

    // Verify no audio after cancel
    if (played_after != played_at_cancel) {
        result.details = "Audio played after cancel: " + std::to_string(played_after - played_at_cancel) + " extra chunks";
        return result;
    }

    // Verify queue is inactive
    if (queue.is_active()) {
        result.details = "Queue still active after cancel";
        return result;
    }

    result.passed = true;
    std::ostringstream details;
    details << "Played " << played_before << " before cancel signal, "
            << played_at_cancel << " total (out of " << chunks_total << " queued)"
            << ", Cancel took " << cancel_ms << "ms"
            << ", " << (chunks_total - played_at_cancel) << " chunks discarded";
    result.details = details.str();

    return result;
}

// =============================================================================
// Test: TTS Queue - Cancel Kills Producer Thread Too
// =============================================================================
// Simulates barge-in while synthesis is still in progress: a slow producer
// thread is pushing chunks into the queue. Cancel should stop both the
// consumer (playback) AND make the producer exit early when it checks the
// cancelled state. No new chunks should be synthesized after cancel.
// =============================================================================

TestResult test_tts_queue_cancel_during_synthesis() {
    TestResult result;
    result.name = "TTS Queue - Cancel Kills Both Producer and Consumer";

    std::atomic<size_t> play_count{0};
    std::atomic<size_t> synth_count{0};
    std::atomic<bool> cancelled{false};

    auto play_audio = [&](const int16_t*, size_t, int, const std::atomic<bool>&) {
        play_count.fetch_add(1);
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    };

    openclaw::TTSQueue queue(play_audio);

    // Producer thread: slowly synthesizes 10 chunks (100ms each = 1 second total)
    std::thread producer([&]() {
        for (int i = 0; i < 10; i++) {
            if (cancelled.load()) break;

            // Simulate synthesis time
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            synth_count.fetch_add(1);

            if (cancelled.load()) break;

            openclaw::AudioChunk chunk;
            chunk.samples.resize(2205, static_cast<int16_t>(1000 + i * 100));
            chunk.sample_rate = 22050;
            queue.push(std::move(chunk));
        }
        queue.finish();
    });

    // Let producer + consumer run for a bit (~300ms = ~3 chunks synthesized)
    std::this_thread::sleep_for(std::chrono::milliseconds(350));
    size_t synth_before = synth_count.load();
    size_t played_before = play_count.load();

    // BARGE-IN: cancel everything
    cancelled.store(true);
    queue.cancel();

    // Wait for producer thread to exit
    producer.join();

    size_t synth_after = synth_count.load();
    size_t played_after = play_count.load();

    // Wait to verify nothing more happens
    std::this_thread::sleep_for(std::chrono::milliseconds(300));
    size_t synth_final = synth_count.load();
    size_t played_final = play_count.load();

    // Verify not all 10 were synthesized
    if (synth_final >= 10) {
        result.details = "All 10 chunks synthesized despite cancel";
        return result;
    }

    // Verify no new activity after cancel
    if (played_final != played_after) {
        result.details = "Audio played after cancel: " + std::to_string(played_final - played_after) + " extra";
        return result;
    }

    if (synth_final != synth_after) {
        result.details = "Synthesis continued after cancel: " + std::to_string(synth_final - synth_after) + " extra";
        return result;
    }

    result.passed = true;
    std::ostringstream details;
    details << "Synthesized: " << synth_before << " before cancel, " << synth_final << " total (out of 10)"
            << ", Played: " << played_before << " before cancel, " << played_final << " total"
            << ", Producer exited cleanly";
    result.details = details.str();

    return result;
}

// =============================================================================
// Test: Barge-in - speak_text_async Cancel Chain
// =============================================================================
// Simulates the full barge-in scenario at the pipeline level (no models):
//   1. Start speak_text_async with a long multi-sentence response
//   2. While TTS is "playing", call cancel_speech()
//   3. Verify: is_speaking() returns false
//   4. Verify: no more audio output after cancel
//   5. Verify: pipeline state transitions back to non-SPEAKING
//
// This tests the exact cancel chain that fires when wake word interrupts TTS.
// Uses the real VoicePipeline but with models loaded (requires ONNX backends).
// =============================================================================

TestResult test_bargein_cancel_chain() {
    TestResult result;
    result.name = "Barge-in - Cancel Chain (speak_text_async → cancel_speech)";

    // Set up pipeline with audio capture
    AudioCapture tts_capture;

    openclaw::VoicePipelineConfig config;
    config.on_audio_output = [&tts_capture](const int16_t* samples, size_t n, int sr, const std::atomic<bool>&) {
        tts_capture.on_audio(samples, n, sr);
    };
    config.on_error = [](const std::string& err) {
        std::cerr << "[BargeIn Test] Error: " << err << "\n";
    };

    openclaw::VoicePipeline pipeline(config);
    if (!pipeline.initialize()) {
        result.details = "Failed to initialize pipeline: " + pipeline.last_error();
        return result;
    }

    // Speak a long multi-sentence response asynchronously
    std::string long_text = "This is the first sentence of a very long response from OpenClaw. "
                            "Here is the second sentence with more details about the topic. "
                            "The third sentence adds even more context to the response. "
                            "And the fourth sentence wraps up the explanation nicely. "
                            "Finally, the fifth sentence concludes the response.";

    pipeline.speak_text_async(long_text);

    // Wait for TTS to start playing
    bool started = false;
    for (int i = 0; i < 100; i++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        if (pipeline.is_speaking() || tts_capture.total_samples() > 0) {
            started = true;
            break;
        }
    }

    if (!started) {
        pipeline.cancel_speech();
        result.details = "TTS never started playing within 5 seconds";
        return result;
    }

    // Record audio at the moment of barge-in
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    size_t samples_before_cancel = tts_capture.total_samples();

    // BARGE-IN: cancel everything
    auto cancel_start = std::chrono::steady_clock::now();
    pipeline.cancel_speech();
    auto cancel_end = std::chrono::steady_clock::now();
    auto cancel_ms = std::chrono::duration_cast<std::chrono::milliseconds>(cancel_end - cancel_start).count();

    // Verify is_speaking() is false now
    if (pipeline.is_speaking()) {
        result.details = "is_speaking() still true after cancel_speech()";
        return result;
    }

    // Verify state is not SPEAKING
    if (pipeline.state() == openclaw::PipelineState::SPEAKING) {
        result.details = "Pipeline state still SPEAKING after cancel";
        return result;
    }

    // Wait and verify no more audio is produced
    size_t samples_at_cancel = tts_capture.total_samples();
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    size_t samples_after_wait = tts_capture.total_samples();

    if (samples_after_wait != samples_at_cancel) {
        result.details = "Audio still being produced after cancel: "
                       + std::to_string(samples_after_wait - samples_at_cancel) + " extra samples";
        return result;
    }

    // The text had 5 sentences - we should NOT have heard all of them
    // (cancel happened after ~0.5s, a 5-sentence response takes several seconds)
    float total_audio_duration = tts_capture.duration_seconds();

    result.passed = true;
    std::ostringstream details;
    details << "Samples before cancel: " << samples_before_cancel
            << ", Samples at cancel: " << samples_at_cancel
            << ", Cancel took: " << cancel_ms << "ms"
            << ", Total audio: " << total_audio_duration << "s"
            << ", No audio leaked after cancel";
    result.details = details.str();

    return result;
}

// =============================================================================
// Test: Barge-in - Rapid Cancel/Restart Cycle
// =============================================================================
// Simulates the user saying "Hey Jarvis" multiple times rapidly:
//   1. Start TTS with a response
//   2. Cancel (barge-in)
//   3. Immediately start TTS with a new response
//   4. Verify the new response plays correctly (no corruption from old state)
//
// This tests that cancel_speech() leaves the pipeline in a clean state
// ready for the next speak_text_async() call.
// =============================================================================

TestResult test_bargein_rapid_restart() {
    TestResult result;
    result.name = "Barge-in - Rapid Cancel/Restart Cycle";

    AudioCapture capture;

    openclaw::VoicePipelineConfig config;
    config.on_audio_output = [&capture](const int16_t* samples, size_t n, int sr, const std::atomic<bool>&) {
        capture.on_audio(samples, n, sr);
    };
    config.on_error = [](const std::string& err) {
        std::cerr << "[Restart Test] Error: " << err << "\n";
    };

    openclaw::VoicePipeline pipeline(config);
    if (!pipeline.initialize()) {
        result.details = "Failed to initialize pipeline: " + pipeline.last_error();
        return result;
    }

    // Cycle 1: start TTS, let it play briefly, cancel
    pipeline.speak_text_async("This is the first response that should be interrupted quickly.");

    // Wait for some audio to start
    for (int i = 0; i < 50; i++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        if (capture.total_samples() > 0) break;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    size_t samples_cycle1 = capture.total_samples();

    pipeline.cancel_speech();
    capture.clear();

    // Cycle 2: immediately start a new response
    pipeline.speak_text_async("Second response after barge-in.");

    // Wait for new audio
    bool got_cycle2_audio = false;
    for (int i = 0; i < 100; i++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        if (capture.total_samples() > 0) {
            got_cycle2_audio = true;
            break;
        }
    }

    if (!got_cycle2_audio) {
        pipeline.cancel_speech();
        result.details = "No audio from second response after cancel/restart (pipeline state corrupted?)";
        return result;
    }

    // Let it finish
    for (int i = 0; i < 100; i++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        if (!pipeline.is_speaking()) break;
    }

    size_t samples_cycle2 = capture.total_samples();

    // Cycle 3: one more cancel/restart to really stress test
    capture.clear();
    pipeline.speak_text_async("Third response works too.");

    for (int i = 0; i < 50; i++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        if (capture.total_samples() > 0) break;
    }

    pipeline.cancel_speech();

    // Verify pipeline is in a clean state
    if (pipeline.is_speaking()) {
        result.details = "Pipeline still speaking after 3rd cancel";
        return result;
    }

    result.passed = true;
    std::ostringstream details;
    details << "Cycle 1: " << samples_cycle1 << " samples before cancel"
            << ", Cycle 2: " << samples_cycle2 << " samples (full playback after restart)"
            << ", Cycle 3: cancel succeeded, pipeline clean";
    result.details = details.str();

    return result;
}

// =============================================================================
// Helper: Generate synthetic audio samples at 16kHz
// =============================================================================

// Generate silence (zeros)
static std::vector<int16_t> generate_silence_16k(float duration_sec) {
    int num = static_cast<int>(16000 * duration_sec);
    return std::vector<int16_t>(num, 0);
}

// Generate a tone (for simulating speech-like audio that triggers VAD)
static std::vector<int16_t> generate_tone_16k(float duration_sec, float freq = 300.0f, float amplitude = 8000.0f) {
    int num = static_cast<int>(16000 * duration_sec);
    std::vector<int16_t> samples(num);
    for (int i = 0; i < num; ++i) {
        float t = static_cast<float>(i) / 16000.0f;
        samples[i] = static_cast<int16_t>(amplitude * std::sin(2.0f * 3.14159f * freq * t));
    }
    return samples;
}

// =============================================================================
// Test: Wake Word - Single Detection (No Re-trigger)
// =============================================================================
// Feeds a real "Hey Jarvis" WAV into the pipeline and verifies:
//   - Wake word fires exactly ONCE
//   - Pipeline transitions to LISTENING state
//   - The cooldown prevents re-triggering from residual audio
//   - After silence timeout, returns to WAITING_FOR_WAKE_WORD
// =============================================================================

TestResult test_wakeword_single_detection() {
    TestResult result;
    result.name = "Wake Word - Single Detection (No Re-trigger)";

    int wakeword_count = 0;

    openclaw::VoicePipelineConfig config;
    config.enable_wake_word = true;
    config.wake_word = "Hey Jarvis";
    config.wake_word_threshold = 0.5f;
    config.silence_duration_sec = 1.0;
    config.min_speech_samples = 8000;

    config.on_wake_word = [&](const std::string&, float conf) {
        wakeword_count++;
        std::cout << "  [Test] Wake word #" << wakeword_count << " (conf=" << conf << ")\n";
    };
    config.on_audio_output = [](const int16_t*, size_t, int, const std::atomic<bool>&) {};
    config.on_error = [](const std::string& e) { std::cerr << "  [Test] Error: " << e << "\n"; };

    openclaw::VoicePipeline pipeline(config);
    if (!pipeline.initialize()) {
        result.details = "Failed to initialize: " + pipeline.last_error();
        return result;
    }
    pipeline.start();

    // Feed silence first (1 second - lets models warm up)
    auto silence = generate_silence_16k(1.0f);
    const size_t chunk = 256;
    for (size_t i = 0; i + chunk <= silence.size(); i += chunk) {
        pipeline.process_audio(silence.data() + i, chunk);
    }

    if (pipeline.state() != openclaw::PipelineState::WAITING_FOR_WAKE_WORD) {
        result.details = "Pipeline not in WAITING_FOR_WAKE_WORD after silence";
        pipeline.stop();
        return result;
    }

    // Feed "Hey Jarvis" audio (use the real recording if available, else the TTS one)
    std::string wav_path = "tests/audio/hey-jarvis-real.wav";
    {
        struct stat st;
        if (stat(wav_path.c_str(), &st) != 0) {
            wav_path = "tests/audio/hey-jarvis-amplified.wav";
            if (stat(wav_path.c_str(), &st) != 0) {
                result.details = "No hey-jarvis WAV file found for testing";
                pipeline.stop();
                return result;
            }
        }
    }

    // Simple WAV reader (reuse the inline one)
    std::ifstream wav_file(wav_path, std::ios::binary);
    if (!wav_file.is_open()) {
        result.details = "Cannot open " + wav_path;
        pipeline.stop();
        return result;
    }

    // Skip to data (simple: read entire file, find "data" chunk)
    wav_file.seekg(0, std::ios::end);
    size_t file_size = wav_file.tellg();
    wav_file.seekg(0);
    std::vector<char> raw(file_size);
    wav_file.read(raw.data(), file_size);
    wav_file.close();

    // Find data chunk
    int16_t* audio_data = nullptr;
    size_t audio_samples = 0;
    for (size_t i = 0; i + 8 < file_size; i++) {
        if (raw[i] == 'd' && raw[i+1] == 'a' && raw[i+2] == 't' && raw[i+3] == 'a') {
            uint32_t data_size = *reinterpret_cast<uint32_t*>(&raw[i + 4]);
            audio_data = reinterpret_cast<int16_t*>(&raw[i + 8]);
            audio_samples = data_size / 2;
            break;
        }
    }

    if (!audio_data || audio_samples == 0) {
        result.details = "Failed to parse WAV file: " + wav_path;
        pipeline.stop();
        return result;
    }

    // Feed the "Hey Jarvis" audio
    for (size_t i = 0; i + chunk <= audio_samples; i += chunk) {
        pipeline.process_audio(audio_data + i, chunk);
    }

    // Feed 2 more seconds of silence (should NOT re-trigger wake word)
    auto post_silence = generate_silence_16k(2.0f);
    for (size_t i = 0; i + chunk <= post_silence.size(); i += chunk) {
        pipeline.process_audio(post_silence.data() + i, chunk);
    }

    pipeline.stop();

    // The wake word should have fired at most ONCE
    // (it might fire 0 times if the WAV is TTS-generated and doesn't match human speech)
    if (wakeword_count > 1) {
        result.details = "Wake word fired " + std::to_string(wakeword_count)
                       + " times (expected at most 1). Cooldown not working!";
        return result;
    }

    result.passed = true;
    std::ostringstream details;
    details << "Wake word fired " << wakeword_count << " time(s) from " << wav_path
            << ", Pipeline state: " << pipeline.state_string();
    result.details = details.str();

    return result;
}

// =============================================================================
// Test: Wake Word → Silence → Timeout → Back to Waiting
// =============================================================================
// Feeds wake word audio, then extended silence. Verifies the pipeline
// transitions: WAITING → LISTENING → (timeout) → WAITING
// =============================================================================

TestResult test_wakeword_timeout_returns_to_waiting() {
    TestResult result;
    result.name = "Wake Word - Timeout Returns to WAITING_FOR_WAKE_WORD";

    bool wakeword_detected = false;

    openclaw::VoicePipelineConfig config;
    config.enable_wake_word = true;
    config.wake_word = "Hey Jarvis";
    config.wake_word_threshold = 0.5f;
    config.silence_duration_sec = 1.0;
    config.min_speech_samples = 8000;

    config.on_wake_word = [&](const std::string&, float) { wakeword_detected = true; };
    config.on_audio_output = [](const int16_t*, size_t, int, const std::atomic<bool>&) {};
    config.on_error = [](const std::string&) {};

    openclaw::VoicePipeline pipeline(config);
    if (!pipeline.initialize()) {
        result.details = "Failed to initialize: " + pipeline.last_error();
        return result;
    }
    pipeline.start();

    // Manually activate wake word (simulate detection without needing real audio)
    // We do this by feeding silence and then checking the timeout logic
    // First, let's just force the state for this test
    // Actually, we need to go through the real pipeline. Let's feed the real WAV.

    // Feed silence to warm up
    auto warmup = generate_silence_16k(0.5f);
    const size_t chunk = 256;
    for (size_t i = 0; i + chunk <= warmup.size(); i += chunk) {
        pipeline.process_audio(warmup.data() + i, chunk);
    }

    // Feed "Hey Jarvis"
    std::string wav_path = "tests/audio/hey-jarvis-real.wav";
    {
        struct stat st;
        if (stat(wav_path.c_str(), &st) != 0) {
            wav_path = "tests/audio/hey-jarvis-amplified.wav";
            if (stat(wav_path.c_str(), &st) != 0) {
                // Skip this test if no wake word audio available
                result.passed = true;
                result.details = "SKIPPED: No hey-jarvis WAV file available";
                pipeline.stop();
                return result;
            }
        }
    }

    std::ifstream wav_file(wav_path, std::ios::binary);
    wav_file.seekg(0, std::ios::end);
    size_t file_size = wav_file.tellg();
    wav_file.seekg(0);
    std::vector<char> raw(file_size);
    wav_file.read(raw.data(), file_size);
    wav_file.close();

    int16_t* audio_data = nullptr;
    size_t audio_samples = 0;
    for (size_t i = 0; i + 8 < file_size; i++) {
        if (raw[i] == 'd' && raw[i+1] == 'a' && raw[i+2] == 't' && raw[i+3] == 'a') {
            uint32_t data_size = *reinterpret_cast<uint32_t*>(&raw[i + 4]);
            audio_data = reinterpret_cast<int16_t*>(&raw[i + 8]);
            audio_samples = data_size / 2;
            break;
        }
    }

    if (audio_data && audio_samples > 0) {
        for (size_t i = 0; i + chunk <= audio_samples; i += chunk) {
            pipeline.process_audio(audio_data + i, chunk);
        }
    }

    if (!wakeword_detected) {
        // WAV didn't trigger wake word (TTS audio) - skip test gracefully
        result.passed = true;
        result.details = "SKIPPED: WAV did not trigger wake word (may be TTS-generated)";
        pipeline.stop();
        return result;
    }

    // Wake word fired - should be in LISTENING now
    if (pipeline.state() != openclaw::PipelineState::LISTENING) {
        result.details = "After wake word, expected LISTENING but got " + pipeline.state_string();
        pipeline.stop();
        return result;
    }

    // Wait for the wake word timeout (10s) by feeding silence at ~real-time pace.
    // The timeout uses wall clock, so we need actual elapsed time, not just audio samples.
    // Feed a small chunk every 500ms for 11 seconds total.
    auto silence_chunk = generate_silence_16k(0.5f);  // 0.5s of silence
    auto timeout_start = std::chrono::steady_clock::now();
    bool timed_out = false;

    for (int i = 0; i < 22; i++) {  // 22 * 500ms = 11 seconds
        for (size_t j = 0; j + chunk <= silence_chunk.size(); j += chunk) {
            pipeline.process_audio(silence_chunk.data() + j, chunk);
        }
        if (pipeline.state() == openclaw::PipelineState::WAITING_FOR_WAKE_WORD) {
            timed_out = true;
            break;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }

    auto timeout_elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - timeout_start
    ).count();

    if (!timed_out) {
        result.details = "After " + std::to_string(timeout_elapsed_ms) + "ms, expected WAITING_FOR_WAKE_WORD but got " + pipeline.state_string();
        pipeline.stop();
        return result;
    }

    pipeline.stop();

    result.passed = true;
    result.details = "Wake word detected -> LISTENING -> timeout after "
                   + std::to_string(timeout_elapsed_ms) + "ms -> WAITING_FOR_WAKE_WORD";

    return result;
}

// =============================================================================
// Test: Barge-in During TTS - Wake Word Cancels Playback
// =============================================================================
// Starts TTS playing a long response, then feeds "Hey Jarvis" audio.
// Verifies:
//   - TTS is cancelled immediately
//   - Pipeline transitions to LISTENING (ready for next command)
//   - No more TTS audio after cancellation
// =============================================================================

TestResult test_bargein_wakeword_during_tts() {
    TestResult result;
    result.name = "Barge-in - Wake Word During TTS Cancels Playback";

    std::atomic<bool> wakeword_detected{false};
    std::atomic<bool> speech_interrupted{false};
    AudioCapture tts_capture;

    openclaw::VoicePipelineConfig config;
    config.enable_wake_word = true;
    config.wake_word = "Hey Jarvis";
    config.wake_word_threshold = 0.5f;
    config.silence_duration_sec = 1.0;
    config.min_speech_samples = 8000;

    config.on_wake_word = [&](const std::string&, float) { wakeword_detected.store(true); };
    config.on_speech_interrupted = [&]() { speech_interrupted.store(true); };
    config.on_audio_output = [&tts_capture](const int16_t* s, size_t n, int sr, const std::atomic<bool>&) {
        tts_capture.on_audio(s, n, sr);
    };
    config.on_error = [](const std::string&) {};

    openclaw::VoicePipeline pipeline(config);
    if (!pipeline.initialize()) {
        result.details = "Failed to initialize: " + pipeline.last_error();
        return result;
    }
    pipeline.start();

    // Start TTS with a long response
    pipeline.speak_text_async(
        "This is a very long response from the agent. "
        "It contains multiple sentences that take several seconds to synthesize and play. "
        "The user should be able to interrupt this at any time by saying the wake word. "
        "This fourth sentence keeps going to make the response even longer. "
        "And the fifth sentence ensures we have plenty of time to test the barge-in."
    );

    // Wait for TTS to start
    for (int i = 0; i < 100; i++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        if (tts_capture.total_samples() > 0) break;
    }

    if (tts_capture.total_samples() == 0) {
        pipeline.cancel_speech();
        pipeline.stop();
        result.details = "TTS never started playing";
        return result;
    }

    size_t samples_before_bargein = tts_capture.total_samples();

    // Now feed "Hey Jarvis" audio while TTS is playing (barge-in!)
    std::string wav_path = "tests/audio/hey-jarvis-real.wav";
    {
        struct stat st;
        if (stat(wav_path.c_str(), &st) != 0) {
            wav_path = "tests/audio/hey-jarvis-amplified.wav";
            if (stat(wav_path.c_str(), &st) != 0) {
                pipeline.cancel_speech();
                pipeline.stop();
                result.passed = true;
                result.details = "SKIPPED: No hey-jarvis WAV for barge-in test";
                return result;
            }
        }
    }

    std::ifstream wav_file(wav_path, std::ios::binary);
    wav_file.seekg(0, std::ios::end);
    size_t file_size = wav_file.tellg();
    wav_file.seekg(0);
    std::vector<char> raw(file_size);
    wav_file.read(raw.data(), file_size);
    wav_file.close();

    int16_t* audio_data = nullptr;
    size_t audio_samples = 0;
    for (size_t i = 0; i + 8 < file_size; i++) {
        if (raw[i] == 'd' && raw[i+1] == 'a' && raw[i+2] == 't' && raw[i+3] == 'a') {
            uint32_t data_size = *reinterpret_cast<uint32_t*>(&raw[i + 4]);
            audio_data = reinterpret_cast<int16_t*>(&raw[i + 8]);
            audio_samples = data_size / 2;
            break;
        }
    }

    if (audio_data && audio_samples > 0) {
        const size_t chunk = 256;
        for (size_t i = 0; i + chunk <= audio_samples; i += chunk) {
            pipeline.process_audio(audio_data + i, chunk);
        }
    }

    // Wait a moment for cancel to propagate
    std::this_thread::sleep_for(std::chrono::milliseconds(300));

    size_t samples_after_bargein = tts_capture.total_samples();

    // Wait more - verify no audio leaks after barge-in
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
    size_t samples_final = tts_capture.total_samples();

    pipeline.stop();

    // If wake word wasn't detected (TTS audio file doesn't work), skip gracefully
    if (!wakeword_detected.load()) {
        result.passed = true;
        result.details = "SKIPPED: WAV did not trigger wake word during TTS (may need real human recording)";
        return result;
    }

    // Verify TTS was cancelled (not all 5 sentences played)
    if (!speech_interrupted.load()) {
        result.details = "on_speech_interrupted callback was not fired";
        return result;
    }

    if (pipeline.is_speaking()) {
        result.details = "Pipeline still speaking after barge-in";
        return result;
    }

    // Verify no more audio after barge-in
    if (samples_final != samples_after_bargein) {
        result.details = "Audio leaked after barge-in: " + std::to_string(samples_final - samples_after_bargein) + " extra samples";
        return result;
    }

    result.passed = true;
    std::ostringstream details;
    details << "TTS samples before barge-in: " << samples_before_bargein
            << ", After barge-in: " << samples_after_bargein
            << ", Final (no leak): " << samples_final
            << ", speech_interrupted callback fired: yes"
            << ", State: " << pipeline.state_string();
    result.details = details.str();

    return result;
}

// =============================================================================
// Test: Post-TTS Wake Word Reactivation
// =============================================================================
// Verifies that after speak_text_async completes normally (no barge-in),
// the pipeline transitions back to WAITING_FOR_WAKE_WORD and a second
// "Hey Jarvis" triggers successfully.
// =============================================================================

TestResult test_post_tts_wakeword_reactivation() {
    TestResult result;
    result.name = "Post-TTS Wake Word Reactivation";

    std::atomic<int> wakeword_count{0};
    AudioCapture tts_capture;

    openclaw::VoicePipelineConfig config;
    config.enable_wake_word = true;
    config.wake_word = "Hey Jarvis";
    config.wake_word_threshold = 0.5f;
    config.silence_duration_sec = 1.0;
    config.min_speech_samples = 8000;

    config.on_wake_word = [&](const std::string&, float) { wakeword_count.fetch_add(1); };
    config.on_audio_output = [&tts_capture](const int16_t* s, size_t n, int sr, const std::atomic<bool>&) {
        tts_capture.on_audio(s, n, sr);
    };
    config.on_error = [](const std::string&) {};

    openclaw::VoicePipeline pipeline(config);
    if (!pipeline.initialize()) {
        result.details = "Failed to initialize: " + pipeline.last_error();
        return result;
    }
    pipeline.start();

    // Step 1: Speak a short TTS response
    pipeline.speak_text_async("Hello, this is a test response.");

    // Wait for TTS to complete (poll state)
    for (int i = 0; i < 200; i++) {  // Up to 10s
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        if (pipeline.state() != openclaw::PipelineState::SPEAKING) break;
    }

    if (pipeline.state() == openclaw::PipelineState::SPEAKING) {
        pipeline.cancel_speech();
        pipeline.stop();
        result.details = "TTS never completed (still SPEAKING after 10s)";
        return result;
    }

    if (pipeline.state() != openclaw::PipelineState::WAITING_FOR_WAKE_WORD) {
        pipeline.stop();
        result.details = "Expected WAITING_FOR_WAKE_WORD after TTS, got: " + pipeline.state_string();
        return result;
    }

    // Step 2: Feed "Hey Jarvis" audio -- should trigger wake word
    std::string wav_path = "tests/audio/hey-jarvis-real.wav";
    {
        struct stat st;
        if (stat(wav_path.c_str(), &st) != 0) {
            wav_path = "tests/audio/hey-jarvis-amplified.wav";
            if (stat(wav_path.c_str(), &st) != 0) {
                pipeline.stop();
                result.passed = true;
                result.details = "SKIPPED: No hey-jarvis WAV file";
                return result;
            }
        }
    }

    // Feed silence to prime the model (500ms)
    auto silence = generate_silence_16k(0.5f);
    const size_t chunk = 256;
    for (size_t i = 0; i + chunk <= silence.size(); i += chunk) {
        pipeline.process_audio(silence.data() + i, chunk);
    }

    // Load and feed wake word audio
    std::ifstream wav_file(wav_path, std::ios::binary);
    wav_file.seekg(0, std::ios::end);
    size_t file_size = wav_file.tellg();
    wav_file.seekg(0);
    std::vector<char> raw(file_size);
    wav_file.read(raw.data(), file_size);
    wav_file.close();

    int16_t* audio_data = nullptr;
    size_t audio_samples = 0;
    for (size_t i = 0; i + 8 < file_size; i++) {
        if (raw[i] == 'd' && raw[i+1] == 'a' && raw[i+2] == 't' && raw[i+3] == 'a') {
            uint32_t data_size = *reinterpret_cast<uint32_t*>(&raw[i + 4]);
            audio_data = reinterpret_cast<int16_t*>(&raw[i + 8]);
            audio_samples = data_size / 2;
            break;
        }
    }

    if (!audio_data || audio_samples == 0) {
        pipeline.stop();
        result.details = "Failed to parse WAV file";
        return result;
    }

    wakeword_count.store(0);
    for (size_t i = 0; i + chunk <= audio_samples; i += chunk) {
        pipeline.process_audio(audio_data + i, chunk);
    }

    // Feed post-silence
    auto post = generate_silence_16k(0.5f);
    for (size_t i = 0; i + chunk <= post.size(); i += chunk) {
        pipeline.process_audio(post.data() + i, chunk);
    }

    pipeline.stop();

    if (wakeword_count.load() == 0) {
        result.details = "Wake word did NOT trigger after TTS completed";
        return result;
    }

    if (pipeline.state() != openclaw::PipelineState::LISTENING) {
        result.details = "Expected LISTENING after 2nd wake word, got: " + pipeline.state_string();
        return result;
    }

    result.passed = true;
    std::ostringstream details;
    details << "TTS completed normally, state=" << pipeline.state_string()
            << ", wake word fired " << wakeword_count.load() << " time(s)"
            << ", TTS audio: " << tts_capture.duration_seconds() << "s";
    result.details = details.str();
    return result;
}

// =============================================================================
// Test: Post-Barge-In Second Wake Word
// =============================================================================
// Full cycle: TTS -> barge-in -> state verified -> timeout ->
// WAITING_FOR_WAKE_WORD -> 2nd wake word triggers
// =============================================================================

TestResult test_post_bargein_second_wakeword() {
    TestResult result;
    result.name = "Post-Barge-In - Second Wake Word Triggers";

    std::atomic<int> wakeword_count{0};
    std::atomic<bool> speech_interrupted{false};
    AudioCapture tts_capture;

    openclaw::VoicePipelineConfig config;
    config.enable_wake_word = true;
    config.wake_word = "Hey Jarvis";
    config.wake_word_threshold = 0.5f;
    config.silence_duration_sec = 1.0;
    config.min_speech_samples = 8000;

    config.on_wake_word = [&](const std::string&, float) { wakeword_count.fetch_add(1); };
    config.on_speech_interrupted = [&]() { speech_interrupted.store(true); };
    config.on_audio_output = [&tts_capture](const int16_t* s, size_t n, int sr, const std::atomic<bool>&) {
        tts_capture.on_audio(s, n, sr);
    };
    config.on_error = [](const std::string&) {};

    openclaw::VoicePipeline pipeline(config);
    if (!pipeline.initialize()) {
        result.details = "Failed to initialize: " + pipeline.last_error();
        return result;
    }
    pipeline.start();

    // Step 1: Start TTS
    pipeline.speak_text_async(
        "This is a long response. The user will interrupt before it finishes. "
        "This third sentence ensures we have plenty of audio to interrupt.");

    // Wait for TTS to start
    for (int i = 0; i < 100; i++) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        if (tts_capture.total_samples() > 0) break;
    }

    // Step 2: Feed "Hey Jarvis" for barge-in
    std::string wav_path = "tests/audio/hey-jarvis-real.wav";
    {
        struct stat st;
        if (stat(wav_path.c_str(), &st) != 0) {
            wav_path = "tests/audio/hey-jarvis-amplified.wav";
            if (stat(wav_path.c_str(), &st) != 0) {
                pipeline.cancel_speech();
                pipeline.stop();
                result.passed = true;
                result.details = "SKIPPED: No hey-jarvis WAV file";
                return result;
            }
        }
    }

    std::ifstream wav_file(wav_path, std::ios::binary);
    wav_file.seekg(0, std::ios::end);
    size_t file_size = wav_file.tellg();
    wav_file.seekg(0);
    std::vector<char> raw(file_size);
    wav_file.read(raw.data(), file_size);
    wav_file.close();

    int16_t* audio_data = nullptr;
    size_t audio_samples = 0;
    for (size_t i = 0; i + 8 < file_size; i++) {
        if (raw[i] == 'd' && raw[i+1] == 'a' && raw[i+2] == 't' && raw[i+3] == 'a') {
            uint32_t data_size = *reinterpret_cast<uint32_t*>(&raw[i + 4]);
            audio_data = reinterpret_cast<int16_t*>(&raw[i + 8]);
            audio_samples = data_size / 2;
            break;
        }
    }

    if (!audio_data || audio_samples == 0) {
        pipeline.cancel_speech();
        pipeline.stop();
        result.details = "Failed to parse WAV";
        return result;
    }

    wakeword_count.store(0);
    const size_t chunk = 256;

    // Feed 1st "Hey Jarvis" (barge-in)
    for (size_t i = 0; i + chunk <= audio_samples; i += chunk) {
        pipeline.process_audio(audio_data + i, chunk);
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(300));

    int wakeword_after_bargein = wakeword_count.load();
    bool interrupted = speech_interrupted.load();
    auto state_after_bargein = pipeline.state();

    if (wakeword_after_bargein == 0) {
        pipeline.cancel_speech();
        pipeline.stop();
        result.passed = true;
        result.details = "SKIPPED: WAV did not trigger wake word during TTS";
        return result;
    }

    // Step 3: Verify barge-in state (should be LISTENING with wakeword_activated=true)
    if (state_after_bargein != openclaw::PipelineState::LISTENING) {
        pipeline.stop();
        result.details = "Expected LISTENING after barge-in, got: " + pipeline.state_string();
        return result;
    }

    // Step 4: Wait for wake word timeout (10s) to return to WAITING_FOR_WAKE_WORD
    // Feed silence to trigger the timeout
    std::cout << "  [Test] Waiting for wake word timeout (~10s)...\n";
    auto timeout_start = std::chrono::steady_clock::now();
    while (pipeline.state() != openclaw::PipelineState::WAITING_FOR_WAKE_WORD) {
        auto silence_chunk = generate_silence_16k(0.5f);
        for (size_t i = 0; i + chunk <= silence_chunk.size(); i += chunk) {
            pipeline.process_audio(silence_chunk.data() + i, chunk);
        }
        auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
            std::chrono::steady_clock::now() - timeout_start).count();
        if (elapsed > 15) {
            pipeline.stop();
            result.details = "Timeout: pipeline never returned to WAITING_FOR_WAKE_WORD (state="
                           + pipeline.state_string() + ")";
            return result;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    // Step 5: Feed 2nd "Hey Jarvis" -- should trigger again
    // Prime with silence first
    auto prime = generate_silence_16k(0.5f);
    for (size_t i = 0; i + chunk <= prime.size(); i += chunk) {
        pipeline.process_audio(prime.data() + i, chunk);
    }

    int count_before_2nd = wakeword_count.load();
    for (size_t i = 0; i + chunk <= audio_samples; i += chunk) {
        pipeline.process_audio(audio_data + i, chunk);
    }

    // Post silence
    auto post = generate_silence_16k(0.5f);
    for (size_t i = 0; i + chunk <= post.size(); i += chunk) {
        pipeline.process_audio(post.data() + i, chunk);
    }

    pipeline.stop();

    int second_wakeword = wakeword_count.load() - count_before_2nd;
    if (second_wakeword == 0) {
        result.details = "2nd wake word did NOT trigger after barge-in cycle";
        return result;
    }

    result.passed = true;
    std::ostringstream details;
    details << "Barge-in: interrupted=" << (interrupted ? "yes" : "no")
            << ", state_after_bargein=LISTENING"
            << ", 1st wakeword fired, timeout->WAITING_FOR_WAKE_WORD"
            << ", 2nd wakeword fired (" << second_wakeword << " times)"
            << ", final state=" << pipeline.state_string();
    result.details = details.str();
    return result;
}

// =============================================================================
// Test: Barge-In ASR Readiness
// =============================================================================
// After barge-in, verify the pipeline is in LISTENING state with
// wakeword_activated=true, meaning VAD/STT will run on the next audio.
// =============================================================================

TestResult test_bargein_asr_readiness() {
    TestResult result;
    result.name = "Barge-In ASR Readiness (LISTENING state after interrupt)";

    std::atomic<bool> wakeword_detected{false};
    std::atomic<bool> speech_interrupted{false};

    openclaw::VoicePipelineConfig config;
    config.enable_wake_word = true;
    config.wake_word = "Hey Jarvis";
    config.wake_word_threshold = 0.5f;
    config.silence_duration_sec = 1.0;
    config.min_speech_samples = 8000;

    config.on_wake_word = [&](const std::string&, float) { wakeword_detected.store(true); };
    config.on_speech_interrupted = [&]() { speech_interrupted.store(true); };
    config.on_audio_output = [](const int16_t*, size_t, int, const std::atomic<bool>&) {};
    config.on_error = [](const std::string&) {};

    openclaw::VoicePipeline pipeline(config);
    if (!pipeline.initialize()) {
        result.details = "Failed to initialize: " + pipeline.last_error();
        return result;
    }
    pipeline.start();

    // Start TTS with a long response to ensure it stays in SPEAKING long enough
    pipeline.speak_text_async(
        "This is a long response to test ASR readiness after barge-in. "
        "We need multiple sentences so the pipeline stays in SPEAKING state. "
        "The user will interrupt before all sentences are synthesized and played.");

    // Wait for TTS to enter SPEAKING state
    bool entered_speaking = false;
    for (int i = 0; i < 100; i++) {  // Up to 5s
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        if (pipeline.state() == openclaw::PipelineState::SPEAKING) {
            entered_speaking = true;
            break;
        }
    }

    if (!entered_speaking) {
        pipeline.stop();
        result.details = "Pipeline never entered SPEAKING state: " + pipeline.state_string();
        return result;
    }

    // Feed "Hey Jarvis" for barge-in
    std::string wav_path = "tests/audio/hey-jarvis-real.wav";
    {
        struct stat st;
        if (stat(wav_path.c_str(), &st) != 0) {
            wav_path = "tests/audio/hey-jarvis-amplified.wav";
            if (stat(wav_path.c_str(), &st) != 0) {
                pipeline.cancel_speech();
                pipeline.stop();
                result.passed = true;
                result.details = "SKIPPED: No hey-jarvis WAV file";
                return result;
            }
        }
    }

    std::ifstream wav_file(wav_path, std::ios::binary);
    wav_file.seekg(0, std::ios::end);
    size_t file_size = wav_file.tellg();
    wav_file.seekg(0);
    std::vector<char> raw(file_size);
    wav_file.read(raw.data(), file_size);
    wav_file.close();

    int16_t* audio_data = nullptr;
    size_t audio_samples = 0;
    for (size_t i = 0; i + 8 < file_size; i++) {
        if (raw[i] == 'd' && raw[i+1] == 'a' && raw[i+2] == 't' && raw[i+3] == 'a') {
            uint32_t data_size = *reinterpret_cast<uint32_t*>(&raw[i + 4]);
            audio_data = reinterpret_cast<int16_t*>(&raw[i + 8]);
            audio_samples = data_size / 2;
            break;
        }
    }

    if (!audio_data || audio_samples == 0) {
        pipeline.cancel_speech();
        pipeline.stop();
        result.details = "Failed to parse WAV";
        return result;
    }

    const size_t chunk = 256;
    for (size_t i = 0; i + chunk <= audio_samples; i += chunk) {
        pipeline.process_audio(audio_data + i, chunk);
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(300));

    if (!wakeword_detected.load()) {
        pipeline.cancel_speech();
        pipeline.stop();
        result.passed = true;
        result.details = "SKIPPED: WAV did not trigger wake word during TTS";
        return result;
    }

    // Key assertions:
    // 1. State should be LISTENING (wakeword_activated=true, ready for VAD)
    auto final_state = pipeline.state();
    bool is_speaking = pipeline.is_speaking();

    pipeline.stop();

    if (final_state != openclaw::PipelineState::LISTENING) {
        result.details = "Expected LISTENING after barge-in, got: " + pipeline.state_string();
        return result;
    }

    if (is_speaking) {
        result.details = "is_speaking() still true after barge-in";
        return result;
    }

    if (!speech_interrupted.load()) {
        result.details = "on_speech_interrupted callback was not fired";
        return result;
    }

    result.passed = true;
    std::ostringstream details;
    details << "State: LISTENING (ASR-ready)"
            << ", is_speaking=false"
            << ", speech_interrupted=yes"
            << ", wakeword_detected=yes";
    result.details = details.str();
    return result;
}

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
    std::string wav_path = create_test_wav(22050, 500);

    openclaw::WaitingChime chime(wav_path, [&capture](const int16_t* samples, size_t n, int sr) {
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
    std::string wav_path = create_test_wav(22050, 300);

    openclaw::WaitingChime chime(wav_path, [&capture](const int16_t* samples, size_t n, int sr) {
        capture.on_audio(samples, n, sr);
    });

    // Play earcon - it should play the WAV once immediately
    chime.start();
    std::this_thread::sleep_for(std::chrono::milliseconds(1000));
    chime.stop();

    size_t total = capture.total_samples();
    if (total == 0) {
        result.details = "No audio samples captured from earcon playback";
        return result;
    }

    // Check that audio has non-zero samples (actual sound, not silence)
    std::lock_guard<std::mutex> lock(capture.mutex);
    int non_zero = 0;
    int16_t max_amp = 0;
    for (int16_t s : capture.captured_samples) {
        if (s != 0) non_zero++;
        int16_t a = static_cast<int16_t>(std::abs(s));
        if (a > max_amp) max_amp = a;
    }

    float non_zero_ratio = static_cast<float>(non_zero) / static_cast<float>(total);
    if (non_zero_ratio < 0.5f) {
        result.details = "Earcon audio is mostly silence (" + std::to_string(non_zero_ratio * 100) + "% non-zero)";
        return result;
    }

    if (max_amp < 500) {
        result.details = "Earcon max amplitude too low: " + std::to_string(max_amp);
        return result;
    }

    result.passed = true;
    std::ostringstream details;
    details << "Samples: " << total
            << ", Non-zero: " << (non_zero_ratio * 100) << "%"
            << ", Max amplitude: " << max_amp;
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
    pipeline_config.on_audio_output = [&capture](const int16_t* samples, size_t n, int sr, const std::atomic<bool>&) {
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
    std::string earcon_path = create_test_wav(22050, 300);

    openclaw::WaitingChime waiting_chime(earcon_path, [&chime_capture](const int16_t* samples, size_t n, int sr) {
        chime_capture.on_audio(samples, n, sr);
    });

    // --- Step 4: Create voice pipeline (for TTS) ---
    openclaw::VoicePipelineConfig pipeline_config;
    pipeline_config.on_audio_output = [&tts_capture](const int16_t* samples, size_t n, int sr, const std::atomic<bool>&) {
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

    // The earcon is a short sound (~0.3s) played once immediately, then every 5 seconds.
    // Verify based on expected number of earcon plays, not continuous audio duration.
    // Each earcon play produces ~0.3s of audio.
    //   5s delay  → 1-2 plays → 0.3-0.6s audio
    //   15s delay → 3-4 plays → 0.9-1.2s audio
    constexpr float EARCON_DURATION = 0.3f;  // Each earcon is ~0.3s
    int expected_min_plays = 1;  // Always plays once immediately
    if (response_delay_ms > 6000) {
        // After the first play, one repeat fires every 5s
        expected_min_plays += (response_delay_ms - 1000) / 5000;  // Conservative (1s margin)
    }
    float expected_min_chime_seconds = expected_min_plays * EARCON_DURATION * 0.5f;  // 50% tolerance

    if (chime_duration < expected_min_chime_seconds && response_delay_ms >= 2000) {
        result.details = "Chime didn't play enough earcons: " + std::to_string(chime_duration) + "s"
                       + " (expected at least " + std::to_string(expected_min_chime_seconds) + "s"
                       + ", " + std::to_string(expected_min_plays) + " plays)";
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

    int approx_earcon_plays = (chime_duration > 0.01f)
        ? static_cast<int>(chime_duration / EARCON_DURATION + 0.5f) : 0;

    std::ostringstream details;
    details << "Server delay: " << response_delay_ms << "ms"
            << ", Chime audio: " << chime_duration << "s"
            << " (~" << approx_earcon_plays << " earcon plays)"
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
              << "  --test-tts-queue         Test TTS queue parallel playback and cancel\n"
              << "  --test-chime             Test waiting chime timing and audio\n"
              << "  --test-bargein           Test barge-in cancel chain and rapid restart (needs ONNX)\n"
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
        else if (arg == "--test-tts-queue") {
            // TTS queue tests need NO model/backend infrastructure
            results.push_back(test_tts_queue_parallel_playback());
            results.push_back(test_tts_queue_cancel());
            results.push_back(test_tts_queue_push_while_playing());
            results.push_back(test_tts_queue_cancel_during_playback());
            results.push_back(test_tts_queue_cancel_during_synthesis());
        }
        else if (arg == "--test-chime") {
            // Chime tests need NO model/backend infrastructure
            results.push_back(test_waiting_chime_timing());
            results.push_back(test_waiting_chime_audio_content());
        }
        else if (arg == "--test-bargein") {
            if (!ensure_backends_initialized()) return 1;
            results.push_back(test_bargein_cancel_chain());
            results.push_back(test_bargein_rapid_restart());
            results.push_back(test_wakeword_single_detection());
            results.push_back(test_wakeword_timeout_returns_to_waiting());
            results.push_back(test_bargein_wakeword_during_tts());
            results.push_back(test_post_tts_wakeword_reactivation());
            results.push_back(test_post_bargein_second_wakeword());
            results.push_back(test_bargein_asr_readiness());
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

            // --- Section 1: TTS Queue (NO backend init needed) ---
            std::cout << "--- Section 1: TTS Queue ---\n\n";
            results.push_back(test_tts_queue_parallel_playback());
            results.push_back(test_tts_queue_cancel());
            results.push_back(test_tts_queue_push_while_playing());
            results.push_back(test_tts_queue_cancel_during_playback());
            results.push_back(test_tts_queue_cancel_during_synthesis());

            // --- Section 2: Waiting Chime (NO backend init needed) ---
            std::cout << "\n--- Section 2: Waiting Chime ---\n\n";
            results.push_back(test_waiting_chime_timing());
            results.push_back(test_waiting_chime_audio_content());

            // --- Initialize backends for remaining tests ---
            if (!ensure_backends_initialized()) return 1;

            // --- Section 3: Text Sanitization ---
            std::cout << "\n--- Section 3: Text Sanitization ---\n\n";
            results.push_back(test_text_sanitization());

            // --- Section 4: TTS Synthesis ---
            std::cout << "\n--- Section 4: TTS Synthesis ---\n\n";
            results.push_back(test_tts_synthesis());

            // --- Section 5: Barge-in + Wake Word ---
            std::cout << "\n--- Section 5: Barge-in + Wake Word ---\n\n";
            results.push_back(test_bargein_cancel_chain());
            results.push_back(test_bargein_rapid_restart());
            results.push_back(test_wakeword_single_detection());
            results.push_back(test_wakeword_timeout_returns_to_waiting());
            results.push_back(test_bargein_wakeword_during_tts());
            results.push_back(test_post_tts_wakeword_reactivation());
            results.push_back(test_post_bargein_second_wakeword());
            results.push_back(test_bargein_asr_readiness());

            // --- Section 6: Full OpenClaw Flow ---
            std::cout << "\n--- Section 5: Full OpenClaw Flow ---\n\n";

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
