// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — structured-output C ABI.
//
// Wraps `core/util/structured_output.{h,cpp}` so frontends can extract
// JSON objects/arrays out of LLM prose without re-implementing the
// brace-matching / escape-aware parser in every language. Mirrors the
// legacy `rac_llm_structured_output.h` capability surface.

#ifndef RA_STRUCTURED_H
#define RA_STRUCTURED_H

#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Frontend-supplied configuration for system-prompt augmentation.
// ---------------------------------------------------------------------------
typedef struct {
    const char* json_schema;        // Optional JSON Schema (may be NULL)
    uint8_t     wrap_in_code_block; // 0/1 — instruct LLM to wrap in ```json
    uint8_t     strict;             // 0/1 — refuse non-JSON answers
    uint8_t     _reserved0[2];
    int32_t     max_attempts;       // 0 = single-shot
} ra_structured_output_config_t;

typedef struct {
    uint8_t  is_valid;             // 0/1
    uint8_t  _reserved0[3];
    char*    error_message;        // Heap-allocated; free with ra_structured_output_validation_free
} ra_structured_output_validation_t;

// ---------------------------------------------------------------------------
// JSON extraction
// ---------------------------------------------------------------------------

// Extract the first complete JSON object/array from `text`. Returns RA_OK and
// a heap-allocated string in `*out_json` on success; RA_ERR_INVALID_ARGUMENT
// if no JSON is found. Caller MUST free with `ra_structured_output_string_free`.
ra_status_t ra_structured_output_extract_json(const char* text, char** out_json);

// Find the position of a complete JSON object/array starting at `text + offset`.
// Returns the byte offset of the first matched character on success; -1 if no
// complete JSON is found. Stateless string-search helper for streaming use.
int32_t ra_structured_output_find_complete_json(const char* text, int32_t offset);

// Find the matching brace `}` for the `{` at `text[open_offset]`. Returns the
// offset of the closing brace, or -1 if unmatched / out of range.
int32_t ra_structured_output_find_matching_brace(const char* text, int32_t open_offset);

// Same, but for `[ ]`.
int32_t ra_structured_output_find_matching_bracket(const char* text, int32_t open_offset);

// ---------------------------------------------------------------------------
// Prompt augmentation
// ---------------------------------------------------------------------------

// Build a system-prompt prefix that tells the LLM to emit JSON conforming to
// `cfg->json_schema`. Returns a heap-allocated string.
ra_status_t ra_structured_output_get_system_prompt(
    const ra_structured_output_config_t* cfg, char** out_prompt);

// Augment an existing user query with structured-output guidance based on cfg.
// Returns a heap-allocated string.
ra_status_t ra_structured_output_prepare_prompt(
    const char*                          user_query,
    const ra_structured_output_config_t* cfg,
    char**                                out_prompt);

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

// Validate `json_text` against `json_schema`. The current implementation
// only checks that `json_text` is well-formed JSON; full JSONSchema validation
// is delegated to the frontend's native library (Codable, Gson, etc.).
ra_status_t ra_structured_output_validate(const char* json_text,
                                           const char* json_schema,
                                           ra_structured_output_validation_t* out_validation);

// Free heap-allocated fields inside a validation result.
void ra_structured_output_validation_free(ra_structured_output_validation_t* v);

// ---------------------------------------------------------------------------
// Memory ownership
// ---------------------------------------------------------------------------

// Release a heap string returned by any helper above.
void ra_structured_output_string_free(char* str);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_STRUCTURED_H
