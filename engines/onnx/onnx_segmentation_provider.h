/** @file onnx_segmentation_provider.h
 *  @brief Generic ONNX Runtime semantic-segmentation provider (model-agnostic).
 */

#ifndef RUNANYWHERE_ONNX_SEGMENTATION_PROVIDER_H
#define RUNANYWHERE_ONNX_SEGMENTATION_PROVIDER_H

#include <memory>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/features/segmentation/rac_segmentation_types.h"

namespace runanywhere::segmentation {

class ONNXSegmentationProvider {
   public:
    ONNXSegmentationProvider();
    ~ONNXSegmentationProvider();

    ONNXSegmentationProvider(const ONNXSegmentationProvider&) = delete;
    ONNXSegmentationProvider& operator=(const ONNXSegmentationProvider&) = delete;

    rac_result_t initialize(const std::string& model_path);
    rac_result_t segment(const rac_segmentation_image_t& image,
                         const rac_segmentation_options_t& options,
                         rac_segmentation_result_t* out_result);
    void cleanup();
    bool is_ready() const;

   private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

}  // namespace runanywhere::segmentation

#endif /* RUNANYWHERE_ONNX_SEGMENTATION_PROVIDER_H */
