// =============================================================================
// Voice Pipeline - Implementation
// =============================================================================
// Simplified pipeline for OpenClaw: VAD → STT → (send to OpenClaw)
// TTS is called separately when speak commands arrive.
// Uses the public STT, TTS, and VAD component APIs - NO LLM loaded.
// =============================================================================

#include "voice_pipeline.h"
#include "tts_queue.h"
#include "config/model_config.h"

#include <rac/features/stt/rac_stt_component.h>
#include <rac/features/tts/rac_tts_component.h>
#include <rac/features/vad/rac_vad_component.h>
#include <rac/core/rac_error.h>

#include <vector>
#include <mutex>
#include <iostream>
#include <chrono>
#include <thread>
#include <cstring>
#include <cmath>
#include <algorithm>

namespace openclaw {

// =============================================================================
// Constants
// =============================================================================

// Silence duration before treating speech as ended
static constexpr double DEFAULT_SILENCE_DURATION_SEC = 1.5;

// Delay after TTS finishes before re-enabling listening (prevents echo feedback).
// 200ms is enough for the last TTS samples to clear the ALSA buffer and mic echo,
// while minimizing the perceived delay before microphone processing resumes.
static constexpr int TTS_COOLDOWN_MS = 200;

// Minimum speech samples before processing (avoid false triggers)
static constexpr size_t DEFAULT_MIN_SPEECH_SAMPLES = 16000;  // 1 second at 16kHz

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

static std::vector<int16_t> float_pcm_to_int16(const void* audio_data, size_t audio_size) {
    if (!audio_data || audio_size == 0 || audio_size % sizeof(float) != 0) {
        return {};
    }

    const auto* samples = static_cast<const float*>(audio_data);
    const size_t count = audio_size / sizeof(float);
    std::vector<int16_t> converted(count);
    for (size_t i = 0; i < count; ++i) {
        const float clamped = std::clamp(samples[i], -1.0f, 1.0f);
        converted[i] = static_cast<int16_t>(std::lround(clamped * 32767.0f));
    }
    return converted;
}

// =============================================================================
// Implementation
// =============================================================================

struct VoicePipeline::Impl {
    rac_handle_t stt_component = nullptr;
    rac_handle_t tts_component = nullptr;

    // Silero VAD (ONNX-based, much more accurate than energy VAD)
    rac_handle_t silero_vad = nullptr;

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

    // Deferred callbacks — collected under the lock, fired after unlock.
    // This prevents deadlocks when callbacks re-enter the pipeline.
    struct PendingCallbacks {
        bool voice_activity_started = false;
        bool voice_activity_ended = false;
        std::vector<int16_t> stt_buffer;  // Non-empty if STT should be processed

        void clear() {
            voice_activity_started = false;
            voice_activity_ended = false;
            stt_buffer.clear();
        }
        bool has_any() const {
            return voice_activity_started || voice_activity_ended || !stt_buffer.empty();
        }
    } pending_callbacks;
};

// =============================================================================
// Async TTS State - Manages producer thread + TTSQueue
// =============================================================================

struct VoicePipeline::AsyncTTSState {
    std::shared_ptr<TTSQueue> queue;
    std::atomic<bool> cancelled{false};
    std::thread producer_thread;

    // Non-blocking cancellation signals the producer to stop and silences audio.
    // Does NOT join the producer — the thread finishes on its own after the current
    // rac_tts_component_synthesize call returns. This avoids blocking the
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
    , config_(config)
    , async_tts_(std::make_unique<AsyncTTSState>()) {
}

VoicePipeline::~VoicePipeline() {
    // Ensure the producer thread exits before we destroy the TTS component.
    if (async_tts_) {
        async_tts_->cleanup();
    }
    stop();

    if (impl_->silero_vad) {
        rac_vad_component_stop(impl_->silero_vad);
        rac_vad_component_destroy(impl_->silero_vad);
        impl_->silero_vad = nullptr;
    }
    if (impl_->stt_component) {
        rac_stt_component_destroy(impl_->stt_component);
        impl_->stt_component = nullptr;
    }
    if (impl_->tts_component) {
        rac_tts_component_destroy(impl_->tts_component);
        impl_->tts_component = nullptr;
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
        print_model_status();
        state_ = PipelineState::ERROR;
        return false;
    }

    std::cout << "[Pipeline] Initializing components (NO LLM)...\n";

    rac_result_t result = rac_stt_component_create(&impl_->stt_component);
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to create STT component";
        state_ = PipelineState::ERROR;
        return false;
    }

