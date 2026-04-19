/**
 * @file StructuredOutputBridge.cpp
 * @brief Structured Output bridge implementation
 *
 * Uses RACommons structured output API for prompt preparation and JSON extraction.
 * Uses LLMBridge for actual text generation.
 * RACommons is REQUIRED - no stub implementations.
 */

#include "StructuredOutputBridge.hpp"
#include "LLMBridge.hpp"
#include <stdexcept>
#include <cstdlib> // For free()

// Unified logging via rac_logger.h
#include "rac_logger.h"

// Log category for this module
#define LOG_CATEGORY "LLM.StructuredOutput"

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
        throw std::runtime_error("StructuredOutputBridge: LLM model not loaded. Call loadModel() first.");
    }

    // Prepare the prompt using RACommons structured output API
    rac_structured_output_config_t config = RAC_STRUCTURED_OUTPUT_DEFAULT;
    config.json_schema = schema.c_str();
    config.include_schema_in_prompt = RAC_TRUE;

    char* preparedPrompt = nullptr;
    rac_result_t prepResult = rac_structured_output_prepare_prompt(
        prompt.c_str(),
        &config,
        &preparedPrompt
    );

    std::string structuredPrompt;
    if (prepResult == RAC_SUCCESS && preparedPrompt) {
        structuredPrompt = preparedPrompt;
        free(preparedPrompt);
    } else {
        // Fallback: Build prompt manually
        RAC_LOG_DEBUG(LOG_CATEGORY, "Fallback to manual prompt preparation");
        structuredPrompt =
            "You must respond with valid JSON matching this schema:\n" +
            schema + "\n\n" +
            "User request: " + prompt + "\n\n" +
            "Respond with valid JSON only, no other text:";
    }

    // Generate using LLMBridge
    LLMOptions opts;
    opts.maxTokens = 1024;
    opts.temperature = 0.1;  // Lower temperature for structured output
    // TODO: Parse optionsJson if provided

    LLMResult llmResult;
    try {
        llmResult = LLMBridge::shared().generate(structuredPrompt, opts);
    } catch (const std::runtime_error& e) {
        throw std::runtime_error("StructuredOutputBridge: LLM generation failed: " + std::string(e.what()));
    }

    if (llmResult.text.empty()) {
        throw std::runtime_error("StructuredOutputBridge: LLM generation returned empty text.");
    }

    // Extract JSON using RACommons API
    char* extractedJson = nullptr;
    size_t jsonLength = 0;
    rac_result_t extractResult = rac_structured_output_extract_json(
        llmResult.text.c_str(),
        &extractedJson,
        &jsonLength
    );

    if (extractResult == RAC_SUCCESS && extractedJson && jsonLength > 0) {
        result.json = std::string(extractedJson, jsonLength);
        result.success = true;
        free(extractedJson);
        RAC_LOG_INFO(LOG_CATEGORY, "Successfully extracted JSON (%zu bytes)", jsonLength);
    } else {
        // Fallback: Try manual extraction
        RAC_LOG_DEBUG(LOG_CATEGORY, "Fallback to manual JSON extraction");

        std::string text = llmResult.text;
        size_t start = 0, end = 0;

        // Try using RACommons to find JSON boundaries
        if (rac_structured_output_find_complete_json(text.c_str(), &start, &end) == RAC_TRUE) {
            result.json = text.substr(start, end - start);
            result.success = true;
        } else {
            // Manual fallback
            start = text.find('{');
            end = text.rfind('}');

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
                    throw std::runtime_error("StructuredOutputBridge: Could not extract valid JSON from response: " + text);
                }
            }
        }
    }

    // Validate the extracted JSON (optional but good for debugging)
    if (result.success) {
        rac_structured_output_validation_t validation = {};
        rac_result_t valResult = rac_structured_output_validate(
            result.json.c_str(),
            &config,
            &validation
        );

        if (valResult != RAC_SUCCESS || validation.is_valid != RAC_TRUE) {
            RAC_LOG_WARNING(LOG_CATEGORY, "Extracted JSON failed validation");
            // Don't throw - the JSON was extracted, just log warning
        }

        rac_structured_output_validation_free(&validation);
    }

    return result;
}

} // namespace bridges
} // namespace runanywhere
