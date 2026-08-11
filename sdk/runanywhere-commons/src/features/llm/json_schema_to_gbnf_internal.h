#ifndef RAC_FEATURES_LLM_JSON_SCHEMA_TO_GBNF_INTERNAL_H
#define RAC_FEATURES_LLM_JSON_SCHEMA_TO_GBNF_INTERNAL_H

#include <string>

namespace rac::llm {

// Compile a JSON Schema document (UTF-8) to a llama.cpp-style GBNF grammar.
// Supports the same subset as sdk/runanywhere-python/runanywhere/grammar.py /
// sdk/runanywhere-electron/src/grammar.ts: object/array/string/number/integer/
// boolean/null/enum/const/anyOf plus maxItems via nested optional tails.
// Returns false on invalid JSON; *out_error is a short reason when provided.
bool json_schema_to_gbnf(const std::string& schema_json, std::string* out_grammar,
                         std::string* out_error = nullptr);

// One-retry repair prompt shared by every SDK generateStructured(mode=repair).
std::string structured_output_repair_prompt(const std::string& original_prompt,
                                            const std::string& invalid_output,
                                            const std::string& schema_json);

}  // namespace rac::llm

#endif  // RAC_FEATURES_LLM_JSON_SCHEMA_TO_GBNF_INTERNAL_H
