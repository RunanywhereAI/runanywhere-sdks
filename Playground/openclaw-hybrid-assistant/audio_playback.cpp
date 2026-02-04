// =============================================================================
// Audio Playback - ALSA implementation
// =============================================================================

#include "audio_playback.h"

#include <alsa/asoundlib.h>
#include <atomic>
#include <cstring>

namespace openclaw {

// =============================================================================
// Implementation
// =============================================================================

struct AudioPlayback::Impl {
    snd_pcm_t* pcm_handle = nullptr;
    std::atomic<bool> playing{false};
};

AudioPlayback::AudioPlayback()
    : AudioPlayback(AudioPlaybackConfig::defaults()) {
}

AudioPlayback::AudioPlayback(const AudioPlaybackConfig& config)
    : impl_(std::make_unique<Impl>())
    , config_(config) {
}

AudioPlayback::~AudioPlayback() {
    stop();
    if (impl_->pcm_handle) {
        snd_pcm_close(impl_->pcm_handle);
        impl_->pcm_handle = nullptr;
    }
}

bool AudioPlayback::initialize() {
    if (initialized_) {
        return true;
    }

    int err;

    // Open PCM device for playback
    err = snd_pcm_open(&impl_->pcm_handle, config_.device.c_str(),
                       SND_PCM_STREAM_PLAYBACK, 0);
    if (err < 0) {
        last_error_ = std::string("Cannot open audio device: ") + snd_strerror(err);
        return false;
    }

    // Set hardware parameters
    snd_pcm_hw_params_t* hw_params;
    snd_pcm_hw_params_alloca(&hw_params);
    snd_pcm_hw_params_any(impl_->pcm_handle, hw_params);

    // Set access type - interleaved
    err = snd_pcm_hw_params_set_access(impl_->pcm_handle, hw_params,
                                        SND_PCM_ACCESS_RW_INTERLEAVED);
    if (err < 0) {
        last_error_ = std::string("Cannot set access type: ") + snd_strerror(err);
        return false;
    }

    // Set sample format - signed 16-bit little-endian
    err = snd_pcm_hw_params_set_format(impl_->pcm_handle, hw_params,
                                        SND_PCM_FORMAT_S16_LE);
    if (err < 0) {
        last_error_ = std::string("Cannot set sample format: ") + snd_strerror(err);
        return false;
    }

    // Set sample rate
    unsigned int rate = config_.sample_rate;
    err = snd_pcm_hw_params_set_rate_near(impl_->pcm_handle, hw_params,
                                           &rate, nullptr);
    if (err < 0) {
        last_error_ = std::string("Cannot set sample rate: ") + snd_strerror(err);
        return false;
    }
    config_.sample_rate = rate;

    // Set channels
    err = snd_pcm_hw_params_set_channels(impl_->pcm_handle, hw_params,
                                          config_.channels);
    if (err < 0) {
        last_error_ = std::string("Cannot set channels: ") + snd_strerror(err);
        return false;
    }

    // Set buffer size
    snd_pcm_uframes_t buffer_size = config_.buffer_frames;
    err = snd_pcm_hw_params_set_buffer_size_near(impl_->pcm_handle, hw_params,
                                                  &buffer_size);
    if (err < 0) {
        last_error_ = std::string("Cannot set buffer size: ") + snd_strerror(err);
        return false;
    }
    config_.buffer_frames = buffer_size;

    // Set period size
    snd_pcm_uframes_t period_size = config_.period_frames;
    err = snd_pcm_hw_params_set_period_size_near(impl_->pcm_handle, hw_params,
                                                  &period_size, nullptr);
    if (err < 0) {
        last_error_ = std::string("Cannot set period size: ") + snd_strerror(err);
        return false;
    }
    config_.period_frames = period_size;

    // Apply hardware parameters
    err = snd_pcm_hw_params(impl_->pcm_handle, hw_params);
    if (err < 0) {
        last_error_ = std::string("Cannot set hardware parameters: ") + snd_strerror(err);
        return false;
    }

    // Prepare device
    err = snd_pcm_prepare(impl_->pcm_handle);
    if (err < 0) {
        last_error_ = std::string("Cannot prepare device: ") + snd_strerror(err);
        return false;
    }

    initialized_ = true;
    return true;
}

bool AudioPlayback::reinitialize(uint32_t sample_rate) {
    // Close existing device
    if (impl_->pcm_handle) {
        snd_pcm_close(impl_->pcm_handle);
        impl_->pcm_handle = nullptr;
    }
    initialized_ = false;

    // Update sample rate and reinitialize
    config_.sample_rate = sample_rate;
    return initialize();
}

bool AudioPlayback::play(const int16_t* samples, size_t num_samples) {
    if (!initialized_) {
        last_error_ = "Not initialized";
        return false;
    }

    impl_->playing = true;

    size_t frames_remaining = num_samples;
    const int16_t* ptr = samples;

    while (frames_remaining > 0) {
        snd_pcm_sframes_t frames = snd_pcm_writei(
            impl_->pcm_handle,
            ptr,
            frames_remaining
        );

        if (frames < 0) {
            // Handle underrun
            if (frames == -EPIPE) {
                snd_pcm_prepare(impl_->pcm_handle);
                continue;
            } else if (frames == -EAGAIN) {
                snd_pcm_wait(impl_->pcm_handle, 100);
                continue;
            } else {
                last_error_ = std::string("Write error: ") + snd_strerror(frames);
                impl_->playing = false;
                return false;
            }
        }

        frames_remaining -= frames;
        ptr += frames * config_.channels;
    }

    impl_->playing = false;
    return true;
}

bool AudioPlayback::play_async(const int16_t* samples, size_t num_samples) {
    // For now, just call blocking play
    // TODO: Implement proper async playback with a queue
    return play(samples, num_samples);
}

void AudioPlayback::stop() {
    if (impl_->pcm_handle) {
        snd_pcm_drop(impl_->pcm_handle);
        snd_pcm_prepare(impl_->pcm_handle);
    }
    impl_->playing = false;
}

void AudioPlayback::drain() {
    if (impl_->pcm_handle) {
        snd_pcm_drain(impl_->pcm_handle);
    }
}

bool AudioPlayback::is_initialized() const {
    return initialized_;
}

bool AudioPlayback::is_playing() const {
    return impl_->playing;
}

std::vector<std::string> AudioPlayback::list_devices() {
    std::vector<std::string> devices;

    // Add default device
    devices.push_back("default");

    // Enumerate hardware devices
    void** hints = nullptr;
    int err = snd_device_name_hint(-1, "pcm", &hints);
    if (err < 0) {
        return devices;
    }

    for (void** hint = hints; *hint != nullptr; ++hint) {
        char* name = snd_device_name_get_hint(*hint, "NAME");
        char* ioid = snd_device_name_get_hint(*hint, "IOID");

        // Only include output devices
        if (name && (!ioid || strcmp(ioid, "Output") == 0)) {
            devices.push_back(name);
        }

        if (name) free(name);
        if (ioid) free(ioid);
    }

    snd_device_name_free_hint(hints);
    return devices;
}

} // namespace openclaw
