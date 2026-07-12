#ifndef RAC_TOOL_CALLING_INTERNAL_H
#define RAC_TOOL_CALLING_INTERNAL_H

#include "rac/core/rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum rac_tool_call_format {
    RAC_TOOL_FORMAT_DEFAULT = 0,
    RAC_TOOL_FORMAT_LFM2 = 1,
    RAC_TOOL_FORMAT_COUNT
} rac_tool_call_format_t;

typedef enum rac_tool_param_type {
    RAC_TOOL_PARAM_STRING = 0,
    RAC_TOOL_PARAM_NUMBER = 1,
    RAC_TOOL_PARAM_BOOLEAN = 2,
    RAC_TOOL_PARAM_OBJECT = 3,
    RAC_TOOL_PARAM_ARRAY = 4
} rac_tool_param_type_t;

typedef struct rac_tool_parameter {
    const char* name;
    rac_tool_param_type_t type;
    const char* description;
    rac_bool_t required;
    const char* enum_values;
} rac_tool_parameter_t;

typedef struct rac_tool_definition {
    const char* name;
    const char* description;
    const rac_tool_parameter_t* parameters;
    size_t num_parameters;
    const char* category;
} rac_tool_definition_t;

typedef struct rac_tool_call {
    rac_bool_t has_tool_call;
    char* tool_name;
    char* arguments_json;
    char* clean_text;
    int64_t call_id;
    rac_tool_call_format_t format;
} rac_tool_call_t;

typedef struct rac_tool_call_validation {
    rac_bool_t is_valid;
    char* validation_errors_json;
    char* matched_tool_json;
    char* normalized_arguments_json;
    char* error_message;
    rac_result_t error_code;
} rac_tool_call_validation_t;

typedef struct rac_tool_calling_options {
    int32_t max_tool_calls;
    rac_bool_t auto_execute;
    float temperature;
    int32_t max_tokens;
    const char* system_prompt;
    rac_bool_t replace_system_prompt;
    rac_bool_t keep_tools_available;
    rac_tool_call_format_t format;
} rac_tool_calling_options_t;

#define RAC_TOOL_CALLING_OPTIONS_DEFAULT                            \
    {                                                               \
        5,                      /* max_tool_calls */                \
        1,                      /* auto_execute = true */           \
        0.7f,                   /* temperature */                   \
        1024,                   /* max_tokens */                    \
        RAC_NULL,               /* system_prompt */                 \
        0,                      /* replace_system_prompt = false */ \
        0,                      /* keep_tools_available = false */  \
        RAC_TOOL_FORMAT_DEFAULT /* format */                        \
    }

rac_result_t rac_tool_call_parse(const char* llm_output, rac_tool_call_t* out_result);
rac_result_t rac_tool_call_parse_with_format(const char* llm_output, rac_tool_call_format_t format,
                                             rac_tool_call_t* out_result);
rac_result_t rac_tool_call_validate(const rac_tool_call_t* call,
                                    const rac_tool_definition_t* definitions,
                                    size_t num_definitions,
                                    rac_tool_call_validation_t* out_validation);
rac_result_t rac_tool_call_validate_json(const rac_tool_call_t* call, const char* tools_json,
                                         rac_tool_call_validation_t* out_validation);
void rac_tool_call_validation_free(rac_tool_call_validation_t* validation);
void rac_tool_call_free(rac_tool_call_t* result);
const char* rac_tool_call_format_name(rac_tool_call_format_t format);
rac_tool_call_format_t rac_tool_call_detect_format(const char* llm_output);
rac_tool_call_format_t rac_tool_call_format_from_name(const char* name);
rac_result_t rac_tool_call_format_prompt(const rac_tool_definition_t* definitions,
                                         size_t num_definitions, char** out_prompt);
rac_result_t rac_tool_call_format_prompt_with_format(const rac_tool_definition_t* definitions,
                                                     size_t num_definitions,
                                                     rac_tool_call_format_t format,
                                                     char** out_prompt);
rac_result_t rac_tool_call_format_prompt_json(const char* tools_json, char** out_prompt);
rac_result_t rac_tool_call_format_prompt_json_with_format(const char* tools_json,
                                                          rac_tool_call_format_t format,
                                                          char** out_prompt);
rac_result_t rac_tool_call_format_prompt_json_with_format_name(const char* tools_json,
                                                               const char* format_name,
                                                               char** out_prompt);
rac_result_t rac_tool_call_build_initial_prompt(const char* user_prompt, const char* tools_json,
                                                const rac_tool_calling_options_t* options,
                                                char** out_prompt);
rac_result_t rac_tool_call_build_followup_prompt(const char* original_user_prompt,
                                                 const char* tools_prompt, const char* tool_name,
                                                 const char* tool_result_json,
                                                 rac_bool_t keep_tools_available,
                                                 char** out_prompt);
rac_result_t rac_tool_call_normalize_json(const char* json_str, char** out_normalized);
rac_result_t rac_tool_call_definitions_to_json(const rac_tool_definition_t* definitions,
                                               size_t num_definitions, char** out_json);
rac_result_t rac_tool_call_result_to_json(const char* tool_name, rac_bool_t success,
                                          const char* result_json, const char* error_message,
                                          char** out_json);

#ifdef __cplusplus
}
#endif

#endif  // RAC_TOOL_CALLING_INTERNAL_H
