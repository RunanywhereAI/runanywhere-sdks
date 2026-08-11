#ifndef RAC_FEATURES_LLM_STRUCTURED_OUTPUT_INTERNAL_H
#define RAC_FEATURES_LLM_STRUCTURED_OUTPUT_INTERNAL_H

#include <cstddef>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

#if defined(__GNUC__) || defined(__clang__)
#define RAC_STRUCTURED_OUTPUT_INTERNAL __attribute__((visibility("hidden")))
#else
#define RAC_STRUCTURED_OUTPUT_INTERNAL
#endif

typedef struct rac_structured_output_config {
    const char* json_schema;
    rac_bool_t include_schema_in_prompt;
} rac_structured_output_config_t;

static const rac_structured_output_config_t RAC_STRUCTURED_OUTPUT_DEFAULT = {
    .json_schema = RAC_NULL, .include_schema_in_prompt = RAC_TRUE};

typedef struct rac_structured_output_validation {
    rac_bool_t is_valid;
    const char* error_message;
    char* extracted_json;
} rac_structured_output_validation_t;

typedef struct rac_structured_output_parse_result {
    rac_bool_t is_valid;
    rac_bool_t contains_json;
    char* parsed_json;
    char* raw_text;
    char* error_message;
    char* validation_errors_json;
    rac_result_t error_code;
} rac_structured_output_parse_result_t;

extern "C" {

RAC_STRUCTURED_OUTPUT_INTERNAL rac_result_t rac_structured_output_extract_json(const char* text,
                                                                               char** out_json,
                                                                               size_t* out_length);
RAC_STRUCTURED_OUTPUT_INTERNAL rac_result_t
rac_structured_output_parse(const char* text, const rac_structured_output_config_t* config,
                            rac_structured_output_parse_result_t* out_result);
RAC_STRUCTURED_OUTPUT_INTERNAL rac_bool_t
rac_structured_output_find_complete_json(const char* text, size_t* out_start, size_t* out_end);
RAC_STRUCTURED_OUTPUT_INTERNAL rac_bool_t
rac_structured_output_find_matching_brace(const char* text, size_t start_pos, size_t* out_end_pos);
RAC_STRUCTURED_OUTPUT_INTERNAL rac_bool_t rac_structured_output_find_matching_bracket(
    const char* text, size_t start_pos, size_t* out_end_pos);
RAC_STRUCTURED_OUTPUT_INTERNAL rac_result_t rac_structured_output_prepare_prompt(
    const char* original_prompt, const rac_structured_output_config_t* config, char** out_prompt);
RAC_STRUCTURED_OUTPUT_INTERNAL rac_result_t
rac_structured_output_get_system_prompt(const char* json_schema, char** out_prompt);
RAC_STRUCTURED_OUTPUT_INTERNAL rac_result_t
rac_structured_output_validate(const char* text, const rac_structured_output_config_t* config,
                               rac_structured_output_validation_t* out_validation);
RAC_STRUCTURED_OUTPUT_INTERNAL void
rac_structured_output_validation_free(rac_structured_output_validation_t* validation);
RAC_STRUCTURED_OUTPUT_INTERNAL void
rac_structured_output_parse_result_free(rac_structured_output_parse_result_t* result);

}  // extern "C"

#undef RAC_STRUCTURED_OUTPUT_INTERNAL

#endif  // RAC_FEATURES_LLM_STRUCTURED_OUTPUT_INTERNAL_H