    result = rac_tts_component_create(&impl_->tts_component);
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to create TTS component";
        state_ = PipelineState::ERROR;
        return false;
    }

    // Get model paths
    std::string stt_path = get_stt_model_path();
    std::string tts_path = get_tts_model_path();

    // Load STT model (Parakeet TDT-CTC 110M - NeMo CTC, int8 quantized)
    std::cout << "  Loading STT: " << STT_MODEL_ID << "\n";
    result = rac_stt_component_load_model(
        impl_->stt_component,
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
    result = rac_tts_component_load_voice(
        impl_->tts_component,
        tts_path.c_str(),
        TTS_MODEL_ID,
        "Piper Lessac Medium TTS"
    );
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to load TTS voice: " + tts_path;
        state_ = PipelineState::ERROR;
        return false;
    }

    // Initialize Silero VAD (ONNX neural network - much more accurate than energy VAD)
    std::string vad_path = get_vad_model_path();
    std::cout << "  Loading VAD: Silero (ONNX)\n";

    rac_vad_config_t vad_config = RAC_VAD_CONFIG_DEFAULT;
    vad_config.sample_rate = 16000;

    result = rac_vad_component_create(&impl_->silero_vad);
    if (result == RAC_SUCCESS) {
        result = rac_vad_component_configure(impl_->silero_vad, &vad_config);
    }
    if (result == RAC_SUCCESS) {
        result = rac_vad_component_initialize(impl_->silero_vad);
    }
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to initialize VAD component";
        state_ = PipelineState::ERROR;
        return false;
    }

    result = rac_vad_component_load_model(
        impl_->silero_vad, vad_path.c_str(), VAD_MODEL_ID, "Silero VAD");
    if (result != RAC_SUCCESS) {
        std::cerr << "[Pipeline] WARNING: Failed to load Silero VAD, using energy VAD\n";
    } else {
        result = rac_vad_component_set_energy_threshold(impl_->silero_vad, config_.vad_threshold);
        if (result != RAC_SUCCESS) {
            std::cerr << "[Pipeline] WARNING: Failed to configure Silero VAD, using energy VAD\n";
            (void)rac_vad_component_unload(impl_->silero_vad);
        }
    }

    result = rac_vad_component_start(impl_->silero_vad);
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to start VAD component";
        state_ = PipelineState::ERROR;
        return false;
    }
    if (rac_vad_component_is_loaded(impl_->silero_vad) == RAC_TRUE) {
        std::cout << "  Silero VAD loaded (threshold: " << config_.vad_threshold << ")\n";
    }

    std::cout << "[Pipeline] All components loaded successfully!\n";
    initialized_ = true;
    state_ = PipelineState::LISTENING;

    return true;
}

void VoicePipeline::start() {
    running_ = true;
    impl_->speech_active = false;
    impl_->speech_buffer.clear();
    impl_->speech_callback_fired = false;
    impl_->consecutive_speech_frames = 0;
    impl_->consecutive_silent_frames = 0;
    impl_->current_burst_frames = 0;
    state_ = PipelineState::LISTENING;
    std::cout << "[Pipeline] Started: LISTENING\n";
}

void VoicePipeline::stop() {
    running_ = false;
    impl_->speech_active = false;
    impl_->speech_buffer.clear();
    impl_->speech_callback_fired = false;
    impl_->consecutive_speech_frames = 0;
    impl_->consecutive_silent_frames = 0;
    impl_->current_burst_frames = 0;
}

bool VoicePipeline::is_running() const {
    return running_;
}

