// =============================================================================
// Audio Capture - ALSA implementation
// =============================================================================

#include "audio_capture.h"

#include <alsa/asoundlib.h>
#include <thread>
#include <atomic>
#include <vector>
#include <cstring>

namespace openclaw {

// =============================================================================
// Implementation
// =============================================================================

struct AudioCapture::Impl {
    snd_pcm_t* pcm_handle = nullptr;
    std::thread capture_thread;
    std::atomic<bool> running{false};
    std::vector<int16_t> buffer;
};

AudioCapture::AudioCapture()
    : AudioCapture(AudioCaptureConfig::defaults()) {
}

AudioCapture::AudioCapture(const AudioCaptureConfig& config)
    : impl_(std::make_unique<Impl>())
    , config_(config) {
}

AudioCapture::~AudioCapture() {
    stop();
    if (impl_->pcm_handle) {
        snd_pcm_close(impl_->pcm_handle);
        impl_->pcm_handle = nullptr;
    }
}

bool AudioCapture::initialize() {
    if (initialized_) {
        return true;
    }

    int err;

    // Open PCM device for capture
    err = snd_pcm_open(&impl_->pcm_handle, config_.device.c_str(),
                       SND_PCM_STREAM_CAPTURE, 0);
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

    // Set channels (mono)
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

    // Allocate buffer
    impl_->buffer.resize(config_.period_frames * config_.channels);

    initialized_ = true;
    return true;
}

void AudioCapture::set_callback(AudioCaptureCallback callback) {
    callback_ = std::move(callback);
}

bool AudioCapture::start() {
    if (!initialized_) {
        last_error_ = "Not initialized";
        return false;
    }

    if (running_) {
        return true;  // Already running
    }

    impl_->running = true;
    running_ = true;

    // Start capture thread
    impl_->capture_thread = std::thread([this]() {
        while (impl_->running) {
            // Read audio data
            snd_pcm_sframes_t frames = snd_pcm_readi(
                impl_->pcm_handle,
                impl_->buffer.data(),
                config_.period_frames
            );

            if (frames < 0) {
                // Handle underrun/overrun
                if (frames == -EPIPE) {
                    snd_pcm_prepare(impl_->pcm_handle);
                    continue;
                } else if (frames == -EAGAIN) {
                    continue;
                } else {
                    // Fatal error
                    impl_->running = false;
                    break;
                }
            }

            // Invoke callback with captured audio
            if (callback_ && frames > 0) {
                callback_(impl_->buffer.data(), static_cast<size_t>(frames));
            }
        }
    });

    return true;
}

void AudioCapture::stop() {
    if (!running_) {
        return;
    }

    impl_->running = false;
    running_ = false;

    if (impl_->capture_thread.joinable()) {
        impl_->capture_thread.join();
    }

    // Drain remaining samples
    if (impl_->pcm_handle) {
        snd_pcm_drop(impl_->pcm_handle);
    }
}

bool AudioCapture::is_running() const {
    return running_;
}

bool AudioCapture::is_initialized() const {
    return initialized_;
}

std::vector<std::string> AudioCapture::list_devices() {
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

        // Only include capture devices
        if (name && (!ioid || strcmp(ioid, "Input") == 0)) {
            devices.push_back(name);
        }

        if (name) free(name);
        if (ioid) free(ioid);
    }

    snd_device_name_free_hint(hints);
    return devices;
}

} // namespace openclaw
