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
// OpenClaw Client
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

    // Send transcription to OpenClaw (fire-and-forget, non-blocking)
    bool send_transcription(const std::string& text, bool is_final = true);

    // Poll for speak messages (returns next message or empty if none)
    // This is used when WebSocket is not available (HTTP fallback)
    bool poll_speak_queue(SpeakMessage& out_message);

    // Configuration
    void set_config(const OpenClawClientConfig& config);
    const OpenClawClientConfig& config() const { return config_; }

    // Status
    std::string last_error() const { return last_error_; }

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;

    OpenClawClientConfig config_;
    std::string last_error_;
    std::atomic<bool> connected_{false};

    // Speak queue (messages received from OpenClaw)
    std::queue<SpeakMessage> speak_queue_;
    std::mutex queue_mutex_;

    // Background thread for WebSocket
    std::thread ws_thread_;
    std::atomic<bool> running_{false};

    // Internal methods
    void run_websocket_loop();
    bool send_connect_message();
    bool send_ping();
    void handle_message(const std::string& message);
    std::string parse_json_string(const std::string& json, const std::string& key);
};

// =============================================================================
// HTTP Fallback Client (for environments without WebSocket)
// =============================================================================

class OpenClawHttpClient {
public:
    OpenClawHttpClient();
    explicit OpenClawHttpClient(const std::string& base_url);
    ~OpenClawHttpClient();

    // Send transcription via HTTP POST
    bool send_transcription(const std::string& text, const std::string& session_id = "main");

    // Poll for speak messages via HTTP GET
    bool poll_speak(SpeakMessage& out_message);

    // Configuration
    void set_base_url(const std::string& url) { base_url_ = url; }
    std::string last_error() const { return last_error_; }

private:
    std::string base_url_ = "http://localhost:8081";  // Voice bridge URL
    std::string last_error_;

    // HTTP helpers
    struct HttpResponse {
        int status_code = 0;
        std::string body;
        bool success = false;
    };

    HttpResponse http_post(const std::string& url, const std::string& body, int timeout_ms = 5000);
    HttpResponse http_get(const std::string& url, int timeout_ms = 2000);
};

} // namespace openclaw
