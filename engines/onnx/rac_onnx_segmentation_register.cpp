/** @file rac_onnx_segmentation_register.cpp @brief SegFormer service-vtable adapter. */

#include "onnx_segmentation_provider.h"

#include <memory>
#include <new>

#include "rac/features/segmentation/rac_segmentation_service.h"

namespace {

struct onnx_segmentation_handle {
    std::unique_ptr<runanywhere::segmentation::ONNXSegmentationProvider> provider;
};

rac_result_t initialize(void* impl, const char* model_path) {
    if (!impl || !model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    try {
        auto* handle = static_cast<onnx_segmentation_handle*>(impl);
        return handle->provider->initialize(model_path);
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        return RAC_ERROR_MODEL_VALIDATION_FAILED;
    }
}

rac_result_t segment(void* impl, const rac_segmentation_image_t* image,
                     const rac_segmentation_options_t* options,
                     rac_segmentation_result_t* out_result) {
    if (!impl || !image || !options || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    try {
        auto* handle = static_cast<onnx_segmentation_handle*>(impl);
        return handle->provider->segment(*image, *options, out_result);
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
        static_cast<onnx_segmentation_handle*>(impl)->provider->cleanup();
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_INTERNAL;
    }
}

void destroy(void* impl) {
    try {
        delete static_cast<onnx_segmentation_handle*>(impl);
    } catch (...) {}
}

rac_result_t create(const char* model_id, const char*, void** out_impl) {
    if (!model_id || !out_impl) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = nullptr;
    try {
        auto handle = std::make_unique<onnx_segmentation_handle>();
        handle->provider = std::make_unique<runanywhere::segmentation::ONNXSegmentationProvider>();
        *out_impl = handle.release();
        return RAC_SUCCESS;
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

}  // namespace

extern "C" const rac_segmentation_service_ops_t g_onnx_segmentation_ops = {
    .initialize = initialize,
    .segment = segment,
    .cleanup = cleanup,
    .destroy = destroy,
    .create = create,
};
