// =============================================================================
// Voice Pipeline - Implementation
// =============================================================================
// Simplified pipeline for OpenClaw: Wake Word → VAD → STT → (send to OpenClaw)
// TTS is called separately when speak commands arrive.
// Uses rac_voice_agent API - NO LLM loaded.
// =============================================================================

#include "voice_pipeline.h"
#include "tts_queue.h"
#include "model_config.h"

// RAC headers - use voice_agent for unified API
#include <rac/features/voice_agent/rac_voice_agent.h>
#include <rac/backends/rac_wakeword_onnx.h>
#include <rac/backends/rac_vad_onnx.h>
#include <rac/core/rac_error.h>

#include <vector>
#include <mutex>
#include <iostream>
#include <chrono>
#include <thread>
#include <cstring>

namespace openclaw {

// =============================================================================
// Constants
// =============================================================================

// Silence duration before treating speech as ended
static constexpr double DEFAULT_SILENCE_DURATION_SEC = 1.5;

// Delay after TTS finishes before re-enabling listening (prevents echo feedback)
static constexpr int TTS_COOLDOWN_MS = 500;

// Minimum speech samples before processing (avoid false triggers)
static constexpr size_t DEFAULT_MIN_SPEECH_SAMPLES = 16000;  // 1 second at 16kHz

// Wake word timeout - return to listening after this many seconds of no speech
static constexpr double WAKE_WORD_TIMEOUT_SEC = 10.0;

// Cooldown after wake word detection - ignore detections for this long
// to prevent the tail end of "Hey Jarvis" audio from re-triggering
static constexpr int WAKEWORD_COOLDOWN_MS = 1000;

// =============================================================================
// Text Sanitization for TTS
// =============================================================================
// Prepares text for natural-sounding speech synthesis by:
// 1. PRESERVING: Natural punctuation (. , ! ? : ; - ' ") for proper prosody
// 2. REMOVING: Markdown formatting (* _ ` # ~ [ ] { } < >)
// 3. REMOVING: Emojis and unicode symbols
// 4. CONVERTING: Symbols to spoken equivalents (& → "and", % → "percent")
// 5. NORMALIZING: Whitespace (collapse multiples, trim edges)
// =============================================================================

// Helper: Get UTF-8 sequence length from first byte
static inline size_t get_utf8_length(unsigned char c) {
    if ((c & 0x80) == 0) return 1;      // ASCII
    if ((c & 0xE0) == 0xC0) return 2;   // 2-byte sequence
    if ((c & 0xF0) == 0xE0) return 3;   // 3-byte sequence
    if ((c & 0xF8) == 0xF0) return 4;   // 4-byte sequence
    return 1;  // Invalid, treat as single byte
}

// Helper: Check if UTF-8 sequence is an emoji or special symbol to remove
// Returns true if the sequence should be skipped
static bool is_emoji_or_symbol(const std::string& input, size_t pos, size_t len) {
    if (len < 3 || pos + len > input.size()) return false;

    unsigned char c1 = static_cast<unsigned char>(input[pos]);
    unsigned char c2 = static_cast<unsigned char>(input[pos + 1]);

    // 4-byte sequences (0xF0-0xF4): Most emojis live here
    // Range U+1F000 to U+1FFFF (emoticons, symbols, pictographs)
    if (len == 4 && c1 == 0xF0) {
        // U+1F300-U+1FAFF: Miscellaneous Symbols and Pictographs, Emoticons, etc.
        // Generally skip all 4-byte sequences starting with F0 9F (emoji range)
        if (c2 == 0x9F) return true;
    }

    // 3-byte sequences starting with E2 (U+2000-U+2FFF)
    if (len == 3 && c1 == 0xE2) {
        // U+2000-U+206F: General Punctuation (some are okay, but symbols aren't)
        // U+2100-U+214F: Letterlike Symbols
        // U+2190-U+21FF: Arrows
        // U+2200-U+22FF: Mathematical Operators
        // U+2300-U+23FF: Miscellaneous Technical
        // U+2460-U+24FF: Enclosed Alphanumerics
        // U+2500-U+257F: Box Drawing
        // U+2580-U+259F: Block Elements
        // U+25A0-U+25FF: Geometric Shapes
        // U+2600-U+26FF: Miscellaneous Symbols
        // U+2700-U+27BF: Dingbats
        // U+2B00-U+2BFF: Miscellaneous Symbols and Arrows

        // Skip arrows, symbols, dingbats, etc. but keep some punctuation
        if (c2 >= 0x80 && c2 <= 0x8F) return false;  // Keep most general punctuation
        if (c2 >= 0x90 && c2 <= 0xBF) return true;   // Skip symbols, arrows, math ops
        if (c2 == 0xAD) return true;                  // Skip stars (⭐)
        if (c2 >= 0x9C && c2 <= 0x9E) return true;   // Skip dingbats, misc symbols
    }

    // 3-byte sequences starting with E3 (U+3000-U+3FFF): CJK symbols
    if (len == 3 && c1 == 0xE3) {
        if (c2 >= 0x80 && c2 <= 0x8F) return true;  // CJK punctuation/symbols
    }

    // Variation selectors and zero-width characters (often paired with emoji)
    if (len == 3 && c1 == 0xEF) {
        // U+FE00-U+FE0F: Variation Selectors
        // U+FEFF: BOM / Zero Width No-Break Space
        if (c2 == 0xB8 || c2 == 0xBB) return true;
    }

    return false;
}

// Helper: Convert common symbols to spoken words
// Returns empty string if no conversion needed (symbol should be removed)
// Returns the symbol itself if it should be kept as-is
static std::string convert_symbol_to_spoken(char c, char prev, char next, bool has_prev, bool has_next) {
    switch (c) {
        // Symbols that should be converted to words
        case '&':
            return " and ";

        case '%':
            // Only say "percent" if preceded by a number
            if (has_prev && (prev >= '0' && prev <= '9')) {
                return " percent";
            }
            return "";  // Remove if not after a number

        case '$':
            // Dollar sign before number: keep for context
            // TTS engines typically handle "$100" well
            if (has_next && (next >= '0' && next <= '9')) {
                return "$";
            }
            return " dollars ";  // Standalone dollar sign

        case '+':
            // Plus sign between numbers/words: "plus" or remove
            if (has_prev && has_next) {
                return " plus ";
            }
            return "";

        case '=':
            // Equals sign: "equals"
            if (has_prev && has_next) {
                return " equals ";
            }
            return "";

        case '/':
            // Slash: "or" or "slash" depending on context
            if (has_prev && has_next) {
                return " or ";
            }
            return " ";

        // Symbols to remove entirely
        case '*':   // Markdown bold/italic
        case '_':   // Markdown italic (but keep if between letters for compound words)
        case '`':   // Markdown code
        case '#':   // Markdown headers
        case '~':   // Markdown strikethrough
        case '[':   // Markdown links
        case ']':
        case '{':   // Braces
        case '}':
        case '<':   // Angle brackets (HTML/XML)
        case '>':
        case '|':   // Pipe
        case '\\':  // Backslash
        case '^':   // Caret
        case '@':   // At sign (usually in mentions/emails)
            return "";

        // Symbols to convert to space (natural pause)
        case '"':
            // Double quotes: remove but keep sentence flow
            return "";

        default:
            // Keep the character as-is
            std::string s;
            s += c;
            return s;
    }
}

// Main sanitization function
static std::string sanitize_text_for_tts(const std::string& input) {
    if (input.empty()) return input;

    // Pre-process: handle literal \n sequences (backslash + n) from JSON.
    // OpenClaw sends "\n" as a literal two-char sequence, which the character-level
    // sanitizer below would strip the backslash and keep the 'n', producing "nn".
    std::string preprocessed;
    preprocessed.reserve(input.size());
    for (size_t j = 0; j < input.size(); ++j) {
        if (input[j] == '\\' && j + 1 < input.size()) {
            char next = input[j + 1];
            if (next == 'n' || next == 'r' || next == 't') {
                // Replace \n, \r, \t with space (collapse multiple into one)
                if (!preprocessed.empty() && preprocessed.back() != ' ') {
                    preprocessed += ' ';
                }
                ++j;  // skip the escaped character
                continue;
            }
        }
        preprocessed += input[j];
    }

    std::string result;
    result.reserve(preprocessed.size() * 1.2);  // May expand slightly due to word replacements

    size_t i = 0;
    while (i < preprocessed.size()) {
        unsigned char c = static_cast<unsigned char>(preprocessed[i]);

        // --- Handle multi-byte UTF-8 sequences ---
        size_t utf8_len = get_utf8_length(c);
        if (utf8_len > 1) {
            // Check if it's an emoji or symbol to skip
            if (is_emoji_or_symbol(preprocessed, i, utf8_len)) {
                // Skip the entire sequence, optionally add space to maintain word boundaries
                if (!result.empty() && result.back() != ' ') {
                    result += ' ';
                }
                i += utf8_len;
                continue;
            }
            // Keep valid UTF-8 text (international characters)
            for (size_t j = 0; j < utf8_len && i + j < preprocessed.size(); ++j) {
                result += preprocessed[i + j];
            }
            i += utf8_len;
            continue;
        }

        // --- Handle ASCII characters ---

        // Characters to preserve for natural prosody (TTS uses these for pacing)
        // Period, comma, exclamation, question mark, colon, semicolon
        if (c == '.' || c == ',' || c == '!' || c == '?' || c == ':' || c == ';') {
            result += c;
            i++;
            continue;
        }

        // Apostrophe: Keep for contractions (don't, it's, we'll)
        if (c == '\'') {
            result += c;
            i++;
            continue;
        }

        // Hyphen/dash: Keep single hyphens, collapse multiple dashes (---, —)
        if (c == '-') {
            // Skip if previous char was also a dash
            if (!result.empty() && result.back() == '-') {
                i++;
                continue;
            }
            result += c;
            i++;
            continue;
        }

        // Parentheses: Keep for natural grouping (TTS handles these okay)
        if (c == '(' || c == ')') {
            result += c;
            i++;
            continue;
        }

        // Letters (a-z, A-Z) and digits (0-9): Always keep
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) {
            result += c;
            i++;
            continue;
        }

        // Whitespace: Normalize to single space
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            // Only add space if result doesn't already end with one
            if (!result.empty() && result.back() != ' ') {
                result += ' ';
            }
            i++;
            continue;
        }

