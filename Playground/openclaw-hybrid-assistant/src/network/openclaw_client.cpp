// =============================================================================
// OpenClaw WebSocket Client - Implementation
// =============================================================================

#include "openclaw_client.h"

#include <iostream>
#include <sstream>
#include <regex>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <random>

// Socket/network
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <poll.h>

namespace openclaw {

// =============================================================================
// URL parsing helper
// =============================================================================

static bool parse_ws_url(const std::string& url, std::string& host, int& port, std::string& path) {
    // ws://host:port/path or http://host:port/path (no TLS support)
    std::regex url_regex(R"((ws|wss|http|https)://([^:/]+)(?::(\d+))?(/.*)?)");
    std::smatch match;
    if (!std::regex_match(url, match, url_regex)) {
        return false;
    }

    std::string scheme = match[1].str();
    if (scheme == "wss" || scheme == "https") {
        std::cerr << "[OpenClaw] TLS is not supported; use ws:// or http:// instead of "
                  << scheme << "://" << std::endl;
        return false;
    }

    host = match[2].str();
    port = match[3].matched ? std::stoi(match[3].str()) : 8082;
    path = match[4].matched && !match[4].str().empty() ? match[4].str() : "/";
    return true;
}

// =============================================================================
// Base64 encode (for WebSocket handshake key)
// =============================================================================

static const char b64_table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static std::string base64_encode(const uint8_t* data, size_t len) {
    std::string result;
    result.reserve(((len + 2) / 3) * 4);
    for (size_t i = 0; i < len; i += 3) {
        uint32_t n = ((uint32_t)data[i]) << 16;
        if (i + 1 < len) n |= ((uint32_t)data[i + 1]) << 8;
        if (i + 2 < len) n |= data[i + 2];
        result += b64_table[(n >> 18) & 0x3F];
        result += b64_table[(n >> 12) & 0x3F];
        result += (i + 1 < len) ? b64_table[(n >> 6) & 0x3F] : '=';
        result += (i + 2 < len) ? b64_table[n & 0x3F] : '=';
    }
    return result;
}

// =============================================================================
// Socket helpers
// =============================================================================

static bool recv_all(int fd, void* buf, size_t len, int timeout_ms) {
    size_t total = 0;
    auto* p = static_cast<uint8_t*>(buf);
    while (total < len) {
        struct pollfd pfd = {fd, POLLIN, 0};
        int ret = poll(&pfd, 1, timeout_ms);
        if (ret <= 0) return false;
        ssize_t n = recv(fd, p + total, len - total, 0);
        if (n <= 0) return false;
        total += n;
    }
    return true;
}

static bool send_all(int fd, const void* buf, size_t len) {
    size_t total = 0;
    auto* p = static_cast<const uint8_t*>(buf);
    while (total < len) {
        ssize_t n = send(fd, p + total, len - total, MSG_NOSIGNAL);
        if (n <= 0) return false;
        total += n;
    }
    return true;
}

// =============================================================================
// OpenClawClient Implementation
// =============================================================================

OpenClawClient::OpenClawClient() {}

OpenClawClient::OpenClawClient(const OpenClawClientConfig& config)
    : config_(config) {}

OpenClawClient::~OpenClawClient() {
    disconnect();
}

bool OpenClawClient::connect() {
    std::string host, path;
    int port;
    if (!parse_ws_url(config_.url, host, port, path)) {
        last_error_ = "Invalid URL: " + config_.url;
        std::cerr << "[OpenClaw] " << last_error_ << std::endl;
        return false;
    }

    // TCP connect via getaddrinfo
    struct addrinfo hints = {};
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    struct addrinfo* result = nullptr;
    int gai_err = getaddrinfo(host.c_str(), std::to_string(port).c_str(), &hints, &result);
    if (gai_err != 0) {
        last_error_ = "Failed to resolve host: " + host + " (" + gai_strerror(gai_err) + ")";
        std::cerr << "[OpenClaw] " << last_error_ << std::endl;
        return false;
    }

    socket_fd_ = socket(result->ai_family, result->ai_socktype, result->ai_protocol);
    if (socket_fd_ < 0) {
        last_error_ = "Failed to create socket";
        std::cerr << "[OpenClaw] " << last_error_ << std::endl;
        freeaddrinfo(result);
        return false;
    }

    // Disable Nagle for low latency
    int flag = 1;
    setsockopt(socket_fd_, IPPROTO_TCP, TCP_NODELAY, &flag, sizeof(flag));

    if (::connect(socket_fd_, result->ai_addr, result->ai_addrlen) < 0) {
        last_error_ = "Failed to connect to " + host + ":" + std::to_string(port);
        std::cerr << "[OpenClaw] " << last_error_ << std::endl;
        close(socket_fd_);
        socket_fd_ = -1;
        freeaddrinfo(result);
        return false;
    }

    freeaddrinfo(result);

    // WebSocket handshake
    if (!ws_handshake(host, port, path)) {
        close(socket_fd_);
        socket_fd_ = -1;
        return false;
    }

    connected_ = true;
    std::cout << "[OpenClaw] WebSocket connected to " << config_.url << std::endl;

    // Send OpenClaw connect message
    if (!send_connect_message()) {
        std::cerr << "[OpenClaw] WARNING: Failed to send connect message" << std::endl;
    }

    // Start background receive loop
    running_ = true;
    ws_thread_ = std::thread(&OpenClawClient::run_receive_loop, this);

    if (config_.on_connected) {
        config_.on_connected();
    }

    return true;
}

void OpenClawClient::disconnect() {
    running_ = false;
    connected_ = false;

    if (socket_fd_ >= 0) {
        // Send WebSocket close frame (opcode 0x08)
        uint8_t close_frame[] = {0x88, 0x80, 0x00, 0x00, 0x00, 0x00};
        send(socket_fd_, close_frame, sizeof(close_frame), MSG_NOSIGNAL);
        shutdown(socket_fd_, SHUT_RDWR);
        close(socket_fd_);
        socket_fd_ = -1;
    }

    if (ws_thread_.joinable()) {
        ws_thread_.join();
    }

    if (config_.on_disconnected) {
        config_.on_disconnected("Disconnected");
    }
}

bool OpenClawClient::is_connected() const {
    return connected_;
}

// =============================================================================
// WebSocket Handshake
// =============================================================================

bool OpenClawClient::ws_handshake(const std::string& host, int port, const std::string& path) {
    // Generate random 16-byte key
    std::random_device rd;
    uint8_t key_bytes[16];
    for (int i = 0; i < 16; i++) {
        key_bytes[i] = rd() & 0xFF;
    }
    std::string ws_key = base64_encode(key_bytes, 16);

    // Build upgrade request
    std::ostringstream req;
    req << "GET " << path << " HTTP/1.1\r\n"
        << "Host: " << host << ":" << port << "\r\n"
        << "Upgrade: websocket\r\n"
        << "Connection: Upgrade\r\n"
        << "Sec-WebSocket-Key: " << ws_key << "\r\n"
        << "Sec-WebSocket-Version: 13\r\n"
        << "\r\n";

    std::string request_str = req.str();
    if (!send_all(socket_fd_, request_str.data(), request_str.size())) {
        last_error_ = "Failed to send WebSocket handshake";
        std::cerr << "[OpenClaw] " << last_error_ << std::endl;
        return false;
    }

    // Read response (look for 101 Switching Protocols)
    std::string response;
    char buf[1];
    int timeout_count = 0;
    while (timeout_count < 5000) {  // 5 second timeout
        struct pollfd pfd = {socket_fd_, POLLIN, 0};
        int ret = poll(&pfd, 1, 1);
        if (ret > 0) {
            ssize_t n = recv(socket_fd_, buf, 1, 0);
            if (n <= 0) break;
            response += buf[0];
            // Check for end of HTTP headers
            if (response.size() >= 4 &&
                response.substr(response.size() - 4) == "\r\n\r\n") {
                break;
            }
        } else {
            timeout_count++;
        }
    }

    if (response.find("101") == std::string::npos) {
        last_error_ = "WebSocket handshake failed: " + response.substr(0, 80);
        std::cerr << "[OpenClaw] " << last_error_ << std::endl;
        return false;
    }

    return true;
}

// =============================================================================
// WebSocket Frame Send (client must mask)
// =============================================================================

bool OpenClawClient::ws_send_text(const std::string& payload) {
    std::lock_guard<std::mutex> lock(write_mutex_);

    if (socket_fd_ < 0 || !connected_) return false;

    std::vector<uint8_t> frame;
    // FIN + text opcode
    frame.push_back(0x81);

    // Payload length + mask bit (client frames must be masked)
    size_t len = payload.size();
    if (len <= 125) {
        frame.push_back(0x80 | (uint8_t)len);
    } else if (len <= 65535) {
        frame.push_back(0x80 | 126);
        frame.push_back((len >> 8) & 0xFF);
        frame.push_back(len & 0xFF);
    } else {
        frame.push_back(0x80 | 127);
        for (int i = 7; i >= 0; i--) {
            frame.push_back((len >> (8 * i)) & 0xFF);
        }
    }

    // Masking key (4 random bytes)
    std::random_device rd;
    uint8_t mask[4];
    for (int i = 0; i < 4; i++) mask[i] = rd() & 0xFF;
    frame.insert(frame.end(), mask, mask + 4);

    // Masked payload
    for (size_t i = 0; i < len; i++) {
        frame.push_back(payload[i] ^ mask[i % 4]);
    }

    return send_all(socket_fd_, frame.data(), frame.size());
}

// =============================================================================
// WebSocket Frame Receive
// =============================================================================

bool OpenClawClient::ws_read_frame(std::string& out_payload, uint8_t& out_opcode) {
    uint8_t header[2];
    if (!recv_all(socket_fd_, header, 2, 500)) return false;

    out_opcode = header[0] & 0x0F;
    bool masked = (header[1] & 0x80) != 0;
    uint64_t payload_len = header[1] & 0x7F;

    if (payload_len == 126) {
        uint8_t ext[2];
        if (!recv_all(socket_fd_, ext, 2, 500)) return false;
        payload_len = ((uint64_t)ext[0] << 8) | ext[1];
    } else if (payload_len == 127) {
        uint8_t ext[8];
        if (!recv_all(socket_fd_, ext, 8, 500)) return false;
        payload_len = 0;
        for (int i = 0; i < 8; i++) {
            payload_len = (payload_len << 8) | ext[i];
        }
    }

    // Sanity check
    if (payload_len > 1024 * 1024) return false;  // Max 1MB

    uint8_t mask_key[4] = {};
    if (masked) {
        if (!recv_all(socket_fd_, mask_key, 4, 500)) return false;
    }

    out_payload.resize(payload_len);
    if (payload_len > 0) {
        if (!recv_all(socket_fd_, &out_payload[0], payload_len, 2000)) return false;
        if (masked) {
            for (size_t i = 0; i < payload_len; i++) {
                out_payload[i] ^= mask_key[i % 4];
            }
        }
    }

    return true;
}

void OpenClawClient::ws_send_pong(const std::string& payload) {
    std::lock_guard<std::mutex> lock(write_mutex_);
    if (socket_fd_ < 0) return;

    std::vector<uint8_t> frame;
    frame.push_back(0x8A);  // FIN + pong
    size_t len = payload.size();
    frame.push_back(0x80 | (uint8_t)(len & 0x7F));

    std::random_device rd;
    uint8_t mask[4];
    for (int i = 0; i < 4; i++) mask[i] = rd() & 0xFF;
    frame.insert(frame.end(), mask, mask + 4);

    for (size_t i = 0; i < len; i++) {
        frame.push_back(payload[i] ^ mask[i % 4]);
    }

    send_all(socket_fd_, frame.data(), frame.size());
}

// =============================================================================
// JSON helper
// =============================================================================

static std::string escape_json_string(const std::string& input) {
    std::string result;
    result.reserve(input.size());
    for (char c : input) {
        switch (c) {
            case '"':  result += "\\\""; break;
            case '\\': result += "\\\\"; break;
            case '\n': result += "\\n";  break;
            case '\r': result += "\\r";  break;
            case '\t': result += "\\t";  break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    // Escape other control characters as \u00XX
                    char buf[8];
                    snprintf(buf, sizeof(buf), "\\u%04x", static_cast<unsigned char>(c));
                    result += buf;
                } else {
                    result += c;
                }
                break;
        }
    }
    return result;
}

