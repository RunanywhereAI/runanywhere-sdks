// =============================================================================
// Voice Pipeline - Implementation using runanywhere-commons Voice Agent
// =============================================================================

#include "voice_pipeline.h"
#include "model_config.h"

#include <rac/features/voice_agent/rac_voice_agent.h>
#include <rac/features/stt/rac_stt_component.h>
#include <rac/features/tts/rac_tts_component.h>
#include <rac/features/vad/rac_vad_component.h>
#include <rac/features/llm/rac_llm_component.h>
#include <rac/backends/rac_wakeword_onnx.h>
#include <rac/core/rac_error.h>

#include <vector>
#include <mutex>
#include <iostream>
#include <chrono>
#include <sstream>
#include <regex>

// For HTTP client (Moltbot integration)
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>

namespace runanywhere {

// =============================================================================
// HTTP Client for Moltbot Voice Bridge
// =============================================================================

struct HttpResponse {
    int status_code = 0;
    std::string body;
    bool success = false;
};

// Parse URL into host, port, path
static bool parse_url(const std::string& url, std::string& host, int& port, std::string& path) {
    // Simple URL parser for http://host:port/path format
    std::regex url_regex(R"(http://([^:/]+)(?::(\d+))?(/.*)?)", std::regex::icase);
    std::smatch match;

    if (!std::regex_match(url, match, url_regex)) {
        return false;
    }

    host = match[1].str();
    port = match[2].matched ? std::stoi(match[2].str()) : 80;
    path = match[3].matched ? match[3].str() : "/";

    return true;
}

// Simple HTTP POST request
static HttpResponse http_post(const std::string& url, const std::string& json_body, int timeout_ms = 30000) {
    HttpResponse response;

    std::string host, path;
    int port;
    if (!parse_url(url, host, port, path)) {
        std::cerr << "[HTTP] Failed to parse URL: " << url << std::endl;
        return response;
    }

    // Create socket
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        std::cerr << "[HTTP] Failed to create socket" << std::endl;
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
        std::cerr << "[HTTP] Failed to resolve host: " << host << std::endl;
        close(sock);
        return response;
    }

    // Connect
    struct sockaddr_in server_addr = {};
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(port);
    memcpy(&server_addr.sin_addr.s_addr, server->h_addr, server->h_length);

