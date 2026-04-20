// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// LLM structured-output JSON extraction. Ports the capability from
// `sdk/runanywhere-commons/include/rac/features/llm/
// rac_llm_structured_output.h` into C++20.
//
// Extracts a complete JSON object `{...}` or array `[...]` from prose-mixed
// LLM output, handling escape sequences and nested braces/brackets.

#ifndef RA_CORE_STRUCTURED_OUTPUT_H
#define RA_CORE_STRUCTURED_OUTPUT_H

#include <optional>
#include <string>
#include <string_view>

namespace ra::core::util {

// Returns the first complete JSON object or array found in `text`, or
// std::nullopt if no well-formed JSON can be located. String escapes are
// honored so that `"}"` inside a JSON string doesn't falsely terminate
// the object.
std::optional<std::string> extract_json(std::string_view text);

}  // namespace ra::core::util

#endif  // RA_CORE_STRUCTURED_OUTPUT_H