        // Special symbols: Convert or remove
        char prev_char = (i > 0) ? preprocessed[i - 1] : '\0';
        char next_char = (i + 1 < preprocessed.size()) ? preprocessed[i + 1] : '\0';

        std::string replacement = convert_symbol_to_spoken(
            static_cast<char>(c),
            prev_char,
            next_char,
            i > 0,
            i + 1 < preprocessed.size()
        );

        if (!replacement.empty()) {
            result += replacement;
        }
        i++;
    }

    // --- Final cleanup: Normalize whitespace ---
    std::string cleaned;
    cleaned.reserve(result.size());
    bool last_was_space = false;

    for (char c : result) {
        if (c == ' ') {
            if (!last_was_space && !cleaned.empty()) {
                cleaned += ' ';
                last_was_space = true;
            }
        } else {
            cleaned += c;
            last_was_space = false;
        }
    }

    // Trim trailing whitespace
    while (!cleaned.empty() && cleaned.back() == ' ') {
        cleaned.pop_back();
    }

    // Trim leading whitespace
    size_t start = 0;
    while (start < cleaned.size() && cleaned[start] == ' ') {
        start++;
    }
    if (start > 0) {
        cleaned = cleaned.substr(start);
    }

    return cleaned;
}

// =============================================================================
// Implementation
// =============================================================================

struct VoicePipeline::Impl {
    // Voice agent handle (for STT, TTS)
    rac_voice_agent_handle_t voice_agent = nullptr;

    // Silero VAD (ONNX-based, much more accurate than energy VAD)
    rac_handle_t silero_vad = nullptr;

