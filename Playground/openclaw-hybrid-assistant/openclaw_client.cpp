// =============================================================================
// OpenClaw WebSocket Client - Implementation
// =============================================================================

#include "openclaw_client.h"

#include <iostream>
#include <sstream>
#include <regex>
#include <chrono>

// For HTTP client
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <cstring>

namespace openclaw {

// =============================================================================
// OpenClawClient Implementation
// =============================================================================

struct OpenClawClient::Impl {
    int socket_fd = -1;
    std::string server_version;
    std::string assigned_session_id;
};

OpenClawClient::OpenClawClient()
    : impl_(std::make_unique<Impl>()) {
}

OpenClawClient::OpenClawClient(const OpenClawClientConfig& config)
    : impl_(std::make_unique<Impl>())
    , config_(config) {
}

OpenClawClient::~OpenClawClient() {
    disconnect();
}

bool OpenClawClient::connect() {
    // For now, use HTTP fallback (WebSocket implementation would require a WS library)
    // TODO: Implement proper WebSocket using libwebsockets or similar

    // Just mark as "connected" for HTTP mode
    connected_ = true;

    if (config_.on_connected) {
        config_.on_connected();
    }

    std::cout << "[OpenClaw] Connected (HTTP mode) to " << config_.url << std::endl;
    return true;
}

void OpenClawClient::disconnect() {
    running_ = false;
    connected_ = false;

    if (ws_thread_.joinable()) {
        ws_thread_.join();
    }

    if (impl_->socket_fd >= 0) {
        close(impl_->socket_fd);
        impl_->socket_fd = -1;
    }

    if (config_.on_disconnected) {
        config_.on_disconnected("Disconnected");
    }
}

bool OpenClawClient::is_connected() const {
    return connected_;
}

bool OpenClawClient::send_transcription(const std::string& text, bool is_final) {
    if (!connected_) {
        last_error_ = "Not connected";
        return false;
    }

    // Use HTTP fallback for now
    OpenClawHttpClient http_client(config_.url);
    return http_client.send_transcription(text, config_.session_id);
}

bool OpenClawClient::poll_speak_queue(SpeakMessage& out_message) {
    // Check local queue first
    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        if (!speak_queue_.empty()) {
            out_message = speak_queue_.front();
            speak_queue_.pop();
            return true;
        }
    }

    // Poll HTTP endpoint
    OpenClawHttpClient http_client(config_.url);
    return http_client.poll_speak(out_message);
}

void OpenClawClient::set_config(const OpenClawClientConfig& config) {
    config_ = config;
}

void OpenClawClient::run_websocket_loop() {
    // TODO: Implement proper WebSocket loop
    // For now, we use HTTP polling which is handled in poll_speak_queue
}

bool OpenClawClient::send_connect_message() {
    // TODO: Implement for WebSocket
    return true;
}

bool OpenClawClient::send_ping() {
    // TODO: Implement for WebSocket
    return true;
}

