/** @file rac_onnx_vocoder_register.cpp @brief BigVGAN vocoder service-vtable adapter. */

#include "onnx_vocoder_provider.h"

#include <memory>
#include <new>

#include "rac/features/vocoder/rac_vocoder_service.h"

namespace {

struct onnx_vocoder_handle {
    std::unique_ptr<runanywhere::vocoder::ONNXVocoderProvider> provider;
};

rac_result_t initialize(void* impl, const char* model_path) {
    if (!impl || !model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    try {
        return static_cast<onnx_vocoder_handle*>(impl)->provider->initialize(model_path);
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        return RAC_ERROR_MODEL_VALIDATION_FAILED;
    }
}

rac_result_t vocode(void* impl, const rac_vocoder_input_t* input,
                    rac_vocoder_result_t* out_result) {
    if (!impl || !input || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    try {
        return static_cast<onnx_vocoder_handle*>(impl)->provider->vocode(*input, out_result);
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        return RAC_ERROR_INFERENCE_FAILED;
    }
}

rac_result_t cleanup(void* impl) {
    if (!impl) {
        return RAC_ERROR_NULL_POINTER;
    }
    try {
        static_cast<onnx_vocoder_handle*>(impl)->provider->cleanup();
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_INTERNAL;
    }
}

void destroy(void* impl) {
    try {
        delete static_cast<onnx_vocoder_handle*>(impl);
    } catch (...) {}
}

rac_result_t create(const char* model_id, const char*, void** out_impl) {
    if (!model_id || !out_impl) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = nullptr;
    try {
        auto handle = std::make_unique<onnx_vocoder_handle>();
        handle->provider = std::make_unique<runanywhere::vocoder::ONNXVocoderProvider>();
        *out_impl = handle.release();
        return RAC_SUCCESS;
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

}  // namespace

extern "C" const rac_vocoder_service_ops_t g_onnx_vocoder_ops = {
    .initialize = initialize,
    .vocode = vocode,
    .cleanup = cleanup,
    .destroy = destroy,
    .create = create,
};
