/** @file onnx_diarization_provider.h @brief ONNX Runtime streaming Sortformer diarization provider.
 */

#ifndef RUNANYWHERE_ONNX_DIARIZATION_PROVIDER_H
#define RUNANYWHERE_ONNX_DIARIZATION_PROVIDER_H

#include <memory>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/diarization/rac_diarization_service.h"

namespace runanywhere::diarization {

/**
 * Streaming speaker-diarization provider backed by NVIDIA's stateful
 * `diar_streaming_sortformer_4spk-v2.1` ONNX graph (128-mel FastConformer +
 * Transformer + Sortformer head). The graph is a streaming step: the driver
 * owns the FIFO + speaker-cache embedding state and the mel frontend; this
 * class implements both, so offline `diarize()` and the persistent stream path
 * share one code path (offline = run all chunks through a transient state).
 */
class ONNXDiarizationProvider {
   public:
    ONNXDiarizationProvider();
    ~ONNXDiarizationProvider();

    ONNXDiarizationProvider(const ONNXDiarizationProvider&) = delete;
    ONNXDiarizationProvider& operator=(const ONNXDiarizationProvider&) = delete;

    rac_result_t initialize(const std::string& model_path);

    /** Offline diarization over a whole 16 kHz mono buffer. */
    rac_result_t diarize(const float* samples, size_t sample_count,
                         const rac_diarization_options_t& options,
                         rac_diarization_result_t* out_result);

    /** Open a persistent streaming session; publishes a non-NULL stream handle. */
    rac_result_t stream_create(const rac_diarization_options_t& options,
                               rac_handle_t* out_stream_handle);
    /** Feed one PCM chunk (samples==NULL && count==0 => final flush). */
    rac_result_t stream_feed_audio_chunk(rac_handle_t stream_handle, const float* samples,
                                         size_t sample_count,
                                         rac_diarization_stream_callback_t callback,
                                         void* user_data);
    rac_result_t stream_destroy(rac_handle_t stream_handle);

    void cleanup();
    bool is_ready() const;

   private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

}  // namespace runanywhere::diarization

#endif /* RUNANYWHERE_ONNX_DIARIZATION_PROVIDER_H */