    // Wake word detector (separate from voice agent)
    rac_handle_t wakeword_handle = nullptr;
    bool wakeword_enabled = false;
    bool wakeword_activated = false;
    std::chrono::steady_clock::time_point wakeword_activation_time;
    std::chrono::steady_clock::time_point wakeword_cooldown_until;  // Ignore detections until this time

    // Speech state
    bool speech_active = false;
    std::vector<int16_t> speech_buffer;
    std::chrono::steady_clock::time_point last_speech_time;
    bool speech_callback_fired = false;

    // Noise robustness state
    int consecutive_speech_frames = 0;     // Consecutive frames with speech detected
    int consecutive_silent_frames = 0;     // Consecutive frames with no speech
    int current_burst_frames = 0;          // Frames in current noise burst (after silence)
    std::chrono::steady_clock::time_point speech_start_time;  // When speech_active became true

    // Mutex for thread safety
    std::mutex mutex;
};

// =============================================================================
// Async TTS State - Manages producer thread + TTSQueue
// =============================================================================

struct VoicePipeline::AsyncTTSState {
    std::shared_ptr<TTSQueue> queue;
    std::atomic<bool> cancelled{false};
    std::thread producer_thread;

    // Non-blocking cancel for barge-in: signals producer to stop and silences audio.
    // Does NOT join the producer — the thread finishes on its own after the current
    // rac_voice_agent_synthesize_speech call returns. This avoids blocking the
    // capture thread for 1-9s during synthesis.
    // The next cleanup() or destructor will join the (already-finished) thread.
    void cancel_fast() {
        cancelled.store(true);
        if (queue) {
            queue->cancel();  // Signals consumer to stop; play_cancellable checks flag every ~46ms
        }
    }

    // Full cleanup: signal cancellation, join producer (blocks until synthesis finishes),
    // and release the queue. Called before creating a new producer or during destruction.
    void cleanup() {
        cancelled.store(true);
        if (queue) {
            queue->cancel();
        }
        if (producer_thread.joinable()) {
            producer_thread.join();
        }
        queue.reset();
        cancelled.store(false);
    }

    ~AsyncTTSState() {
        cleanup();
    }
};

VoicePipeline::VoicePipeline()
    : impl_(std::make_unique<Impl>())
    , async_tts_(std::make_unique<AsyncTTSState>()) {
}

VoicePipeline::VoicePipeline(const VoicePipelineConfig& config)
    : impl_(std::make_unique<Impl>())
    , async_tts_(std::make_unique<AsyncTTSState>())
    , config_(config) {
}

VoicePipeline::~VoicePipeline() {
    // Ensure the producer thread exits before we destroy voice_agent and other resources.
    if (async_tts_) {
        async_tts_->cleanup();
    }
    stop();

    if (impl_->silero_vad) {
        rac_vad_onnx_stop(impl_->silero_vad);
        rac_vad_onnx_destroy(impl_->silero_vad);
        impl_->silero_vad = nullptr;
    }
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

    // Initialize model system
    if (!init_model_system()) {
        last_error_ = "Failed to initialize model system";
        state_ = PipelineState::ERROR;
        return false;
    }

    // Check required models
    if (!are_all_models_available()) {
        last_error_ = "Required models are missing. Run scripts/download-models.sh";
        print_model_status(config_.enable_wake_word);
        state_ = PipelineState::ERROR;
        return false;
    }

    std::cout << "[Pipeline] Initializing components (NO LLM)...\n";

    // Create standalone voice agent
    rac_result_t result = rac_voice_agent_create_standalone(&impl_->voice_agent);
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to create voice agent";
        state_ = PipelineState::ERROR;
        return false;
    }

    // Get model paths
    std::string stt_path = get_stt_model_path();
    std::string tts_path = get_tts_model_path();

    // Load STT model (Parakeet TDT-CTC 110M - NeMo CTC, int8 quantized)
    std::cout << "  Loading STT: " << STT_MODEL_ID << "\n";
    result = rac_voice_agent_load_stt_model(
        impl_->voice_agent,
        stt_path.c_str(),
        STT_MODEL_ID,
        "Parakeet TDT-CTC 110M EN (int8)"
    );
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to load STT model: " + stt_path;
        state_ = PipelineState::ERROR;
        return false;
    }

    // Skip LLM - we don't need it for OpenClaw channel
    std::cout << "  LLM: skipped (OpenClaw mode - no local LLM)\n";

    // Load TTS voice (Piper Lessac Medium - VITS, 22050Hz, natural male voice)
    std::cout << "  Loading TTS: " << TTS_MODEL_ID << "\n";
    result = rac_voice_agent_load_tts_voice(
        impl_->voice_agent,
        tts_path.c_str(),
        TTS_MODEL_ID,
        "Piper Lessac Medium TTS"
    );
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to load TTS voice: " + tts_path;
        state_ = PipelineState::ERROR;
        return false;
    }

    // Initialize with loaded models
    result = rac_voice_agent_initialize_with_loaded_models(impl_->voice_agent);
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to initialize voice agent";
        state_ = PipelineState::ERROR;
        return false;
    }

    // Initialize Silero VAD (ONNX neural network - much more accurate than energy VAD)
    std::string vad_path = get_vad_model_path();
    std::cout << "  Loading VAD: Silero (ONNX)\n";

    rac_vad_onnx_config_t vad_config = RAC_VAD_ONNX_CONFIG_DEFAULT;
    vad_config.sample_rate = 16000;
    vad_config.energy_threshold = config_.vad_threshold;

    result = rac_vad_onnx_create(vad_path.c_str(), &vad_config, &impl_->silero_vad);
    if (result != RAC_SUCCESS) {
        std::cerr << "[Pipeline] WARNING: Failed to load Silero VAD, falling back to energy VAD\n";
        impl_->silero_vad = nullptr;
    } else {
        rac_vad_onnx_start(impl_->silero_vad);
        std::cout << "  Silero VAD loaded (threshold: " << config_.vad_threshold << ")\n";
    }

    // Initialize Wake Word (optional)
    if (config_.enable_wake_word) {
        std::cout << "  Loading Wake Word: " << WAKEWORD_MODEL_ID << "\n";
        if (!initialize_wakeword()) {
            std::cerr << "[Pipeline] Wake word init failed, continuing without it\n";
            impl_->wakeword_enabled = false;
        } else {
            impl_->wakeword_enabled = true;
            std::cout << "  Wake word enabled: \"" << config_.wake_word << "\"\n";
        }
    }

    std::cout << "[Pipeline] All components loaded successfully!\n";
    initialized_ = true;
    state_ = impl_->wakeword_enabled ? PipelineState::WAITING_FOR_WAKE_WORD : PipelineState::LISTENING;

    return true;
}

