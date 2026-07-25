#ifndef RUNANYWHERE_SHERPA_MODEL_INSPECTOR_H
#define RUNANYWHERE_SHERPA_MODEL_INSPECTOR_H

#include <string>
#include <string_view>

namespace rac::backends::sherpa {

enum class SherpaOnnxEncoderKind {
    Unknown,
    Offline,
    OnlineTransducer,
};

struct SherpaOnnxEncoderContract {
    SherpaOnnxEncoderKind kind = SherpaOnnxEncoderKind::Unknown;
    bool uses_language_prompt = false;
};

/**
 * Inspect only the ONNX graph-input declarations needed to distinguish an
 * online transducer encoder from an offline encoder. Tensor payloads are
 * skipped with file seeks, so a multi-hundred-megabyte model is not copied
 * into memory during discovery.
 */
SherpaOnnxEncoderContract inspect_sherpa_onnx_encoder(const std::string& encoder_path);

/** Parse a Sherpa semantic version string and compare it with a required version. */
bool sherpa_runtime_version_at_least(std::string_view version, int required_major,
                                     int required_minor, int required_patch);

}  // namespace rac::backends::sherpa

#endif  // RUNANYWHERE_SHERPA_MODEL_INSPECTOR_H
