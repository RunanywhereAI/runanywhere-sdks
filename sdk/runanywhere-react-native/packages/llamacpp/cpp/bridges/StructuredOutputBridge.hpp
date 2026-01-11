/**
 * @file StructuredOutputBridge.hpp
 * @brief Structured Output bridge for React Native
 *
 * Matches Swift's RunAnywhere+StructuredOutput.swift pattern, providing:
 * - JSON schema-guided generation
 * - Structured output extraction
 *
 * Aligned with rac_llm_structured_output.h API.
 * RACommons is REQUIRED - no stub implementations.
 */

#pragma once

#include <string>

// RACommons structured output header - REQUIRED (flat include paths)
#include "rac_llm_structured_output.h"
#include "rac_llm_types.h"

namespace runanywhere {
namespace bridges {

/**
 * @brief Structured output result
 */
struct StructuredOutputResult {
    std::string json;
    bool success = false;
    std::string error;
};

/**
 * @brief Structured Output bridge singleton
 *
 * Generates LLM output following a JSON schema.
 * NOTE: RACommons is REQUIRED. All methods will throw std::runtime_error if
 * the underlying C API calls fail.
 */
class StructuredOutputBridge {
public:
    static StructuredOutputBridge& shared();

    /**
     * Generate structured output following a JSON schema
     * @param prompt User prompt
     * @param schema JSON schema string
     * @param optionsJson Generation options
     * @return Structured output result
     */
    StructuredOutputResult generate(
        const std::string& prompt,
        const std::string& schema,
        const std::string& optionsJson = ""
    );

private:
    StructuredOutputBridge() = default;
    ~StructuredOutputBridge() = default;

    StructuredOutputBridge(const StructuredOutputBridge&) = delete;
    StructuredOutputBridge& operator=(const StructuredOutputBridge&) = delete;
};

} // namespace bridges
} // namespace runanywhere
