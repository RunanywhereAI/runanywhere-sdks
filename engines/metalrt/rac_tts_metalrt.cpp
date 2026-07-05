/**
 * @file rac_tts_metalrt.cpp
 * @brief MetalRT TTS backend — wraps metalrt_tts_* for Kokoro text-to-speech
 */

#include "rac_tts_metalrt.h"

#include "metalrt_c_api.h"
#include "rac_runtime_metal.h"

#include <atomic>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <mutex>

#include "rac/core/rac_logger.h"

static const char* LOG_CAT = "TTS.MetalRT";

// See rac_llm_metalrt.cpp for the full ADR. Same
// acquire/release pin pattern: destroy waits on cv_ for in-flight synthesize
// pins to drain before tearing down the TTS handle and freeing impl.
struct rac_tts_metalrt_impl {
    void* handle = nullptr;  // metalrt_tts_create() handle
    std::atomic<bool> loaded{false};
    mutable std::mutex mutex_;
    std::condition_variable cv_;
    int refcount_ = 0;  // guarded by mutex_
};

namespace {

class MetalRTTTSPin {
   public:
    explicit MetalRTTTSPin(rac_tts_metalrt_impl* impl) : impl_(impl) {
        if (impl_ == nullptr)
            return;
        std::lock_guard<std::mutex> lock(impl_->mutex_);
        if (!impl_->loaded.load(std::memory_order_acquire) || impl_->handle == nullptr)
            return;
        handle_ = impl_->handle;
        impl_->refcount_++;
        pinned_ = true;
    }
    MetalRTTTSPin(const MetalRTTTSPin&) = delete;
    MetalRTTTSPin& operator=(const MetalRTTTSPin&) = delete;
    ~MetalRTTTSPin() {
        if (!pinned_)
            return;
        bool notify = false;
        {
            std::lock_guard<std::mutex> lock(impl_->mutex_);
            impl_->refcount_--;
            notify = (impl_->refcount_ == 0);
        }
        if (notify)
            impl_->cv_.notify_all();
    }
    bool pinned() const { return pinned_; }
    void* handle() const { return handle_; }

   private:
    rac_tts_metalrt_impl* impl_ = nullptr;
    void* handle_ = nullptr;
    bool pinned_ = false;
};

}  // namespace

extern "C" {

rac_result_t rac_tts_metalrt_create(const char* model_path, rac_handle_t* out_handle) {
    if (!out_handle)
        return RAC_ERROR_NULL_POINTER;
    rac_result_t runtime_rc = rac_metal_runtime_require_available();
    if (runtime_rc != RAC_SUCCESS)
        return runtime_rc;

    auto* impl = new (std::nothrow) rac_tts_metalrt_impl();
    if (!impl)
        return RAC_ERROR_OUT_OF_MEMORY;

    impl->handle = metalrt_tts_create();
    if (!impl->handle) {
        delete impl;
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    if (model_path && model_path[0] != '\0') {
        if (!metalrt_tts_load(impl->handle, model_path)) {
            metalrt_tts_destroy(impl->handle);
            delete impl;
            rac_error_set_details("metalrt_tts_load() failed");
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }
        impl->loaded.store(true, std::memory_order_release);
        RAC_LOG_INFO(LOG_CAT, "Kokoro TTS model loaded: %s", model_path);
    }

    *out_handle = static_cast<rac_handle_t>(impl);
    return RAC_SUCCESS;
}

void rac_tts_metalrt_destroy(rac_handle_t handle) {
    if (!handle)
        return;
    auto* impl = static_cast<rac_tts_metalrt_impl*>(handle);
    {
        std::unique_lock<std::mutex> lock(impl->mutex_);
        impl->loaded.store(false, std::memory_order_release);
        impl->cv_.wait(lock, [impl] { return impl->refcount_ == 0; });
        if (impl->handle) {
            metalrt_tts_destroy(impl->handle);
            impl->handle = nullptr;
        }
    }
    delete impl;
}

rac_bool_t rac_tts_metalrt_is_loaded(rac_handle_t handle) {
    if (!handle)
        return RAC_FALSE;
    auto* impl = static_cast<rac_tts_metalrt_impl*>(handle);
    return impl->loaded.load(std::memory_order_acquire) ? RAC_TRUE : RAC_FALSE;
}

rac_result_t rac_tts_metalrt_synthesize(rac_handle_t handle, const char* text,
                                        const rac_tts_options_t* options,
                                        rac_tts_result_t* out_result) {
    if (!handle || !text || !out_result)
        return RAC_ERROR_NULL_POINTER;
    auto* impl = static_cast<rac_tts_metalrt_impl*>(handle);
    MetalRTTTSPin pin(impl);
    if (!pin.pinned())
        return RAC_ERROR_BACKEND_NOT_READY;

    const char* voice = "af_heart";  // default voice
    float speed = 1.0f;

    if (options) {
        if (options->voice && options->voice[0] != '\0') {
            voice = options->voice;
        }
        if (options->rate > 0.0f) {
            speed = options->rate;
        }
    }

    struct MetalRTAudio audio = metalrt_tts_synthesize(pin.handle(), text, voice, speed);

    if (!audio.samples || audio.num_samples <= 0) {
        rac_error_set_details("metalrt_tts_synthesize returned no audio");
        return RAC_ERROR_INFERENCE_FAILED;
    }

    // Copy samples into RAC-owned buffer
    size_t buf_size = static_cast<size_t>(audio.num_samples) * sizeof(float);
    out_result->audio_data = malloc(buf_size);
    if (!out_result->audio_data) {
        metalrt_tts_free_audio(audio);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    memcpy(out_result->audio_data, audio.samples, buf_size);
    out_result->audio_size = buf_size;
    out_result->audio_format = RAC_AUDIO_FORMAT_PCM;
    out_result->sample_rate = audio.sample_rate;
    out_result->duration_ms =
        static_cast<int64_t>((static_cast<double>(audio.num_samples) / audio.sample_rate) * 1000.0);
    out_result->processing_time_ms = static_cast<int64_t>(audio.synthesis_ms);

    metalrt_tts_free_audio(audio);
    return RAC_SUCCESS;
}

}  // extern "C"
