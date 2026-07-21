/** @file rac_onnx_diarization_register.cpp @brief Sortformer diarization service-vtable adapter. */

#include "onnx_diarization_provider.h"

#include <memory>
#include <new>

#include "rac/features/diarization/rac_diarization_service.h"

namespace {

struct onnx_diarization_handle {
    std::unique_ptr<runanywhere::diarization::ONNXDiarizationProvider> provider;
};

rac_result_t initialize(void* impl, const char* model_path) {
    if (!impl || !model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    try {
        auto* handle = static_cast<onnx_diarization_handle*>(impl);
        return handle->provider->initialize(model_path);
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        return RAC_ERROR_MODEL_VALIDATION_FAILED;
    }
}

rac_result_t diarize(void* impl, const float* samples, size_t sample_count,
                     const rac_diarization_options_t* options,
                     rac_diarization_result_t* out_result) {
    if (!impl || !samples || !options || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    try {
        auto* handle = static_cast<onnx_diarization_handle*>(impl);
        return handle->provider->diarize(samples, sample_count, *options, out_result);
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        return RAC_ERROR_INFERENCE_FAILED;
    }
}

rac_result_t stream_create(void* impl, const rac_diarization_options_t* options,
                           rac_handle_t* out_stream_handle) {
    if (!impl || !options || !out_stream_handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    try {
        auto* handle = static_cast<onnx_diarization_handle*>(impl);
        return handle->provider->stream_create(*options, out_stream_handle);
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        return RAC_ERROR_INFERENCE_FAILED;
    }
}

rac_result_t stream_feed_audio_chunk(void* impl, rac_handle_t stream_handle, const float* samples,
                                     size_t sample_count,
                                     rac_diarization_stream_callback_t callback, void* user_data) {
    if (!impl || !stream_handle || !callback) {
        return RAC_ERROR_NULL_POINTER;
    }
    try {
        auto* handle = static_cast<onnx_diarization_handle*>(impl);
        return handle->provider->stream_feed_audio_chunk(stream_handle, samples, sample_count,
                                                         callback, user_data);
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        return RAC_ERROR_INFERENCE_FAILED;
    }
}

rac_result_t stream_destroy(void* impl, rac_handle_t stream_handle) {
    if (!impl || !stream_handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    try {
        auto* handle = static_cast<onnx_diarization_handle*>(impl);
        return handle->provider->stream_destroy(stream_handle);
    } catch (...) {
        return RAC_ERROR_INTERNAL;
    }
}

rac_result_t cleanup(void* impl) {
    if (!impl) {
        return RAC_ERROR_NULL_POINTER;
    }
    try {
        static_cast<onnx_diarization_handle*>(impl)->provider->cleanup();
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_INTERNAL;
    }
}

void destroy(void* impl) {
    try {
        delete static_cast<onnx_diarization_handle*>(impl);
    } catch (...) {}
}

rac_result_t create(const char* model_id, const char*, void** out_impl) {
    if (!model_id || !out_impl) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = nullptr;
    try {
        auto handle = std::make_unique<onnx_diarization_handle>();
        handle->provider = std::make_unique<runanywhere::diarization::ONNXDiarizationProvider>();
        *out_impl = handle.release();
        return RAC_SUCCESS;
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

}  // namespace

extern "C" const rac_diarization_service_ops_t g_onnx_diarization_ops = {
    .initialize = initialize,
    .diarize = diarize,
    .stream_create = stream_create,
    .stream_feed_audio_chunk = stream_feed_audio_chunk,
    .stream_destroy = stream_destroy,
    .cleanup = cleanup,
    .destroy = destroy,
    .create = create,
};