    if (connect(sock, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        std::cerr << "[HTTP] Failed to connect to " << host << ":" << port << std::endl;
        close(sock);
        return response;
    }

    // Build HTTP request
    std::ostringstream request;
    request << "POST " << path << " HTTP/1.1\r\n";
    request << "Host: " << host << ":" << port << "\r\n";
    request << "Content-Type: application/json\r\n";
    request << "Content-Length: " << json_body.size() << "\r\n";
    request << "Connection: close\r\n";
    request << "\r\n";
    request << json_body;

    std::string request_str = request.str();

    // Send request
    if (send(sock, request_str.c_str(), request_str.size(), 0) < 0) {
        std::cerr << "[HTTP] Failed to send request" << std::endl;
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
        std::cerr << "[HTTP] Invalid response (no header end)" << std::endl;
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

// Simple HTTP GET request
static HttpResponse http_get(const std::string& url, int timeout_ms = 5000) {
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

// Extract "text" field from JSON response (simple parser)
static std::string extract_json_text(const std::string& json) {
    // Look for "text": "..." pattern
    // Using escaped regex instead of raw string literal
    std::regex text_regex("\"text\"\\s*:\\s*\"([^\"]*)\"");
    std::smatch match;
    if (std::regex_search(json, match, text_regex)) {
        return match[1].str();
    }
    return "";
}

// =============================================================================
// Constants (matching iOS VoiceSession behavior)
// =============================================================================

// Minimum silence duration before treating speech as ended (iOS uses 1.5s)
static constexpr double SILENCE_DURATION_SEC = 1.5;

// Minimum accumulated speech samples before processing (iOS uses 16000 = 0.5s at 16kHz)
static constexpr size_t MIN_SPEECH_SAMPLES = 16000;

// Wake word detection timeout - return to listening after this many seconds of silence
static constexpr double WAKE_WORD_TIMEOUT_SEC = 10.0;

// =============================================================================
// Implementation
// =============================================================================

struct VoicePipeline::Impl {
    rac_voice_agent_handle_t voice_agent = nullptr;

    // Wake word detector
    rac_handle_t wakeword_handle = nullptr;
    bool wakeword_enabled = false;
    bool wakeword_activated = false;  // True after wake word detected, until command processed
    std::chrono::steady_clock::time_point wakeword_activation_time;

    // State
    bool speech_active = false;
    std::vector<int16_t> speech_buffer;

    // Timestamp-based silence tracking (matches iOS VoiceSession pattern)
    std::chrono::steady_clock::time_point last_speech_time;
    bool speech_callback_fired = false;  // Whether we notified "listening"
};

VoicePipeline::VoicePipeline()
    : impl_(std::make_unique<Impl>()) {
}

VoicePipeline::VoicePipeline(const VoicePipelineConfig& config)
    : impl_(std::make_unique<Impl>())
    , config_(config) {
}

VoicePipeline::~VoicePipeline() {
    stop();
    if (impl_->wakeword_handle) {
        rac_wakeword_onnx_destroy(impl_->wakeword_handle);
        impl_->wakeword_handle = nullptr;
    }
    if (impl_->voice_agent) {
        rac_voice_agent_destroy(impl_->voice_agent);
        impl_->voice_agent = nullptr;
    }
}

bool VoicePipeline::initialize() {
    if (initialized_) {
        return true;
    }

    // Initialize model system (sets base directory)
    if (!init_model_system()) {
        last_error_ = "Failed to initialize model system";
        return false;
    }

    // Check if all models are available (skip LLM in moltbot mode)
    if (!are_all_models_available(config_.enable_moltbot)) {
        last_error_ = "One or more models are missing. Run scripts/download-models.sh";
        print_model_status(false, config_.enable_moltbot);
        return false;
    }

    // Initialize wake word detector if enabled
    if (config_.enable_wake_word) {
        if (!initialize_wakeword()) {
            // Wake word init failed, but continue without it
            std::cerr << "Wake word initialization failed, continuing without wake word\n";
            impl_->wakeword_enabled = false;
        } else {
            impl_->wakeword_enabled = true;
            std::cout << "  Wake word detection enabled: \"" << config_.wake_word << "\"\n";
        }
    }

    // Create standalone voice agent
    rac_result_t result = rac_voice_agent_create_standalone(&impl_->voice_agent);
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to create voice agent";
        return false;
    }

    // Get model paths
    std::string stt_path = get_stt_model_path();
    std::string llm_path = get_llm_model_path();
    std::string tts_path = get_tts_model_path();

    std::cout << "Loading models..." << std::endl;

    // Load STT model
    std::cout << "  Loading STT: " << STT_MODEL_ID << std::endl;
    result = rac_voice_agent_load_stt_model(
        impl_->voice_agent,
        stt_path.c_str(),
        STT_MODEL_ID,
        "Whisper Tiny English"
    );
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to load STT model: " + stt_path;
        return false;
    }

    // Load LLM model (skip in moltbot mode — LLM runs remotely)
    if (!config_.enable_moltbot) {
        std::cout << "  Loading LLM: " << LLM_MODEL_ID << std::endl;
        result = rac_voice_agent_load_llm_model(
            impl_->voice_agent,
            llm_path.c_str(),
            LLM_MODEL_ID,
            "Qwen2.5 0.5B"
        );
        if (result != RAC_SUCCESS) {
            last_error_ = "Failed to load LLM model: " + llm_path;
            return false;
        }
    } else {
        std::cout << "  LLM: skipped (moltbot mode — using remote agent)\n";
    }

    // Load TTS voice
    std::cout << "  Loading TTS: " << TTS_MODEL_ID << std::endl;
    result = rac_voice_agent_load_tts_voice(
        impl_->voice_agent,
        tts_path.c_str(),
        TTS_MODEL_ID,
        "Piper Lessac US"
    );
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to load TTS voice: " + tts_path;
        return false;
    }

    // Initialize with loaded models
    result = rac_voice_agent_initialize_with_loaded_models(impl_->voice_agent);
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to initialize voice agent";
        return false;
    }

    std::cout << "All models loaded successfully!" << std::endl;
    initialized_ = true;
    return true;
}