// =============================================================================
// OpenClaw Protocol
// =============================================================================

bool OpenClawClient::send_connect_message() {
    std::ostringstream json;
    json << "{"
         << "\"type\":\"connect\","
         << "\"deviceId\":\"" << escape_json_string(config_.device_id) << "\","
         << "\"accountId\":\"" << escape_json_string(config_.account_id) << "\","
         << "\"capabilities\":{"
         <<   "\"stt\":true,"
         <<   "\"tts\":true,"
         <<   "\"wakeWord\":true"
         << "}"
         << "}";

    std::cout << "[OpenClaw] Sending connect message (device: " << config_.device_id << ")" << std::endl;
    return ws_send_text(json.str());
}

bool OpenClawClient::send_transcription(const std::string& text, bool is_final) {
    if (!connected_) {
        last_error_ = "Not connected";
        return false;
    }

    // Build JSON with proper escaping
    std::ostringstream json;
    json << "{\"type\":\"transcription\",\"text\":\""
         << escape_json_string(text)
         << "\",\"sessionId\":\"" << escape_json_string(config_.session_id) << "\""
         << ",\"isFinal\":" << (is_final ? "true" : "false")
         << "}";

    std::cout << "[OpenClaw] Sending transcription: " << text << std::endl;

    if (!ws_send_text(json.str())) {
        last_error_ = "Failed to send WebSocket frame";
        std::cerr << "[OpenClaw] " << last_error_ << std::endl;
        return false;
    }

    std::cout << "[OpenClaw] Transcription sent successfully" << std::endl;
    return true;
}

