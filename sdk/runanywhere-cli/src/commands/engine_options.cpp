#include "commands/engine_options.h"

#include <algorithm>
#include <cctype>

namespace rcli::commands {

bool parse_engine_hint(const std::string& engine,
                       runanywhere::v1::InferenceFramework* out_framework,
                       std::string* error) {
    if (!out_framework) {
        return false;
    }
    *out_framework = runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED;
    std::string normalized = engine;
    std::transform(normalized.begin(), normalized.end(), normalized.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    if (normalized.empty()) {
        return true;
    }
    if (normalized == "mlx") {
        *out_framework = runanywhere::v1::INFERENCE_FRAMEWORK_MLX;
        return true;
    }
    if (normalized == "llamacpp" || normalized == "llama.cpp" || normalized == "llama_cpp" ||
        normalized == "llama-cpp") {
        *out_framework = runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP;
        return true;
    }
    if (normalized == "onnx") {
        *out_framework = runanywhere::v1::INFERENCE_FRAMEWORK_ONNX;
        return true;
    }
    if (normalized == "sherpa") {
        *out_framework = runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA;
        return true;
    }
    if (error) {
        *error = "unsupported engine '" + engine + "'";
    }
    return false;
}

bool resolve_engine_hint(const std::string& engine, EngineHintResolution* out_resolution,
                         std::string* error) {
    if (!out_resolution) {
        if (error) {
            *error = "engine resolution output is required";
        }
        return false;
    }
    *out_resolution = EngineHintResolution{};
    if (!parse_engine_hint(engine, &out_resolution->framework, error)) {
        return false;
    }
    if (out_resolution->framework != runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED) {
        out_resolution->resolve_options.has_framework = true;
        out_resolution->resolve_options.framework = out_resolution->framework;
    }
    return true;
}

}  // namespace rcli::commands
