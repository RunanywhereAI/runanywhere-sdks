/** @file onnx_vocoder_provider.h @brief Pinned BigVGAN ONNX vocoder provider. */

#ifndef RUNANYWHERE_ONNX_VOCODER_PROVIDER_H
#define RUNANYWHERE_ONNX_VOCODER_PROVIDER_H

#include <memory>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/features/vocoder/rac_vocoder_types.h"

namespace runanywhere::vocoder {

class ONNXVocoderProvider {
   public:
    ONNXVocoderProvider();
    ~ONNXVocoderProvider();

    ONNXVocoderProvider(const ONNXVocoderProvider&) = delete;
    ONNXVocoderProvider& operator=(const ONNXVocoderProvider&) = delete;

    rac_result_t initialize(const std::string& model_path);
    rac_result_t vocode(const rac_vocoder_input_t& input, rac_vocoder_result_t* out_result);
    void cleanup();
    bool is_ready() const;

   private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

}  // namespace runanywhere::vocoder

#endif /* RUNANYWHERE_ONNX_VOCODER_PROVIDER_H */