bool VoicePipeline::is_ready() const {
    if (!initialized_ || !impl_->stt_component || !impl_->tts_component || !impl_->silero_vad) {
        return false;
    }
    return rac_stt_component_is_loaded(impl_->stt_component) == RAC_TRUE &&
           rac_tts_component_is_loaded(impl_->tts_component) == RAC_TRUE;
}

void VoicePipeline::process_audio(const int16_t* samples, size_t num_samples) {
    // Audio level diagnostics: compute RMS and peak of raw int16 audio
    // Log every ~1s (62 frames @ 256 samples/frame @ 16kHz)
    {
        static int diag_frame = 0;
        ++diag_frame;

        if (config_.debug_audio && diag_frame % 62 == 0) {
            // Compute RMS and peak of this chunk
            double sum_sq = 0.0;
            int peak = 0;
            int16_t min_val = 0;
            int16_t max_val = 0;
            for (size_t i = 0; i < num_samples; ++i) {
                sum_sq += static_cast<double>(samples[i]) * samples[i];
                int abs_val = std::abs(static_cast<int>(samples[i]));
                if (abs_val > peak) peak = abs_val;
                if (samples[i] < min_val) min_val = samples[i];
                if (samples[i] > max_val) max_val = samples[i];
            }
            double rms = std::sqrt(sum_sq / num_samples);
            // dBFS relative to int16 max (32768)
            double db = (rms > 0) ? 20.0 * std::log10(rms / 32768.0) : -96.0;

            std::cout << "[AUDIO] RMS=" << static_cast<int>(rms)
                      << " (" << std::fixed;
            std::cout.precision(1);
            std::cout << db << "dB)"
                      << " peak=" << peak
                      << " range=[" << min_val << "," << max_val << "]"
                      << " state=" << static_cast<int>(state_.load())
                      << "\n" << std::flush;
        }

        // Keep the original low-frequency DIAG log (every ~8s)
        if (diag_frame % 500 == 0) {
            std::cout << "[DIAG] process_audio frame=" << diag_frame
                      << " init=" << initialized_
                      << " running=" << running_
                      << " state=" << static_cast<int>(state_.load())
                      << " samples=" << num_samples << "\n" << std::flush;
        }
    }

    if (!initialized_ || !running_) {
        return;
    }

    std::unique_lock<std::mutex> lock(impl_->mutex);

    // Skip VAD/STT during playback to prevent speaker echo from being
    // transcribed as microphone input.
    if (state_ == PipelineState::SPEAKING) {
        return;
    }

    // VAD consumes normalized float PCM; STT retains the original int16 PCM.
    std::vector<float> float_samples(num_samples);
    for (size_t i = 0; i < num_samples; ++i) {
        float_samples[i] = samples[i] / 32768.0f;
    }

    process_vad(float_samples.data(), num_samples, samples);

    // Dispatch deferred callbacks outside the lock to prevent deadlocks
    // when callbacks re-enter the pipeline (e.g., speak_text_async, cancel_speech)
    if (impl_->pending_callbacks.has_any()) {
        auto pending = std::move(impl_->pending_callbacks);
        impl_->pending_callbacks.clear();
        lock.unlock();

        if (pending.voice_activity_started && config_.on_voice_activity) {
            config_.on_voice_activity(true);
        }
        if (pending.voice_activity_ended && config_.on_voice_activity) {
            config_.on_voice_activity(false);
        }
        if (!pending.stt_buffer.empty()) {
            process_stt(pending.stt_buffer.data(), pending.stt_buffer.size());
        }
    }
}