bool VoicePipeline::initialize_wakeword() {
    // Check if wake word models are available
    if (!are_wakeword_models_available()) {
        last_error_ = "Wake word models not available";
        return false;
    }

    // Create wake word detector with default config
    rac_wakeword_onnx_config_t ww_config = RAC_WAKEWORD_ONNX_CONFIG_DEFAULT;
    ww_config.threshold = config_.wake_word_threshold;

    rac_result_t result = rac_wakeword_onnx_create(&ww_config, &impl_->wakeword_handle);
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to create wake word detector";
        return false;
    }

    // Get model paths
    std::string embedding_path = get_wakeword_embedding_path();
    std::string melspec_path = get_wakeword_melspec_path();
    std::string wakeword_path = get_wakeword_model_path();

    std::cout << "  Loading Wake Word models..." << std::endl;

    // Initialize shared models (embedding + melspectrogram for openWakeWord pipeline)
    result = rac_wakeword_onnx_init_shared_models(
        impl_->wakeword_handle,
        embedding_path.c_str(),
        melspec_path.c_str()
    );
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to load wake word embedding model: " + embedding_path;
        rac_wakeword_onnx_destroy(impl_->wakeword_handle);
        impl_->wakeword_handle = nullptr;
        return false;
    }

    // Load the wake word model
    result = rac_wakeword_onnx_load_model(
        impl_->wakeword_handle,
        wakeword_path.c_str(),
        WAKEWORD_MODEL_ID,
        config_.wake_word.c_str()
    );
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to load wake word model: " + wakeword_path;
        rac_wakeword_onnx_destroy(impl_->wakeword_handle);
        impl_->wakeword_handle = nullptr;
        return false;
    }

    std::cout << "  Wake word model loaded: " << config_.wake_word << std::endl;
    return true;
}

bool VoicePipeline::is_ready() const {
    if (!impl_->voice_agent) {
        return false;
    }
    rac_bool_t ready = RAC_FALSE;
    rac_voice_agent_is_ready(impl_->voice_agent, &ready);
    return ready == RAC_TRUE;
}

void VoicePipeline::process_audio(const int16_t* samples, size_t num_samples) {
    if (!initialized_ || !running_) {
        return;
    }

    // Convert to float for processing
    std::vector<float> float_samples(num_samples);
    for (size_t i = 0; i < num_samples; ++i) {
        float_samples[i] = samples[i] / 32768.0f;
    }

    auto now = std::chrono::steady_clock::now();

    // If wake word is enabled and not yet activated, check for wake word first
    if (impl_->wakeword_enabled && !impl_->wakeword_activated) {
        int32_t detected_index = -1;
        float confidence = 0.0f;

        rac_result_t result = rac_wakeword_onnx_process(
            impl_->wakeword_handle,
            float_samples.data(),
            num_samples,
            &detected_index,
            &confidence
        );

        if (result == RAC_SUCCESS && detected_index >= 0) {
            // Wake word detected!
            impl_->wakeword_activated = true;
            impl_->wakeword_activation_time = now;
            impl_->speech_buffer.clear();
            impl_->speech_active = false;
            impl_->speech_callback_fired = false;

            // Fire wake word callback
            if (config_.on_wake_word) {
                config_.on_wake_word(config_.wake_word, confidence);
            }
        }

        // Don't process further until wake word is detected
        return;
    }

    // Check for wake word timeout (return to wake word listening mode)
    if (impl_->wakeword_enabled && impl_->wakeword_activated && !impl_->speech_active) {
        double elapsed = std::chrono::duration<double>(
            now - impl_->wakeword_activation_time
        ).count();

        if (elapsed >= WAKE_WORD_TIMEOUT_SEC) {
            // Timeout - go back to listening for wake word
            impl_->wakeword_activated = false;
            impl_->speech_buffer.clear();
            impl_->speech_callback_fired = false;
            return;
        }
    }

    // Detect speech via VAD
    rac_bool_t is_speech = RAC_FALSE;
    rac_voice_agent_detect_speech(
        impl_->voice_agent,
        float_samples.data(),
        num_samples,
        &is_speech
    );

    bool speech_detected = (is_speech == RAC_TRUE);

    if (speech_detected) {
        // Update last speech timestamp
        impl_->last_speech_time = now;

        // Also update wake word activation time to keep session alive
        if (impl_->wakeword_enabled) {
            impl_->wakeword_activation_time = now;
        }

        if (!impl_->speech_active) {
            // Speech just started — begin accumulating
            impl_->speech_active = true;
            impl_->speech_buffer.clear();
            impl_->speech_callback_fired = false;
        }

        // Fire "listening" callback once we have enough samples
        if (!impl_->speech_callback_fired
            && impl_->speech_buffer.size() + num_samples >= MIN_SPEECH_SAMPLES) {
            impl_->speech_callback_fired = true;
            if (config_.on_voice_activity) {
                config_.on_voice_activity(true);
            }
        }
    }

    // Accumulate audio while speech session is active (including silence grace period)
    if (impl_->speech_active) {
        impl_->speech_buffer.insert(
            impl_->speech_buffer.end(),
            samples, samples + num_samples
        );
    }

    // Check if silence has lasted long enough to end the speech session
    if (impl_->speech_active && !speech_detected) {
        double silence_elapsed = std::chrono::duration<double>(
            now - impl_->last_speech_time
        ).count();

        if (silence_elapsed >= SILENCE_DURATION_SEC) {
            // Silence timeout reached — end speech session
            impl_->speech_active = false;

            if (config_.on_voice_activity) {
                config_.on_voice_activity(false);
            }

            // Only process if we accumulated enough speech
            if (impl_->speech_buffer.size() >= MIN_SPEECH_SAMPLES) {
                process_voice_turn(
                    impl_->speech_buffer.data(),
                    impl_->speech_buffer.size()
                );
            }

            impl_->speech_buffer.clear();
            impl_->speech_callback_fired = false;

            // After processing command, go back to wake word mode
            if (impl_->wakeword_enabled) {
                impl_->wakeword_activated = false;
                rac_wakeword_onnx_reset(impl_->wakeword_handle);
            }
        }
    }
}

