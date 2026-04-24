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

#include <nlohmann/json.hpp>

// Unified logging via rac_logger.h
#include "rac_logger.h"

// Log category for this module
#define LOG_CATEGORY "LLM.StructuredOutput"

namespace runanywhere {
namespace bridges {

namespace {

using json = nlohmann::json;

/**
 * @brief Parsed options derived from the JS-side optionsJson payload.
 *
 * Keeping this struct local to the .cpp file so the public header stays
 * free of third-party dependencies.
 */
struct ParsedStructuredOptions {
    int maxTokens = 1024;      // Enough headroom for JSON payloads
    double temperature = 0.1;  // Deterministic by default for valid JSON
    bool strict = true;        // Require schema to be embedded in prompt
    // JS side may override the schema (e.g. compiled/canonical form).
    // Empty string means "use the schema parameter as-is".
    std::string schemaOverride;
};

template <typename T>
T getOr(const json& j, const std::string& key, const T& fallback) {
    auto it = j.find(key);
    if (it == j.end() || it->is_null()) return fallback;
    try {
        return it->template get<T>();
    } catch (...) {
        return fallback;
    }
}

ParsedStructuredOptions parseOptions(const std::string& optionsJson) {
    ParsedStructuredOptions opts;
    if (optionsJson.empty()) return opts;

    json parsed;
    try {
        parsed = json::parse(optionsJson);
    } catch (const std::exception& e) {
        RAC_LOG_WARNING(LOG_CATEGORY, "Failed to parse optionsJson (%s); using defaults.", e.what());
        return opts;
    }

    if (!parsed.is_object()) {
        RAC_LOG_WARNING(LOG_CATEGORY, "optionsJson is not a JSON object; using defaults.");
        return opts;
    }

    // JS type is StructuredOutputOptions { maxTokens, temperature, strict, retries }.
    // Accept both camelCase (current JS shape) and snake_case (legacy / native callers).
    if (parsed.contains("maxTokens")) {
        opts.maxTokens = getOr<int>(parsed, "maxTokens", opts.maxTokens);
    } else {
        opts.maxTokens = getOr<int>(parsed, "max_tokens", opts.maxTokens);
    }
    opts.temperature = getOr<double>(parsed, "temperature", opts.temperature);
    opts.strict = getOr<bool>(parsed, "strict", opts.strict);
    opts.schemaOverride = getOr<std::string>(parsed, "schema", std::string{});
    return opts;
}

} // namespace

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

    const ParsedStructuredOptions parsedOpts = parseOptions(optionsJson);
    const std::string& effectiveSchema =
        parsedOpts.schemaOverride.empty() ? schema : parsedOpts.schemaOverride;

    // Prepare the prompt using RACommons structured output API.
    // In strict mode we always embed the schema in the prompt, matching the
    // semantics of OpenAI-style `strict: true` structured output.
    rac_structured_output_config_t config = RAC_STRUCTURED_OUTPUT_DEFAULT;
    config.json_schema = effectiveSchema.c_str();
    config.include_schema_in_prompt = parsedOpts.strict ? RAC_TRUE : RAC_FALSE;

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
        // Fallback: Build prompt manually. In strict mode we surface the schema
        // explicitly; in non-strict mode we still include it because the model
        // otherwise has no way to know the expected shape.
        RAC_LOG_DEBUG(LOG_CATEGORY, "Fallback to manual prompt preparation (strict=%s)",
                      parsedOpts.strict ? "true" : "false");
        if (parsedOpts.strict) {
            structuredPrompt =
                "You MUST respond with valid JSON that strictly conforms to this schema. "
                "Do not include any fields not present in the schema.\n\n"
                "Schema:\n" + effectiveSchema + "\n\n" +
                "User request: " + prompt + "\n\n" +
                "Respond with JSON only, no prose, no markdown fences:";
        } else {
            structuredPrompt =
                "You must respond with valid JSON matching this schema:\n" +
                effectiveSchema + "\n\n" +
                "User request: " + prompt + "\n\n" +
                "Respond with valid JSON only, no other text:";
        }
    }

    // Generate using LLMBridge, honoring caller-supplied generation options.
    LLMOptions opts;
    opts.maxTokens = parsedOpts.maxTokens;
    opts.temperature = parsedOpts.temperature;

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