bool VoicePipeline::initialize_wakeword() {
    if (!are_wakeword_models_available()) {
        last_error_ = "Wake word models not available";
        return false;
    }

    // Create wake word detector
    rac_wakeword_onnx_config_t ww_config = RAC_WAKEWORD_ONNX_CONFIG_DEFAULT;
    ww_config.threshold = config_.wake_word_threshold;

    rac_result_t result = rac_wakeword_onnx_create(&ww_config, &impl_->wakeword_handle);
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to create wake word detector";
        return false;
    }

    // Load shared models
    std::string embedding_path = get_wakeword_embedding_path();
    std::string melspec_path = get_wakeword_melspec_path();
    std::string wakeword_path = get_wakeword_model_path();

    result = rac_wakeword_onnx_init_shared_models(
        impl_->wakeword_handle,
        embedding_path.c_str(),
        melspec_path.c_str()
    );
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to load wake word embedding model";
        rac_wakeword_onnx_destroy(impl_->wakeword_handle);
        impl_->wakeword_handle = nullptr;
        return false;
    }

    // Load wake word model
    result = rac_wakeword_onnx_load_model(
        impl_->wakeword_handle,
        wakeword_path.c_str(),
        WAKEWORD_MODEL_ID,
        config_.wake_word.c_str()
    );
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to load wake word model";
        rac_wakeword_onnx_destroy(impl_->wakeword_handle);
        impl_->wakeword_handle = nullptr;
        return false;
    }

    return true;
}

void VoicePipeline::start() {
    running_ = true;
    impl_->wakeword_activated = false;
    impl_->speech_active = false;
    impl_->speech_buffer.clear();
    impl_->speech_callback_fired = false;
    impl_->consecutive_speech_frames = 0;
    impl_->consecutive_silent_frames = 0;
    impl_->current_burst_frames = 0;

    if (impl_->wakeword_enabled) {
        state_ = PipelineState::WAITING_FOR_WAKE_WORD;
    } else {
        state_ = PipelineState::LISTENING;
    }
}

void VoicePipeline::stop() {
    running_ = false;
    impl_->speech_active = false;
    impl_->speech_buffer.clear();
    impl_->speech_callback_fired = false;
    impl_->wakeword_activated = false;
    impl_->consecutive_speech_frames = 0;
    impl_->consecutive_silent_frames = 0;
    impl_->current_burst_frames = 0;
}

bool VoicePipeline::is_running() const {
    return running_;
}