bool VoicePipeline::process_voice_turn(const int16_t* samples, size_t num_samples) {
    if (!initialized_) {
        return false;
    }

    // If Moltbot integration is enabled, use STT-only then send to Moltbot
    if (config_.enable_moltbot) {
        return process_voice_turn_moltbot(samples, num_samples);
    }

    // Use voice agent to process complete turn (local STT -> LLM -> TTS)
    rac_voice_agent_result_t result = {};

    rac_result_t status = rac_voice_agent_process_voice_turn(
        impl_->voice_agent,
        samples,
        num_samples * sizeof(int16_t),
        &result
    );

    if (status != RAC_SUCCESS) {
        if (config_.on_error) {
            config_.on_error("Voice processing failed");
        }
        return false;
    }

    // Report transcription
    if (result.transcription && config_.on_transcription) {
        config_.on_transcription(result.transcription, true);
    }

    // Report LLM response
    if (result.response && config_.on_response) {
        config_.on_response(result.response, true);
    }

    // Report TTS audio
    if (result.synthesized_audio && result.synthesized_audio_size > 0 && config_.on_audio_output) {
        // Assume 22050 Hz output from TTS (common rate)
        config_.on_audio_output(
            static_cast<const int16_t*>(result.synthesized_audio),
            result.synthesized_audio_size / sizeof(int16_t),
            22050
        );
    }

    // Free result
    rac_voice_agent_result_free(&result);

    return result.speech_detected == RAC_TRUE;
}

bool VoicePipeline::process_voice_turn_moltbot(const int16_t* samples, size_t num_samples) {
    // Step 1: Transcribe using local STT
    // Note: voice_agent_transcribe expects raw audio bytes (int16), not float
    char* transcription_ptr = nullptr;
    rac_result_t status = rac_voice_agent_transcribe(
        impl_->voice_agent,
        samples,
        num_samples * sizeof(int16_t),
        &transcription_ptr
    );

    if (status != RAC_SUCCESS || !transcription_ptr || strlen(transcription_ptr) == 0) {
        if (config_.on_error) {
            config_.on_error("STT transcription failed");
        }
        if (transcription_ptr) {
            free(transcription_ptr);
        }
        return false;
    }

    std::string transcription = transcription_ptr;
    free(transcription_ptr);

    // Report transcription
    if (config_.on_transcription) {
        config_.on_transcription(transcription, true);
    }

    // Step 2: Send transcription to Moltbot voice bridge
    std::string voice_bridge_url = config_.moltbot_voice_bridge_url + "/transcription";

    // Build JSON request
    std::ostringstream json;
    json << "{\"text\":\"";
    // Escape special characters in transcription
    for (char c : transcription) {
        if (c == '"') json << "\\\"";
        else if (c == '\\') json << "\\\\";
        else if (c == '\n') json << "\\n";
        else if (c == '\r') json << "\\r";
        else if (c == '\t') json << "\\t";
        else json << c;
    }
    json << "\",\"sessionId\":\"" << config_.moltbot_session_id << "\"}";

    std::cout << "[Moltbot] Sending to voice bridge: " << transcription << std::endl;

    HttpResponse http_response = http_post(voice_bridge_url, json.str(), 30000);

    if (!http_response.success) {
        std::cerr << "[Moltbot] Voice bridge request failed (status=" << http_response.status_code << ")" << std::endl;
        if (config_.on_error) {
            config_.on_error("Moltbot voice bridge request failed");
        }
        return false;
    }

    // Extract response text from JSON
    std::string response_text = extract_json_text(http_response.body);

    if (response_text.empty()) {
        std::cerr << "[Moltbot] Empty response from voice bridge" << std::endl;
        response_text = "I received your message but couldn't generate a response.";
    }

    std::cout << "[Moltbot] Response: " << response_text << std::endl;

    // Report LLM response
    if (config_.on_response) {
        config_.on_response(response_text, true);
    }

    // Step 3: Synthesize response using local TTS
    void* audio_data = nullptr;
    size_t audio_size = 0;
    status = rac_voice_agent_synthesize_speech(
        impl_->voice_agent,
        response_text.c_str(),
        &audio_data,
        &audio_size
    );

    if (status == RAC_SUCCESS && audio_data && audio_size > 0) {
        if (config_.on_audio_output) {
            config_.on_audio_output(
                static_cast<const int16_t*>(audio_data),
                audio_size / sizeof(int16_t),
                22050  // Default TTS sample rate
            );
        }
        free(audio_data);
    }

    return true;
}

