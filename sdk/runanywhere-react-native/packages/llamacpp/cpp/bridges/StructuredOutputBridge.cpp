/**
 * @file StructuredOutputBridge.cpp
 * @brief Structured Output bridge implementation
 */

#include "StructuredOutputBridge.hpp"
#include "LLMBridge.hpp"

#if defined(ANDROID) || defined(__ANDROID__)
#include <android/log.h>
#define LOG_TAG "StructuredOutputBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#define LOGI(...) printf(__VA_ARGS__); printf("\n")
#define LOGE(...) printf(__VA_ARGS__); printf("\n")
#endif

namespace runanywhere {
namespace bridges {

StructuredOutputBridge& StructuredOutputBridge::shared() {
    static StructuredOutputBridge instance;
    return instance;
}

StructuredOutputResult StructuredOutputBridge::generate(
    const std::string& prompt,
    const std::string& schema,
    const std::string& optionsJson
) {
    StructuredOutputResult result;

    if (!LLMBridge::shared().isLoaded()) {
        result.error = "LLM model not loaded";
        return result;
    }

#ifdef HAS_RACOMMONS
    // Use RAC structured output API if available
    rac_llm_structured_output_config_t config = {};
    config.schema = schema.c_str();

    char* output = nullptr;
    rac_result_t ret = rac_llm_generate_structured(
        prompt.c_str(),
        &config,
        &output
    );

    if (ret == RAC_SUCCESS && output) {
        result.json = std::string(output);
        result.success = true;
        free(output);
    } else {
        result.error = "Structured generation failed";
    }
#else
    // Fallback: Use regular generation with schema in prompt
    std::string structuredPrompt =
        "You must respond with valid JSON matching this schema:\n" +
        schema + "\n\n" +
        "User request: " + prompt + "\n\n" +
        "Respond with valid JSON only, no other text:";

    LLMOptions opts;
    opts.maxTokens = 1024;
    opts.temperature = 0.1;  // Lower temperature for structured output

    auto llmResult = LLMBridge::shared().generate(structuredPrompt, opts);

    if (!llmResult.text.empty()) {
        // Try to extract JSON from response
        std::string text = llmResult.text;

        // Find JSON boundaries
        size_t start = text.find('{');
        size_t end = text.rfind('}');

        if (start != std::string::npos && end != std::string::npos && end > start) {
            result.json = text.substr(start, end - start + 1);
            result.success = true;
        } else {
            // Try array
            start = text.find('[');
            end = text.rfind(']');
            if (start != std::string::npos && end != std::string::npos && end > start) {
                result.json = text.substr(start, end - start + 1);
                result.success = true;
            } else {
                result.error = "Could not extract valid JSON from response";
                result.json = text;
            }
        }
    } else {
        result.error = "Generation failed";
    }
#endif

    return result;
}

} // namespace bridges
} // namespace runanywhere
