/**
 * @file rac_stt_metalrt.cpp
 * @brief MetalRT STT backend — wraps metalrt_whisper_* for speech-to-text
 */

#include "rac_stt_metalrt.h"

#include "metalrt_c_api.h"

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <vector>

#include "rac/audio/rac_audio_convert.h"
#include "rac/core/rac_logger.h"
#include "rac_runtime_metal.h"

static const char *LOG_CAT = "STT.MetalRT";

// engines-other-008: see rac_llm_metalrt.cpp for the ADR. Same pattern:
// guard handle / loaded with mutex_ + atomic on lifecycle paths; transcribe
// reads loaded with acquire ordering and runs lock-free.
struct rac_stt_metalrt_impl {
  void *handle = nullptr; // metalrt_whisper_create() handle
  std::atomic<bool> loaded{false};
  mutable std::mutex mutex_;
};

extern "C" {

rac_result_t rac_stt_metalrt_create(const char *model_path,
                                    rac_handle_t *out_handle) {
  if (!out_handle)
    return RAC_ERROR_NULL_POINTER;
  rac_result_t runtime_rc = rac_metal_runtime_require_available();
  if (runtime_rc != RAC_SUCCESS)
    return runtime_rc;

  auto *impl = new (std::nothrow) rac_stt_metalrt_impl();
  if (!impl)
    return RAC_ERROR_OUT_OF_MEMORY;

  impl->handle = metalrt_whisper_create();
  if (!impl->handle) {
    delete impl;
    return RAC_ERROR_BACKEND_INIT_FAILED;
  }

  if (model_path && model_path[0] != '\0') {
    if (!metalrt_whisper_load(impl->handle, model_path)) {
      metalrt_whisper_destroy(impl->handle);
      delete impl;
      rac_error_set_details("metalrt_whisper_load() failed");
      return RAC_ERROR_MODEL_LOAD_FAILED;
    }
    impl->loaded.store(true, std::memory_order_release);
    RAC_LOG_INFO(LOG_CAT, "Whisper model loaded: %s", model_path);
  }

  *out_handle = static_cast<rac_handle_t>(impl);
  return RAC_SUCCESS;
}

void rac_stt_metalrt_destroy(rac_handle_t handle) {
  if (!handle)
    return;
  auto *impl = static_cast<rac_stt_metalrt_impl *>(handle);
  {
    std::lock_guard<std::mutex> lock(impl->mutex_);
    if (impl->handle) {
      metalrt_whisper_destroy(impl->handle);
      impl->handle = nullptr;
    }
    impl->loaded.store(false, std::memory_order_release);
  }
  delete impl;
}

rac_result_t rac_stt_metalrt_transcribe(rac_handle_t handle,
                                        const void *audio_data,
                                        size_t audio_size,
                                        const rac_stt_options_t *options,
                                        rac_stt_result_t *out_result) {
  (void)options;
  if (!handle || !audio_data || !out_result)
    return RAC_ERROR_NULL_POINTER;
  auto *impl = static_cast<rac_stt_metalrt_impl *>(handle);
  if (!impl->loaded.load(std::memory_order_acquire))
    return RAC_ERROR_BACKEND_NOT_READY;

  // SDK audio capture sends Int16 PCM at 16 kHz.
  // Convert to Float32 normalized [-1.0, 1.0] for metalrt_whisper_transcribe.
  const auto *int16_samples = static_cast<const int16_t *>(audio_data);
  int n_samples = static_cast<int>(audio_size / sizeof(int16_t));
  int sample_rate = 16000;

  std::vector<float> float_samples(n_samples);
  rac::audio::rac_audio_pcm16_to_float32(int16_samples,
                                         static_cast<size_t>(n_samples),
                                         float_samples.data());

  RAC_LOG_INFO(LOG_CAT, "Transcribing %d samples (%.1fs) at %d Hz", n_samples,
               static_cast<float>(n_samples) / sample_rate, sample_rate);

  const char *text = metalrt_whisper_transcribe(
      impl->handle, float_samples.data(), n_samples, sample_rate);
  if (!text) {
    rac_error_set_details("metalrt_whisper_transcribe returned null");
    return RAC_ERROR_INFERENCE_FAILED;
  }

  out_result->text = strdup(text);
  if (!out_result->text) {
    metalrt_whisper_free_text(text);
    return RAC_ERROR_OUT_OF_MEMORY;
  }
  out_result->detected_language = nullptr;
  out_result->words = nullptr;
  out_result->num_words = 0;
  out_result->confidence = 1.0f;
  out_result->processing_time_ms =
      static_cast<int64_t>(metalrt_whisper_last_encode_ms(impl->handle) +
                           metalrt_whisper_last_decode_ms(impl->handle));

  metalrt_whisper_free_text(text);
  return RAC_SUCCESS;
}

} // extern "C"