bool OpenClawClient::poll_speak_queue(SpeakMessage& out_message) {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    if (speak_queue_.empty()) return false;
    out_message = speak_queue_.front();
    speak_queue_.pop();
    return true;
}

void OpenClawClient::clear_speak_queue() {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    std::queue<SpeakMessage>().swap(speak_queue_);
}

void OpenClawClient::set_config(const OpenClawClientConfig& config) {
    config_ = config;
}

// =============================================================================
// Background Receive Loop
// =============================================================================

void OpenClawClient::run_receive_loop() {
    while (running_ && socket_fd_ >= 0) {
        std::string payload;
        uint8_t opcode;

        if (!ws_read_frame(payload, opcode)) {
            // Timeout or error - check if we should keep running
            if (!running_) break;
            continue;
        }

        switch (opcode) {
            case 0x01:  // Text frame
                handle_message(payload);
                break;
            case 0x08:  // Close
                std::cout << "[OpenClaw] Server closed connection" << std::endl;
                connected_ = false;
                running_ = false;
                if (config_.on_disconnected) {
                    config_.on_disconnected("Server closed connection");
                }
                return;
            case 0x09:  // Ping
                ws_send_pong(payload);
                break;
            case 0x0A:  // Pong
                break;
            default:
                break;
        }
    }
}