bool VoicePipeline::is_ready() const {
    if (!initialized_ || !impl_->voice_agent) {
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

    std::lock_guard<std::mutex> lock(impl_->mutex);

    // During TTS playback: ONLY run wake word detection for barge-in.
    // Skip VAD/STT to prevent echo feedback (mic picking up speaker output).
    // Wake word is resilient to echo because it's trained on a specific phrase,
    // not arbitrary speech - TTS audio won't trigger "Hey Jarvis".
    if (state_ == PipelineState::SPEAKING) {
        if (impl_->wakeword_enabled && impl_->wakeword_handle) {
            // Convert to raw float for openWakeWord (unnormalized)
            std::vector<float> raw(num_samples);
            for (size_t i = 0; i < num_samples; ++i) {
                raw[i] = static_cast<float>(samples[i]);
            }
            process_wakeword(raw.data(), num_samples);
        }
        return;
    }

    // Convert to float for processing
    // NOTE: Different components need different normalization:
    // - Wake word (openWakeWord): Raw int16 cast to float (no normalization)
    // - VAD/STT: Normalized to [-1, 1] (divide by 32768)
    std::vector<float> float_samples(num_samples);
    std::vector<float> float_samples_raw(num_samples);  // For wake word (unnormalized)
    for (size_t i = 0; i < num_samples; ++i) {
        float_samples[i] = samples[i] / 32768.0f;       // Normalized for VAD/STT
        float_samples_raw[i] = static_cast<float>(samples[i]);  // Raw for wake word
    }

    auto now = std::chrono::steady_clock::now();

    // Stage 1: Wake Word Detection (if enabled and not activated)
    if (impl_->wakeword_enabled && !impl_->wakeword_activated) {
        process_wakeword(float_samples_raw.data(), num_samples);  // Use raw (unnormalized) for openWakeWord
        return;  // Don't process further until wake word detected
    }

    // Check wake word timeout
    if (impl_->wakeword_enabled && impl_->wakeword_activated && !impl_->speech_active) {
        double elapsed = std::chrono::duration<double>(
            now - impl_->wakeword_activation_time
        ).count();

        if (elapsed >= WAKE_WORD_TIMEOUT_SEC) {
            if (config_.debug_wakeword) {
                std::cout << "[WakeWord] Timeout, returning to wake word mode\n";
            }
            impl_->wakeword_activated = false;
            impl_->speech_buffer.clear();
            impl_->speech_callback_fired = false;
            state_ = PipelineState::WAITING_FOR_WAKE_WORD;
            return;
        }
    }

    // Stage 2: VAD + Speech Buffering
    process_vad(float_samples.data(), num_samples, samples);
}

void VoicePipeline::process_wakeword(const float* samples, size_t num_samples) {
    if (!impl_->wakeword_handle) {
        return;
    }

    // Cooldown: ignore detections for WAKEWORD_COOLDOWN_MS after the last detection
    // to prevent the tail end of "Hey Jarvis" audio from re-triggering
    auto now = std::chrono::steady_clock::now();
    if (now < impl_->wakeword_cooldown_until) {
        // Still in cooldown - feed audio to the model (to keep it in sync)
        // but ignore the result
        int32_t ignored_index = -1;
        float ignored_conf = 0.0f;
        rac_wakeword_onnx_process(impl_->wakeword_handle, samples, num_samples,
                                   &ignored_index, &ignored_conf);
        return;
    }

    int32_t detected_index = -1;
    float confidence = 0.0f;

    rac_result_t result = rac_wakeword_onnx_process(
        impl_->wakeword_handle,
        samples,
        num_samples,
        &detected_index,
        &confidence
    );

    if (config_.debug_wakeword && confidence > 0.1f) {
        std::cout << "[WakeWord] Confidence: " << confidence << "\n";
    }

    if (result == RAC_SUCCESS && detected_index >= 0) {
        // Wake word detected!
        bool was_bargein = (state_ == PipelineState::SPEAKING);

        // Barge-in: if TTS is currently playing, cancel it immediately
        if (was_bargein) {
            std::cout << "[WakeWord] Barge-in! Cancelling TTS playback...\n";
            // cancel_speech() stops producer thread + TTSQueue consumer + clears everything
            // Must unlock mutex before cancel_speech (it may join threads)
            impl_->mutex.unlock();
            cancel_speech();
            impl_->mutex.lock();

            // Fire interrupt callback so main.cpp can stop chime/cleanup
            if (config_.on_speech_interrupted) {
                config_.on_speech_interrupted();
            }
        }

        impl_->wakeword_activated = true;
        impl_->wakeword_activation_time = std::chrono::steady_clock::now();
        impl_->wakeword_cooldown_until = impl_->wakeword_activation_time
            + std::chrono::milliseconds(WAKEWORD_COOLDOWN_MS);
        impl_->speech_buffer.clear();
        impl_->speech_active = false;
        impl_->speech_callback_fired = false;
        impl_->consecutive_speech_frames = 0;
        impl_->consecutive_silent_frames = 0;
        impl_->current_burst_frames = 0;
        state_ = PipelineState::LISTENING;

        // Reset wake word model's internal streaming buffers so the same
        // "Hey Jarvis" pattern doesn't re-trigger on subsequent frames
        rac_wakeword_onnx_reset(impl_->wakeword_handle);

        // Only reset Silero VAD during barge-in (TTS was playing, mic had echo).
        // During normal wake word detection, keep VAD state intact so it can
        // immediately detect the trailing speech ("Hey Jarvis, what's the weather?")
        if (was_bargein && impl_->silero_vad) {
            rac_vad_onnx_reset(impl_->silero_vad);
        }

        std::cout << "[WakeWord] Detected: \"" << config_.wake_word
                  << "\" (confidence: " << confidence << ")\n";

        if (config_.on_wake_word) {
            config_.on_wake_word(config_.wake_word, confidence);
        }
    }
}

void VoicePipeline::process_vad(const float* samples, size_t num_samples, const int16_t* raw_samples) {
    if (!impl_->voice_agent) {
        return;
    }

    auto now = std::chrono::steady_clock::now();

    // Detect speech: prefer Silero VAD (ONNX neural network) if loaded,
    // fall back to energy VAD (built into voice agent) if not.
    rac_bool_t is_speech = RAC_FALSE;
    if (impl_->silero_vad) {
        rac_vad_onnx_process(impl_->silero_vad, samples, num_samples, &is_speech);
    } else {
        rac_voice_agent_detect_speech(impl_->voice_agent, samples, num_samples, &is_speech);
    }

    bool speech_detected = (is_speech == RAC_TRUE);

    // --- Noise robustness: track consecutive speech/silent frames ---
    int start_frames_needed = config_.speech_start_frames > 0 ? config_.speech_start_frames : 3;
    int noise_burst_max = config_.noise_burst_max_frames > 0 ? config_.noise_burst_max_frames : 2;
    double max_speech_sec = config_.max_speech_duration_sec > 0 ? config_.max_speech_duration_sec : 60.0;

    if (speech_detected) {
        impl_->consecutive_speech_frames++;
        impl_->consecutive_silent_frames = 0;
    } else {
        impl_->consecutive_silent_frames++;
        impl_->consecutive_speech_frames = 0;
    }

    if (config_.debug_vad) {
        static int frame_count = 0;
        if (++frame_count % 50 == 0) {  // Log every 50 frames
            std::cout << "[VAD] Speech: " << (speech_detected ? "YES" : "no")
                      << ", Buffer: " << impl_->speech_buffer.size() << " samples"
                      << ", ConsecSpeech: " << impl_->consecutive_speech_frames
                      << ", ConsecSilent: " << impl_->consecutive_silent_frames << "\n";
        }
    }

    if (speech_detected) {
        if (impl_->wakeword_enabled) {
            impl_->wakeword_activation_time = now;
        }

        if (!impl_->speech_active) {
            // --- Debounce: require multiple consecutive speech frames to start ---
            // This prevents fan noise bursts from triggering speech detection.
            if (impl_->consecutive_speech_frames < start_frames_needed) {
                return;  // Not enough consecutive speech yet, wait for more
            }

            // Enough consecutive speech frames — start speech session
            impl_->speech_active = true;
            impl_->speech_buffer.clear();
            impl_->speech_callback_fired = false;
            impl_->last_speech_time = now;
            impl_->speech_start_time = now;
            impl_->current_burst_frames = 0;

            if (config_.debug_vad) {
                std::cout << "[VAD] Speech started (after " << start_frames_needed << " consecutive frames)\n";
            }
        } else {
            // Speech was already active — update last speech time.
            // But only count as "real speech" if this burst is long enough.
            impl_->current_burst_frames++;
            if (impl_->current_burst_frames >= noise_burst_max) {
                // This is a sustained speech burst, reset the silence timer
                impl_->last_speech_time = now;
            }
        }

        // Fire "listening" callback once we have enough samples
        size_t min_samples = config_.min_speech_samples > 0 ? config_.min_speech_samples : DEFAULT_MIN_SPEECH_SAMPLES;
        if (!impl_->speech_callback_fired && impl_->speech_buffer.size() + num_samples >= min_samples / 2) {
            impl_->speech_callback_fired = true;
            if (config_.on_voice_activity) {
                config_.on_voice_activity(true);
            }
        }
    } else if (impl_->speech_active) {
        // Silent frame during active speech — reset burst counter
        impl_->current_burst_frames = 0;
    }

    // Accumulate audio while speech session is active
    if (impl_->speech_active) {
        impl_->speech_buffer.insert(
            impl_->speech_buffer.end(),
            raw_samples, raw_samples + num_samples
        );
    }

    // --- End of speech detection ---
    // Two conditions can end speech:
    // 1. Silence timeout: no sustained speech for silence_duration_sec
    // 2. Max duration: speech has been going on too long (prevents infinite buffering)

    if (!impl_->speech_active) {
        return;
    }

    bool should_end = false;
    const char* end_reason = nullptr;

    // Check silence timeout
    double silence_duration = config_.silence_duration_sec > 0 ? config_.silence_duration_sec : DEFAULT_SILENCE_DURATION_SEC;
    double silence_elapsed = std::chrono::duration<double>(now - impl_->last_speech_time).count();

    if (silence_elapsed >= silence_duration) {
        should_end = true;
        end_reason = "silence timeout";
    }

    // Check max speech duration
    double speech_elapsed = std::chrono::duration<double>(now - impl_->speech_start_time).count();
    if (speech_elapsed >= max_speech_sec) {
        should_end = true;
        end_reason = "max duration reached";
    }

    if (should_end) {
        // End of speech
        impl_->speech_active = false;
        impl_->consecutive_speech_frames = 0;
        impl_->consecutive_silent_frames = 0;
        impl_->current_burst_frames = 0;
        state_ = PipelineState::PROCESSING_STT;

        if (config_.debug_vad) {
            std::cout << "[VAD] Speech ended (" << end_reason << "), "
                      << impl_->speech_buffer.size() << " samples buffered ("
                      << (float)impl_->speech_buffer.size() / 16000.0f << "s)\n";
        }

        if (config_.on_voice_activity) {
            config_.on_voice_activity(false);
        }

        // Process STT if we have enough speech
        size_t min_samples = config_.min_speech_samples > 0 ? config_.min_speech_samples : DEFAULT_MIN_SPEECH_SAMPLES;
        if (impl_->speech_buffer.size() >= min_samples) {
            process_stt(impl_->speech_buffer.data(), impl_->speech_buffer.size());
        } else if (config_.debug_stt) {
            std::cout << "[STT] Not enough speech (" << impl_->speech_buffer.size()
                      << " < " << min_samples << ")\n";
        }

        // Reset state
        impl_->speech_buffer.clear();
        impl_->speech_callback_fired = false;

        // Return to wake word mode if enabled
        if (impl_->wakeword_enabled) {
            impl_->wakeword_activated = false;
            rac_wakeword_onnx_reset(impl_->wakeword_handle);
            state_ = PipelineState::WAITING_FOR_WAKE_WORD;
        } else {
            state_ = PipelineState::LISTENING;
        }
    }
}

bool VoicePipeline::process_stt(const int16_t* samples, size_t num_samples) {
    if (!impl_->voice_agent) {
        return false;
    }

    if (config_.debug_stt) {
        std::cout << "[STT] Processing " << num_samples << " samples ("
                  << (float)num_samples / 16000.0f << "s)\n";
    }

    // Transcribe using voice agent
    char* transcription_ptr = nullptr;
    rac_result_t result = rac_voice_agent_transcribe(
        impl_->voice_agent,
        samples,
        num_samples * sizeof(int16_t),
        &transcription_ptr
    );

    if (result != RAC_SUCCESS || !transcription_ptr || strlen(transcription_ptr) == 0) {
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

    std::cout << "[STT] Transcription: \"" << transcription << "\"\n";

    // Fire callback (this will send to OpenClaw)
    if (config_.on_transcription) {
        config_.on_transcription(transcription, true);
    }

    return true;
}

// =============================================================================
// Sentence Splitting - Abbreviation-aware
// =============================================================================
// Splits text at sentence boundaries (. ! ?) while avoiding false splits on
// common abbreviations like "Mr.", "Dr.", "e.g.", "U.S.", "a.m.", etc.

// Check if the word before a period is a common abbreviation
static bool is_abbreviation(const std::string& text, size_t dot_pos) {
    // Walk backward to find the start of the word
    if (dot_pos == 0) return false;

    size_t word_end = dot_pos;
    size_t word_start = dot_pos;
    while (word_start > 0 && text[word_start - 1] != ' ' && text[word_start - 1] != '\n') {
        --word_start;
    }

    // Extract the word (lowercase for comparison)
    std::string word;
    for (size_t i = word_start; i < word_end; ++i) {
        word += static_cast<char>(tolower(static_cast<unsigned char>(text[i])));
    }

    if (word.empty()) return false;

    // Single letter abbreviations: "A.", "B.", etc.
    if (word.length() == 1 && isalpha(static_cast<unsigned char>(word[0]))) {
        return true;
    }

    // Common abbreviations (without the trailing dot)
    static const char* abbreviations[] = {
        // Titles
        "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "rev", "hon",
        // Addresses
        "st", "ave", "blvd", "rd", "ln", "ct",
        // Latin / academic
        "vs", "etc", "approx", "dept", "est",
        // Companies / organizations
        "inc", "ltd", "corp", "co",
        // Common multi-dot abbreviations (matched without dots)
        "eg", "ie", "al",  // e.g., i.e., et al.
        // Time
        "am", "pm",
        // Measurements
        "oz", "lb", "ft", "sq",
        nullptr
    };

    for (int i = 0; abbreviations[i] != nullptr; ++i) {
        if (word == abbreviations[i]) {
            return true;
        }
    }

    // Multi-dot abbreviations: "e.g", "i.e", "u.s", "a.m", "p.m"
    // Check if the word contains dots (like "e.g" or "u.s")
    std::string word_with_dot;
    for (size_t i = word_start; i <= dot_pos && i < text.size(); ++i) {
        word_with_dot += static_cast<char>(tolower(static_cast<unsigned char>(text[i])));
    }

    static const char* dotted_abbreviations[] = {
        "e.g.", "i.e.", "u.s.", "a.m.", "p.m.", "no.",
        nullptr
    };

    for (int i = 0; dotted_abbreviations[i] != nullptr; ++i) {
        if (word_with_dot == dotted_abbreviations[i]) {
            return true;
        }
    }

    return false;
}

// Helper: trim a string of leading/trailing whitespace
static std::string trim_string(const std::string& s) {
    size_t start = s.find_first_not_of(" \t\n\r");
    size_t end = s.find_last_not_of(" \t\n\r");
    if (start == std::string::npos || end == std::string::npos) return "";
    return s.substr(start, end - start + 1);
}

// Split text into sentences for streaming TTS
static std::vector<std::string> split_into_sentences(const std::string& text) {
    std::vector<std::string> sentences;
    std::string current;

    for (size_t i = 0; i < text.length(); ++i) {
        char c = text[i];
        current += c;

        // Check for sentence boundaries: . ! ? followed by space, newline, or end
        if ((c == '.' || c == '!' || c == '?') &&
            (i + 1 >= text.length() || text[i + 1] == ' ' || text[i + 1] == '\n')) {

            // For periods, check if this is an abbreviation (not a sentence end)
            if (c == '.' && is_abbreviation(text, i)) {
                continue;  // Not a sentence boundary, keep accumulating
            }

            std::string trimmed = trim_string(current);
            if (!trimmed.empty()) {
                sentences.push_back(trimmed);
            }
            current.clear();

            // Skip the space after punctuation
            if (i + 1 < text.length() && text[i + 1] == ' ') {
                ++i;
            }
        }
    }

    // Don't forget any remaining text
    std::string trimmed = trim_string(current);
    if (!trimmed.empty()) {
        sentences.push_back(trimmed);
    }

    return sentences;
}

bool VoicePipeline::speak_text(const std::string& text) {
    if (!initialized_ || !impl_->voice_agent) {
        return false;
    }

    // Sanitize text: remove special characters, emojis, markdown that shouldn't be spoken
    std::string sanitized_text = sanitize_text_for_tts(text);

    if (sanitized_text.empty()) {
        std::cout << "[TTS] Skipping empty text after sanitization\n";
        return true;  // Not an error, just nothing to say
    }

    state_ = PipelineState::SPEAKING;

    // Split into sentences for streaming playback
    std::vector<std::string> sentences = split_into_sentences(sanitized_text);

    if (sentences.empty()) {
        sentences.push_back(sanitized_text);  // Fallback: treat whole text as one sentence
    }

    std::cout << "[TTS] Streaming " << sentences.size() << " sentence(s)\n";

    int tts_sample_rate = 22050;  // Piper Lessac's 22050Hz
    bool any_success = false;

    for (size_t i = 0; i < sentences.size(); ++i) {
        const std::string& sentence = sentences[i];

        if (sentence.empty()) {
            continue;
        }

        std::cout << "[TTS] [" << (i + 1) << "/" << sentences.size() << "] \""
                  << sentence.substr(0, 60) << (sentence.length() > 60 ? "..." : "") << "\"\n";

        // Synthesize this sentence
        void* audio_data = nullptr;
        size_t audio_size = 0;

        rac_result_t result = rac_voice_agent_synthesize_speech(
            impl_->voice_agent,
            sentence.c_str(),
            &audio_data,
            &audio_size
        );

        if (result != RAC_SUCCESS || !audio_data || audio_size == 0) {
            std::cerr << "[TTS] Failed to synthesize sentence " << (i + 1) << "\n";
            continue;
        }

        // Play this sentence immediately (don't wait for others)
        // Synchronous speak_text has no cancellation, so pass a dummy flag
        if (config_.on_audio_output) {
            static std::atomic<bool> no_cancel{false};
            config_.on_audio_output(
                static_cast<const int16_t*>(audio_data),
                audio_size / sizeof(int16_t),
                tts_sample_rate,
                no_cancel
            );
        }

        free(audio_data);
        any_success = true;
    }

    if (!any_success) {
        if (config_.on_error) {
            config_.on_error("TTS synthesis failed for all sentences");
        }
        state_ = impl_->wakeword_enabled ? PipelineState::WAITING_FOR_WAKE_WORD : PipelineState::LISTENING;
        return false;
    }

    // Add cooldown before re-enabling listening to prevent echo feedback
    // (speaker audio being picked up by microphone)
    std::this_thread::sleep_for(std::chrono::milliseconds(TTS_COOLDOWN_MS));

    state_ = impl_->wakeword_enabled ? PipelineState::WAITING_FOR_WAKE_WORD : PipelineState::LISTENING;

    return true;
}

// =============================================================================
// Async TTS - Non-blocking, pre-synthesizes ahead of playback
// =============================================================================
// Synthesize sentence 1 → push to queue → consumer starts playing immediately
// While sentence 1 plays, synthesize sentence 2 → push → plays right after
// No gap between sentences.

void VoicePipeline::speak_text_async(const std::string& text) {
    if (!initialized_ || !impl_->voice_agent) {
        return;
    }

    // Full cleanup: cancel + join old producer thread before starting a new one.
    // If barge-in happened, cancel_fast() was called seconds ago (during ASR +
    // OpenClaw processing), so the old producer has had time to finish its current
    // synthesis call. The join here should be instant or very fast.
    async_tts_->cleanup();

    // Sanitize and split
    std::string sanitized = sanitize_text_for_tts(text);
    if (sanitized.empty()) {
        std::cout << "[TTS] Skipping empty text after sanitization\n";
        return;
    }

    std::vector<std::string> sentences = split_into_sentences(sanitized);
    if (sentences.empty()) {
        sentences.push_back(sanitized);
    }

    std::cout << "[TTS-Async] Streaming " << sentences.size() << " sentence(s)\n";
    state_ = PipelineState::SPEAKING;

    // Create queue - consumer thread starts immediately, waits for first chunk
    async_tts_->queue = std::make_shared<TTSQueue>(config_.on_audio_output);
    async_tts_->cancelled.store(false);

    // Capture references for the producer thread.
    // The producer accesses async_tts_->cancelled and async_tts_->queue via these refs.
    // This is safe because the producer is always joined before async_tts_ or the
    // pipeline is destroyed (cleanup() or ~AsyncTTSState both join).
    auto queue_ref = async_tts_->queue;
    auto& cancelled_ref = async_tts_->cancelled;
    auto voice_agent = impl_->voice_agent;
    bool wakeword_enabled = impl_->wakeword_enabled;

    async_tts_->producer_thread = std::thread([this, voice_agent, sentences, wakeword_enabled,
                                                queue_ref, &cancelled_ref]() {
        int tts_sample_rate = 22050;  // Piper Lessac

        for (size_t i = 0; i < sentences.size(); ++i) {
            if (cancelled_ref.load()) break;

            const auto& sentence = sentences[i];
            if (sentence.empty()) continue;

            std::cout << "[TTS-Async] [" << (i + 1) << "/" << sentences.size() << "] \""
                      << sentence.substr(0, 60) << (sentence.length() > 60 ? "..." : "") << "\"\n";

            void* audio_data = nullptr;
            size_t audio_size = 0;

            rac_result_t result = rac_voice_agent_synthesize_speech(
                voice_agent, sentence.c_str(), &audio_data, &audio_size);

            if (result != RAC_SUCCESS || !audio_data || audio_size == 0) {
                std::cerr << "[TTS-Async] Failed to synthesize sentence " << (i + 1) << "\n";
                if (audio_data) free(audio_data);
                continue;
            }

            // Push audio into the playback queue
            size_t num_samples = audio_size / sizeof(int16_t);
            AudioChunk chunk;
            chunk.samples.assign(
                static_cast<const int16_t*>(audio_data),
                static_cast<const int16_t*>(audio_data) + num_samples);
            chunk.sample_rate = tts_sample_rate;
            free(audio_data);

            if (!cancelled_ref.load()) {
                queue_ref->push(std::move(chunk));
            }
        }

        // Tell consumer there's nothing more coming
        queue_ref->finish();

        // Wait for consumer to finish playing, then cooldown + state transition
        // (This runs on the producer thread so it doesn't block main)
        if (!cancelled_ref.load()) {
            while (queue_ref->is_active() && !cancelled_ref.load()) {
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
            }
        }

        if (!cancelled_ref.load()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(TTS_COOLDOWN_MS));

            // Lock mutex to ensure state_ write is visible on ARM (Raspberry Pi).
            // Without this, the capture thread may never see the transition from
            // SPEAKING back to WAITING_FOR_WAKE_WORD due to weak memory ordering.
            {
                std::lock_guard<std::mutex> lock(impl_->mutex);
                state_ = wakeword_enabled ? PipelineState::WAITING_FOR_WAKE_WORD : PipelineState::LISTENING;

                // Reset wake word model after TTS. During SPEAKING state, the model
                // processed 20+ seconds of speaker audio for barge-in detection.
                // Its streaming buffers are now polluted with TTS output, making the
                // next "Hey Jarvis" detection unreliable. Reset to a clean state.
                if (impl_->wakeword_handle) {
                    rac_wakeword_onnx_reset(impl_->wakeword_handle);
                }
            }
            std::cout << "[TTS-Async] Playback complete\n";
        }
    });
}

void VoicePipeline::cancel_speech() {
    if (!async_tts_) return;

    // Force-stop ALSA immediately (snd_pcm_drop) for instant silence
    if (config_.on_audio_stop) {
        config_.on_audio_stop();
    }

    // Non-blocking cancel: set cancelled flag + cancel queue for instant silence.
    // The producer thread continues running (finishes current synthesis call) but
    // won't push any more audio. The thread stays joinable — it will be joined by
    // the next speak_text_async() call or the destructor.
    async_tts_->cancel_fast();

    // Clear stale speak messages that may still be in the queue
    if (config_.on_cancel_pending_responses) {
        config_.on_cancel_pending_responses();
    }

    if (initialized_ && state_ == PipelineState::SPEAKING) {
        state_ = impl_->wakeword_enabled ? PipelineState::WAITING_FOR_WAKE_WORD : PipelineState::LISTENING;
    }
}

bool VoicePipeline::is_speaking() const {
    if (!async_tts_ || !async_tts_->queue) {
        return state_ == PipelineState::SPEAKING;
    }
    // If cancelled, we're no longer "speaking" even if the consumer thread
    // hasn't fully exited yet (cancel_fast sets cancelled without joining).
    if (async_tts_->cancelled.load()) {
        return false;
    }
    return async_tts_->queue->is_active();
}

std::string VoicePipeline::state_string() const {
    switch (state_) {
        case PipelineState::NOT_INITIALIZED: return "NOT_INITIALIZED";
        case PipelineState::WAITING_FOR_WAKE_WORD: return "WAITING_FOR_WAKE_WORD";
        case PipelineState::LISTENING: return "LISTENING";
        case PipelineState::PROCESSING_STT: return "PROCESSING_STT";
        case PipelineState::SPEAKING: return "SPEAKING";
        case PipelineState::ERROR: return "ERROR";
        default: return "UNKNOWN";
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

std::string VoicePipeline::get_tts_model_id() const {
    if (impl_->voice_agent) {
        const char* id = rac_voice_agent_get_tts_voice_id(impl_->voice_agent);
        return id ? id : "";
    }
    return "";
}

// =============================================================================
// Component Testers
// =============================================================================

bool test_wakeword(const std::string& wav_path, float threshold) {
    std::cout << "[Test] Wake word test not yet implemented\n";
    return false;
}

bool test_vad(const std::string& wav_path) {
    std::cout << "[Test] VAD test not yet implemented\n";
    return false;
}

std::string test_stt(const std::string& wav_path) {
    std::cout << "[Test] STT test not yet implemented\n";
    return "";
}

bool test_tts(const std::string& text, const std::string& output_path) {
    std::cout << "[Test] TTS test not yet implemented\n";
    return false;
}

} // namespace openclaw