void VoicePipeline::process_vad(const float* samples, size_t num_samples, const int16_t* raw_samples) {
    if (!impl_->stt_component || !impl_->silero_vad) {
        return;
    }

    auto now = std::chrono::steady_clock::now();

    // The VAD component uses Silero when loaded and its energy backend otherwise.
    rac_bool_t is_speech = RAC_FALSE;
    if (impl_->silero_vad) {
        rac_vad_component_process(impl_->silero_vad, samples, num_samples, &is_speech);
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

        // Defer "listening" callback once we have enough samples (fired after unlock)
        size_t min_samples = config_.min_speech_samples > 0 ? config_.min_speech_samples : DEFAULT_MIN_SPEECH_SAMPLES;
        if (!impl_->speech_callback_fired && impl_->speech_buffer.size() + num_samples >= min_samples / 2) {
            impl_->speech_callback_fired = true;
            impl_->pending_callbacks.voice_activity_started = true;
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

        // Defer callbacks (fired after unlock to prevent deadlock)
        impl_->pending_callbacks.voice_activity_ended = true;

        // Copy speech buffer for deferred STT processing (before clearing)
        size_t min_samples = config_.min_speech_samples > 0 ? config_.min_speech_samples : DEFAULT_MIN_SPEECH_SAMPLES;
        if (impl_->speech_buffer.size() >= min_samples) {
            impl_->pending_callbacks.stt_buffer = impl_->speech_buffer;
        } else if (config_.debug_stt) {
            std::cout << "[STT] Not enough speech (" << impl_->speech_buffer.size()
                      << " < " << min_samples << ")\n";
        }

        // Reset state
        impl_->speech_buffer.clear();
        impl_->speech_callback_fired = false;

        state_ = PipelineState::LISTENING;
    }
}

bool VoicePipeline::process_stt(const int16_t* samples, size_t num_samples) {
    if (!impl_->stt_component) {
        return false;
    }

    if (config_.debug_stt) {
        std::cout << "[STT] Processing " << num_samples << " samples ("
                  << (float)num_samples / 16000.0f << "s)\n";
    }

    rac_stt_result_t transcription_result{};
    rac_result_t result = rac_stt_component_transcribe(
        impl_->stt_component,
        samples,
        num_samples * sizeof(int16_t),
        nullptr,
        &transcription_result
    );

    if (result != RAC_SUCCESS || !transcription_result.text ||
        transcription_result.text[0] == '\0') {
        if (config_.on_error) {
            config_.on_error("STT transcription failed");
        }
        rac_stt_result_free(&transcription_result);
        return false;
    }

    std::string transcription = transcription_result.text;
    rac_stt_result_free(&transcription_result);

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
    if (!initialized_ || !impl_->tts_component) {
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

    bool any_success = false;

    for (size_t i = 0; i < sentences.size(); ++i) {
        const std::string& sentence = sentences[i];

        if (sentence.empty()) {
            continue;
        }

        std::cout << "[TTS] [" << (i + 1) << "/" << sentences.size() << "] \""
                  << sentence.substr(0, 60) << (sentence.length() > 60 ? "..." : "") << "\"\n";

        rac_tts_result_t tts_result{};
        rac_result_t result = rac_tts_component_synthesize(
            impl_->tts_component,
            sentence.c_str(),
            nullptr,
            &tts_result
        );

        if (result != RAC_SUCCESS || !tts_result.audio_data || tts_result.audio_size == 0) {
            std::cerr << "[TTS] Failed to synthesize sentence " << (i + 1) << "\n";
            rac_tts_result_free(&tts_result);
            continue;
        }

        auto pcm = float_pcm_to_int16(tts_result.audio_data, tts_result.audio_size);
        const int sample_rate = tts_result.sample_rate > 0 ? tts_result.sample_rate : 22050;
        rac_tts_result_free(&tts_result);
        if (pcm.empty()) {
            std::cerr << "[TTS] Backend returned invalid float PCM for sentence " << (i + 1) << "\n";
            continue;
        }

        // Play this sentence immediately (don't wait for others)
        // Synchronous speak_text has no cancellation, so pass a dummy flag
        if (config_.on_audio_output) {
            std::atomic<bool> cancel_flag{false};
            config_.on_audio_output(pcm.data(), pcm.size(), sample_rate, cancel_flag);
        }

        any_success = true;
    }

    if (!any_success) {
        if (config_.on_error) {
            config_.on_error("TTS synthesis failed for all sentences");
        }
        state_ = PipelineState::LISTENING;
        return false;
    }

    // Add cooldown before re-enabling listening to prevent echo feedback
    // (speaker audio being picked up by microphone)
    std::this_thread::sleep_for(std::chrono::milliseconds(TTS_COOLDOWN_MS));

    state_ = PipelineState::LISTENING;

    return true;
}

// =============================================================================
// Async TTS - Non-blocking, pre-synthesizes ahead of playback
// =============================================================================
// Synthesize sentence 1 → push to queue → consumer starts playing immediately
// While sentence 1 plays, synthesize sentence 2 → push → plays right after
// No gap between sentences.

void VoicePipeline::speak_text_async(const std::string& text) {
    if (!initialized_ || !impl_->tts_component) {
        return;
    }

    // Full cleanup: cancel + join old producer thread before starting a new one.
    // If cancellation already happened, cancel_fast() was called earlier (during ASR +
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
    std::cout << "[Pipeline] State: -> SPEAKING (TTS started)\n";

    // Create queue - consumer thread starts immediately, waits for first chunk
    async_tts_->queue = std::make_shared<TTSQueue>(config_.on_audio_output);
    async_tts_->cancelled.store(false);

    // Capture references for the producer thread.
    // The producer accesses async_tts_->cancelled and async_tts_->queue via these refs.
    // This is safe because the producer is always joined before async_tts_ or the
    // pipeline is destroyed (cleanup() or ~AsyncTTSState both join).
    auto queue_ref = async_tts_->queue;
    auto& cancelled_ref = async_tts_->cancelled;
    auto tts_component = impl_->tts_component;

    async_tts_->producer_thread = std::thread([this, tts_component, sentences,
                                                queue_ref, &cancelled_ref]() {
        for (size_t i = 0; i < sentences.size(); ++i) {
            if (cancelled_ref.load()) break;

            const auto& sentence = sentences[i];
            if (sentence.empty()) continue;

            std::cout << "[TTS-Async] [" << (i + 1) << "/" << sentences.size() << "] \""
                      << sentence.substr(0, 60) << (sentence.length() > 60 ? "..." : "") << "\"\n";

            rac_tts_result_t tts_result{};
            rac_result_t result = rac_tts_component_synthesize(
                tts_component, sentence.c_str(), nullptr, &tts_result);

            if (result != RAC_SUCCESS || !tts_result.audio_data || tts_result.audio_size == 0) {
                std::cerr << "[TTS-Async] Failed to synthesize sentence " << (i + 1) << "\n";
                rac_tts_result_free(&tts_result);
                continue;
            }

            auto pcm = float_pcm_to_int16(tts_result.audio_data, tts_result.audio_size);
            const int sample_rate = tts_result.sample_rate > 0 ? tts_result.sample_rate : 22050;
            rac_tts_result_free(&tts_result);
            if (pcm.empty()) {
                std::cerr << "[TTS-Async] Backend returned invalid float PCM for sentence "
                          << (i + 1) << "\n";
                continue;
            }

            AudioChunk chunk;
            chunk.samples = std::move(pcm);
            chunk.sample_rate = sample_rate;

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

            // state_ is std::atomic so the write is inherently visible across threads
            // (including ARM weak memory ordering on Raspberry Pi).
            {
                state_ = PipelineState::LISTENING;
            }
            std::cout << "[Pipeline] State: SPEAKING -> LISTENING (TTS playback complete)\n";
        }
    });
}

void VoicePipeline::cancel_speech() {
    if (!async_tts_) return;

    std::cout << "[Pipeline] cancel_speech() called (state=" << state_string() << ")\n";

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
        state_ = PipelineState::LISTENING;
        std::cout << "[Pipeline] State: SPEAKING -> LISTENING (cancel_speech)\n";
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
    if (impl_->stt_component) {
        const char* id = rac_stt_component_get_model_id(impl_->stt_component);
        return id ? id : "";
    }
    return "";
}

std::string VoicePipeline::get_tts_model_id() const {
    if (impl_->tts_component) {
        const char* id = rac_tts_component_get_voice_id(impl_->tts_component);
        return id ? id : "";
    }
    return "";
}

} // namespace openclaw
