/**
 * @file StructuredOutputBridge.hpp
 * @brief Structured Output bridge for React Native
 *
 * Matches Swift's RunAnywhere+StructuredOutput.swift pattern, providing:
 * - JSON schema-guided generation
 * - Structured output extraction
 */

#pragma once

#include <string>

#ifdef HAS_RACOMMONS
#include "rac/features/llm/rac_llm_structured_output.h"
#else
typedef int rac_result_t;
#define RAC_SUCCESS 0
#endif

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