bool VoicePipeline::speak_text(const std::string& text) {
    if (!initialized_ || !impl_->voice_agent) {
        return false;
    }

    // Synthesize speech using local TTS
    void* audio_data = nullptr;
    size_t audio_size = 0;
    rac_result_t status = rac_voice_agent_synthesize_speech(
        impl_->voice_agent,
        text.c_str(),
        &audio_data,
        &audio_size
    );

    if (status == RAC_SUCCESS && audio_data && audio_size > 0) {
        if (config_.on_audio_output) {
            config_.on_audio_output(
                static_cast<const int16_t*>(audio_data),
                audio_size / sizeof(int16_t),
                22050  // Default TTS sample rate
            );
        }
        free(audio_data);
        return true;
    }

    return false;
}

bool VoicePipeline::poll_speak_queue() {
    if (!config_.enable_moltbot || config_.moltbot_voice_bridge_url.empty()) {
        return false;
    }

    // Poll the /speak endpoint
    std::string speak_url = config_.moltbot_voice_bridge_url + "/speak";

    HttpResponse response = http_get(speak_url, 2000);  // 2 second timeout

    if (!response.success || response.body.empty()) {
        return false;
    }

    // Parse JSON response: {"text": "...", "sourceChannel": "..."}
    // or {"text": null} if no message
    std::string text = extract_json_text(response.body);

    if (text.empty()) {
        return false;
    }

    // Extract source channel for logging
    std::string source = "unknown";
    size_t source_pos = response.body.find("\"sourceChannel\"");
    if (source_pos != std::string::npos) {
        size_t colon = response.body.find(':', source_pos);
        size_t quote1 = response.body.find('"', colon);
        size_t quote2 = response.body.find('"', quote1 + 1);
        if (quote1 != std::string::npos && quote2 != std::string::npos) {
            source = response.body.substr(quote1 + 1, quote2 - quote1 - 1);
        }
    }

    std::cout << "[Moltbot] Speaking message from " << source << ": " << text << std::endl;

    // Report as response
    if (config_.on_response) {
        config_.on_response(text, true);
    }

    // Speak the text
    return speak_text(text);
}

void VoicePipeline::start() {
    running_ = true;
    impl_->wakeword_activated = false;  // Start in wake word listening mode
}

void VoicePipeline::stop() {
    running_ = false;
    impl_->speech_active = false;
    impl_->speech_buffer.clear();
    impl_->speech_callback_fired = false;
    impl_->wakeword_activated = false;
}

bool VoicePipeline::is_running() const {
    return running_;
}

void VoicePipeline::cancel() {
    // Cancel any ongoing generation
    // Note: Voice agent API may not support mid-generation cancellation
    impl_->speech_active = false;
    impl_->speech_buffer.clear();
    impl_->speech_callback_fired = false;

    // Return to wake word mode if enabled
    if (impl_->wakeword_enabled) {
        impl_->wakeword_activated = false;
        if (impl_->wakeword_handle) {
            rac_wakeword_onnx_reset(impl_->wakeword_handle);
        }
    }
}

void VoicePipeline::set_config(const VoicePipelineConfig& config) {
    config_ = config;
}

std::string VoicePipeline::get_stt_model_id() const {
    if (impl_->voice_agent) {
        const char* id = rac_voice_agent_get_stt_model_id(impl_->voice_agent);
        return id ? id : "";
    }
    return "";
}

std::string VoicePipeline::get_llm_model_id() const {
    if (impl_->voice_agent) {
        const char* id = rac_voice_agent_get_llm_model_id(impl_->voice_agent);
        return id ? id : "";
    }
    return "";
}

std::string VoicePipeline::get_tts_model_id() const {
    if (impl_->voice_agent) {
        const char* id = rac_voice_agent_get_tts_voice_id(impl_->voice_agent);
        return id ? id : "";
    }
    return "";
}

} // namespace runanywhere
