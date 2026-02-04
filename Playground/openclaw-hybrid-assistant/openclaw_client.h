#pragma once

// =============================================================================
// OpenClaw WebSocket Client
// =============================================================================
// Handles WebSocket communication with OpenClaw voice-assistant channel.
//
// Protocol:
// - Connect with device capabilities
// - Send transcriptions (ASR results)
// - Receive speak commands (for TTS)
// =============================================================================

#include <string>
#include <functional>
#include <memory>
#include <queue>
#include <mutex>
#include <atomic>
#include <thread>
#include <vector>

namespace openclaw {

// =============================================================================
// Message Types
// =============================================================================

struct SpeakMessage {
    std::string text;
    std::string source_channel;
    int priority = 1;
    bool interrupt = false;
};

// =============================================================================
// OpenClaw Client Configuration
// =============================================================================

struct OpenClawClientConfig {
    std::string url = "ws://localhost:8082";
    std::string device_id = "openclaw-assistant";
    std::string account_id = "default";
    std::string session_id = "main";

    // Reconnection settings
    int reconnect_delay_ms = 2000;
    int max_reconnect_attempts = 10;

    // Callbacks
    std::function<void()> on_connected;
    std::function<void(const std::string&)> on_disconnected;
    std::function<void(const SpeakMessage&)> on_speak;
    std::function<void(const std::string&)> on_error;
};

// =============================================================================
// OpenClaw Client (WebSocket)
// =============================================================================

class OpenClawClient {
public:
    OpenClawClient();
    explicit OpenClawClient(const OpenClawClientConfig& config);
    ~OpenClawClient();

    // Connection management
    bool connect();
    void disconnect();
    bool is_connected() const;

    // Send transcription to OpenClaw
    bool send_transcription(const std::string& text, bool is_final = true);

    // Poll for speak messages from the receive queue
    bool poll_speak_queue(SpeakMessage& out_message);

    // Configuration
    void set_config(const OpenClawClientConfig& config);
    const OpenClawClientConfig& config() const { return config_; }

    // Status
    std::string last_error() const { return last_error_; }

private:
    OpenClawClientConfig config_;
    std::string last_error_;
    std::atomic<bool> connected_{false};

    // Socket
    int socket_fd_ = -1;
    std::mutex write_mutex_;

    // Speak queue (messages received from OpenClaw)
    std::queue<SpeakMessage> speak_queue_;
    std::mutex queue_mutex_;

    // Background thread for WebSocket receive loop
    std::thread ws_thread_;
    std::atomic<bool> running_{false};

    // WebSocket helpers
    bool ws_handshake(const std::string& host, int port, const std::string& path);
    bool ws_send_text(const std::string& payload);
    bool ws_read_frame(std::string& out_payload, uint8_t& out_opcode);
    void ws_send_pong(const std::string& payload);

    // Protocol
    bool send_connect_message();
    void run_receive_loop();
    void handle_message(const std::string& message);
    std::string parse_json_string(const std::string& json, const std::string& key);
};

} // namespace openclaw
