// =============================================================================
// Waiting Chime - Implementation
// =============================================================================
// Loads a WAV earcon file and plays it once immediately, then every 5 seconds.
// Simple WAV parser handles standard 16-bit PCM files.
// =============================================================================

#include "waiting_chime.h"

#include <algorithm>
#include <cstring>
#include <fstream>
#include <iostream>

namespace openclaw {

// =============================================================================
// Constructor / Destructor
// =============================================================================

WaitingChime::WaitingChime(const std::string& wav_path, AudioOutputCallback play_audio)
    : play_audio_(std::move(play_audio)) {
    loaded_ = load_wav(wav_path);
    if (loaded_) {
        std::cout << "[WaitingChime] Loaded earcon: " << earcon_buffer_.size()
                  << " samples @ " << sample_rate_ << " Hz\n";
    } else {
        std::cout << "[WaitingChime] No earcon loaded (waiting feedback will be silent)\n";
    }
}

WaitingChime::~WaitingChime() {
    stop();
}

// =============================================================================
// WAV Loader (16-bit PCM)
// =============================================================================

bool WaitingChime::load_wav(const std::string& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open()) {
        return false;
    }

    // Read RIFF header
    char riff[4];
    file.read(riff, 4);
    if (strncmp(riff, "RIFF", 4) != 0) return false;

    uint32_t file_size;
    file.read(reinterpret_cast<char*>(&file_size), 4);

    char wave[4];
    file.read(wave, 4);
    if (strncmp(wave, "WAVE", 4) != 0) return false;

    // Find fmt and data chunks
    uint16_t channels = 0;
    uint16_t bits_per_sample = 0;

    while (file.good()) {
        char chunk_id[4];
        file.read(chunk_id, 4);
        uint32_t chunk_size;
        file.read(reinterpret_cast<char*>(&chunk_size), 4);

        if (!file.good()) break;

        if (strncmp(chunk_id, "fmt ", 4) == 0) {
            uint16_t audio_format;
            file.read(reinterpret_cast<char*>(&audio_format), 2);
            file.read(reinterpret_cast<char*>(&channels), 2);
            uint32_t sr;
            file.read(reinterpret_cast<char*>(&sr), 4);
            sample_rate_ = static_cast<int>(sr);
            uint32_t byte_rate;
            file.read(reinterpret_cast<char*>(&byte_rate), 4);
            uint16_t block_align;
            file.read(reinterpret_cast<char*>(&block_align), 2);
            file.read(reinterpret_cast<char*>(&bits_per_sample), 2);
            // Skip extra fmt bytes
            if (chunk_size > 16) {
                file.seekg(chunk_size - 16, std::ios::cur);
            }
        } else if (strncmp(chunk_id, "data", 4) == 0) {
            if (bits_per_sample == 0 || channels == 0) {
                return false;  // fmt chunk not yet parsed
            }
            size_t num_samples = chunk_size / (bits_per_sample / 8) / channels;
            earcon_buffer_.resize(num_samples);
            if (channels == 1 && bits_per_sample == 16) {
                // Direct read for mono 16-bit
                file.read(reinterpret_cast<char*>(earcon_buffer_.data()), chunk_size);
            } else if (channels == 2 && bits_per_sample == 16) {
                // Downmix stereo to mono
                std::vector<int16_t> stereo(num_samples * 2);
                file.read(reinterpret_cast<char*>(stereo.data()), chunk_size);
                for (size_t i = 0; i < num_samples; ++i) {
                    earcon_buffer_[i] = static_cast<int16_t>(
                        (static_cast<int32_t>(stereo[i * 2]) + stereo[i * 2 + 1]) / 2);
                }
            } else {
                // Unsupported format
                earcon_buffer_.clear();
                return false;
            }
            break;
        } else {
            file.seekg(chunk_size, std::ios::cur);
        }
    }

    return !earcon_buffer_.empty() && sample_rate_ > 0;
}

// =============================================================================
// Start / Stop
// =============================================================================

void WaitingChime::start() {
    if (playing_.load() || !loaded_) return;

    if (repeat_thread_.joinable()) {
        repeat_thread_.join();
    }

    playing_.store(true);
    repeat_thread_ = std::thread(&WaitingChime::repeat_loop, this);
}

void WaitingChime::stop() {
    if (!playing_.load()) return;

    playing_.store(false);

    if (repeat_thread_.joinable()) {
        repeat_thread_.join();
    }
}

bool WaitingChime::is_playing() const {
    return playing_.load();
}

// =============================================================================
// Playback
// =============================================================================

void WaitingChime::play_earcon() {
    if (!play_audio_ || earcon_buffer_.empty()) return;

    // Play in small chunks so we can check the stop flag between chunks
    size_t offset = 0;
    while (offset < earcon_buffer_.size() && playing_.load()) {
        size_t remaining = earcon_buffer_.size() - offset;
        size_t chunk = std::min(remaining, PLAYBACK_CHUNK_SAMPLES);
        play_audio_(earcon_buffer_.data() + offset, chunk, sample_rate_);
        offset += chunk;
    }
}

void WaitingChime::repeat_loop() {
    // Play once immediately
    play_earcon();

    // Then repeat every REPEAT_INTERVAL_MS
    while (playing_.load()) {
        // Wait in small increments so stop() is responsive
        auto wait_start = std::chrono::steady_clock::now();
        while (playing_.load()) {
            auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now() - wait_start
            ).count();
            if (elapsed >= REPEAT_INTERVAL_MS) break;
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }

        if (!playing_.load()) break;

        play_earcon();
    }
}

} // namespace openclaw