void OpenClawClient::handle_message(const std::string& message) {
    std::string type = parse_json_string(message, "type");

    if (type == "connected") {
        std::string session_id = parse_json_string(message, "sessionId");
        std::string version = parse_json_string(message, "serverVersion");
        std::cout << "[OpenClaw] Handshake complete (session: " << session_id
                  << ", server: " << version << ")" << std::endl;

    } else if (type == "speak") {
        SpeakMessage msg;
        msg.text = parse_json_string(message, "text");
        msg.source_channel = parse_json_string(message, "sourceChannel");

        if (!msg.text.empty()) {
            std::cout << "[OpenClaw] Received speak from " << msg.source_channel
                      << ": " << msg.text << std::endl;
            {
                std::lock_guard<std::mutex> lock(queue_mutex_);
                speak_queue_.push(msg);
            }
            if (config_.on_speak) {
                config_.on_speak(msg);
            }
        }

    } else if (type == "pong") {
        // Keepalive response, ignore

    } else if (type == "error") {
        std::string code = parse_json_string(message, "code");
        std::string err_msg = parse_json_string(message, "message");
        std::cerr << "[OpenClaw] Error from server: " << code << " - " << err_msg << std::endl;
        if (config_.on_error) {
            config_.on_error(code + ": " + err_msg);
        }

    } else {
        std::cout << "[OpenClaw] Unknown message type: " << type << std::endl;
    }
}

std::string OpenClawClient::parse_json_string(const std::string& json, const std::string& key) {
    std::string pattern = "\"" + key + "\"\\s*:\\s*\"([^\"]*)\"";
    std::regex re(pattern);
    std::smatch match;
    if (std::regex_search(json, match, re)) {
        return match[1].str();
    }
    return "";
}

} // namespace openclaw