void OpenClawClient::handle_message(const std::string& message) {
    // TODO: Implement for WebSocket
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

// =============================================================================
// OpenClawHttpClient Implementation
// =============================================================================

OpenClawHttpClient::OpenClawHttpClient() {
}

OpenClawHttpClient::OpenClawHttpClient(const std::string& base_url)
    : base_url_(base_url) {
    // Convert ws:// to http:// if needed
    if (base_url_.find("ws://") == 0) {
        base_url_ = "http://" + base_url_.substr(5);
    } else if (base_url_.find("wss://") == 0) {
        base_url_ = "https://" + base_url_.substr(6);
    }

    // Extract host:port and default to voice bridge port
    // ws://localhost:8082 -> http://localhost:8081
    size_t port_pos = base_url_.rfind(':');
    if (port_pos != std::string::npos && port_pos > 7) {
        // Replace port with voice bridge port
        base_url_ = base_url_.substr(0, port_pos) + ":8081";
    }
}

OpenClawHttpClient::~OpenClawHttpClient() {
}

// Parse URL into host, port, path
static bool parse_url(const std::string& url, std::string& host, int& port, std::string& path) {
    std::regex url_regex(R"(https?://([^:/]+)(?::(\d+))?(/.*)?)", std::regex::icase);
    std::smatch match;

    if (!std::regex_match(url, match, url_regex)) {
        return false;
    }

    host = match[1].str();
    port = match[2].matched ? std::stoi(match[2].str()) : 80;
    path = match[3].matched ? match[3].str() : "/";

    return true;
}

OpenClawHttpClient::HttpResponse OpenClawHttpClient::http_post(
    const std::string& url,
    const std::string& body,
    int timeout_ms
) {
    HttpResponse response;

    std::string host, path;
    int port;
    if (!parse_url(url, host, port, path)) {
        last_error_ = "Failed to parse URL: " + url;
        return response;
    }

    // Create socket
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        last_error_ = "Failed to create socket";
        return response;
    }

    // Set timeout
    struct timeval tv;
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    // Resolve hostname
    struct hostent* server = gethostbyname(host.c_str());
    if (!server) {
        last_error_ = "Failed to resolve host: " + host;
        close(sock);
        return response;
    }

    // Connect
    struct sockaddr_in server_addr = {};
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(port);
    memcpy(&server_addr.sin_addr.s_addr, server->h_addr, server->h_length);

    if (connect(sock, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        last_error_ = "Failed to connect to " + host + ":" + std::to_string(port);
        close(sock);
        return response;
    }

    // Build HTTP request
    std::ostringstream request;
    request << "POST " << path << " HTTP/1.1\r\n";
    request << "Host: " << host << ":" << port << "\r\n";
    request << "Content-Type: application/json\r\n";
    request << "Content-Length: " << body.size() << "\r\n";
    request << "Connection: close\r\n";
    request << "\r\n";
    request << body;

    std::string request_str = request.str();

    // Send request
    if (send(sock, request_str.c_str(), request_str.size(), 0) < 0) {
        last_error_ = "Failed to send request";
        close(sock);
        return response;
    }

    // Read response
    std::string response_data;
    char buffer[4096];
    ssize_t bytes_read;

    while ((bytes_read = recv(sock, buffer, sizeof(buffer) - 1, 0)) > 0) {
        buffer[bytes_read] = '\0';
        response_data += buffer;
    }

    close(sock);

    // Parse response
    size_t header_end = response_data.find("\r\n\r\n");
    if (header_end == std::string::npos) {
        last_error_ = "Invalid response (no header end)";
        return response;
    }

    std::string headers = response_data.substr(0, header_end);
    response.body = response_data.substr(header_end + 4);

    // Extract status code
    std::regex status_regex(R"(HTTP/\d\.\d\s+(\d+))");
    std::smatch status_match;
    if (std::regex_search(headers, status_match, status_regex)) {
        response.status_code = std::stoi(status_match[1].str());
        response.success = (response.status_code >= 200 && response.status_code < 300);
    }

    return response;
}

OpenClawHttpClient::HttpResponse OpenClawHttpClient::http_get(
    const std::string& url,
    int timeout_ms
) {
    HttpResponse response;

    std::string host, path;
    int port;
    if (!parse_url(url, host, port, path)) {
        return response;
    }

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        return response;
    }

    struct timeval tv;
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct hostent* server = gethostbyname(host.c_str());
    if (!server) {
        close(sock);
        return response;
    }

    struct sockaddr_in server_addr = {};
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(port);
    memcpy(&server_addr.sin_addr.s_addr, server->h_addr, server->h_length);

    if (connect(sock, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        close(sock);
        return response;
    }

    // Build HTTP GET request
    std::ostringstream request;
    request << "GET " << path << " HTTP/1.1\r\n";
    request << "Host: " << host << ":" << port << "\r\n";
    request << "Connection: close\r\n";
    request << "\r\n";

    std::string request_str = request.str();

    if (send(sock, request_str.c_str(), request_str.size(), 0) < 0) {
        close(sock);
        return response;
    }

    std::string response_data;
    char buffer[4096];
    ssize_t bytes_read;

    while ((bytes_read = recv(sock, buffer, sizeof(buffer) - 1, 0)) > 0) {
        buffer[bytes_read] = '\0';
        response_data += buffer;
    }

    close(sock);

    size_t header_end = response_data.find("\r\n\r\n");
    if (header_end == std::string::npos) {
        return response;
    }

    std::string headers = response_data.substr(0, header_end);
    response.body = response_data.substr(header_end + 4);

    std::regex status_regex("HTTP/\\d\\.\\d\\s+(\\d+)");
    std::smatch status_match;
    if (std::regex_search(headers, status_match, status_regex)) {
        response.status_code = std::stoi(status_match[1].str());
        response.success = (response.status_code >= 200 && response.status_code < 300);
    }

    return response;
}

bool OpenClawHttpClient::send_transcription(const std::string& text, const std::string& session_id) {
    std::string url = base_url_ + "/transcription";

    // Build JSON body with proper escaping
    std::ostringstream json;
    json << "{\"text\":\"";
    for (char c : text) {
        if (c == '"') json << "\\\"";
        else if (c == '\\') json << "\\\\";
        else if (c == '\n') json << "\\n";
        else if (c == '\r') json << "\\r";
        else if (c == '\t') json << "\\t";
        else json << c;
    }
    json << "\",\"sessionId\":\"" << session_id << "\",\"isFinal\":true}";

    std::cout << "[OpenClaw] Sending transcription: " << text << std::endl;

    HttpResponse response = http_post(url, json.str());

    if (!response.success) {
        last_error_ = "HTTP POST failed (status=" + std::to_string(response.status_code) + ")";
        std::cerr << "[OpenClaw] " << last_error_ << std::endl;
        return false;
    }

    std::cout << "[OpenClaw] Transcription sent successfully" << std::endl;
    return true;
}

bool OpenClawHttpClient::poll_speak(SpeakMessage& out_message) {
    std::string url = base_url_ + "/speak";

    HttpResponse response = http_get(url);

    if (!response.success || response.body.empty()) {
        return false;
    }

    // Parse JSON response: {"text": "...", "sourceChannel": "..."}
    std::regex text_regex("\"text\"\\s*:\\s*\"([^\"]*)\"");
    std::smatch text_match;

    if (!std::regex_search(response.body, text_match, text_regex)) {
        return false;
    }

    std::string text = text_match[1].str();
    if (text.empty() || text == "null") {
        return false;
    }

    out_message.text = text;

    // Extract source channel
    std::regex source_regex("\"sourceChannel\"\\s*:\\s*\"([^\"]*)\"");
    std::smatch source_match;
    if (std::regex_search(response.body, source_match, source_regex)) {
        out_message.source_channel = source_match[1].str();
    }

    std::cout << "[OpenClaw] Received speak from " << out_message.source_channel
              << ": " << out_message.text << std::endl;

    return true;
}

} // namespace openclaw
