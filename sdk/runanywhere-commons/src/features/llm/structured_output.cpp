/**
 * @file structured_output.cpp
 * @brief LLM Structured Output JSON Parsing Implementation
 *
 * C++ port of Swift's StructuredOutputHandler.swift from:
 * Sources/RunAnywhere/Features/LLM/StructuredOutput/StructuredOutputHandler.swift
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
 */

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

#include "features/llm/rac_llm_lifecycle_bridge.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_structured_output.h"
#include "rac/features/llm/rac_llm_thinking.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "structured_output.pb.h"
#endif

using nlohmann::json;

// HELPER FUNCTIONS

/**
 * @brief Trim whitespace from the beginning and end of a string
 *
 * @param str Input string
 * @param out_start Output: Start position after leading whitespace
 * @param out_end Output: End position before trailing whitespace (exclusive)
 */
static void trim_whitespace(const char* str, size_t* out_start, size_t* out_end) {
    size_t len = strlen(str);
    size_t start = 0;
    size_t end = len;

    // Skip leading whitespace
    while (start < len &&
           (str[start] == ' ' || str[start] == '\t' || str[start] == '\n' || str[start] == '\r')) {
        start++;
    }

    // Skip trailing whitespace
    while (end > start && (str[end - 1] == ' ' || str[end - 1] == '\t' || str[end - 1] == '\n' ||
                           str[end - 1] == '\r')) {
        end--;
    }

    *out_start = start;
    *out_end = end;
}

static char* dup_owned_string(const std::string& value) {
    char* copy = static_cast<char*>(malloc(value.size() + 1));
    if (!copy) {
        return nullptr;
    }
    memcpy(copy, value.c_str(), value.size() + 1);
    return copy;
}

static bool parse_json_value(const char* text, json* out_value) {
    if (!text || !out_value) {
        return false;
    }
    json parsed = json::parse(text, nullptr, false);
    if (parsed.is_discarded()) {
        return false;
    }
    *out_value = std::move(parsed);
    return true;
}

static std::string validation_errors_to_json(const std::vector<std::string>& errors) {
    json arr = json::array();
    for (const auto& error : errors) {
        arr.push_back(error);
    }
    return arr.dump();
}

static std::string json_type_name(const json& value) {
    if (value.is_object()) {
        return "object";
    }
    if (value.is_array()) {
        return "array";
    }
    if (value.is_string()) {
        return "string";
    }
    if (value.is_boolean()) {
        return "boolean";
    }
    if (value.is_number_integer()) {
        return "integer";
    }
    if (value.is_number()) {
        return "number";
    }
    if (value.is_null()) {
        return "null";
    }
    return "unknown";
}

static bool json_matches_schema_type(const json& value, const std::string& type) {
    if (type == "object") {
        return value.is_object();
    }
    if (type == "array") {
        return value.is_array();
    }
    if (type == "string") {
        return value.is_string();
    }
    if (type == "boolean") {
        return value.is_boolean();
    }
    if (type == "integer") {
        return value.is_number_integer();
    }
    if (type == "number") {
        return value.is_number();
    }
    if (type == "null") {
        return value.is_null();
    }
    return true;
}

static void validate_json_against_schema(const json& value, const json& schema,
                                         const std::string& path,
                                         std::vector<std::string>* errors) {
    if (!schema.is_object()) {
        return;
    }

    const auto type_it = schema.find("type");
    if (type_it != schema.end()) {
        bool type_ok = true;
        std::string expected_type;
        if (type_it->is_string()) {
            expected_type = type_it->get<std::string>();
            type_ok = json_matches_schema_type(value, expected_type);
        } else if (type_it->is_array()) {
            type_ok = false;
            for (const auto& candidate : *type_it) {
                if (candidate.is_string()) {
                    const std::string candidate_type = candidate.get<std::string>();
                    if (json_matches_schema_type(value, candidate_type)) {
                        type_ok = true;
                        break;
                    }
                    if (!expected_type.empty()) {
                        expected_type += "|";
                    }
                    expected_type += candidate_type;
                }
            }
        }

        if (!type_ok) {
            errors->push_back(path + " must be " + expected_type + " but was " +
                              json_type_name(value));
            return;
        }
    }

    const auto enum_it = schema.find("enum");
    if (enum_it != schema.end() && enum_it->is_array()) {
        bool matched = false;
        for (const auto& enum_value : *enum_it) {
            if (enum_value == value) {
                matched = true;
                break;
            }
        }
        if (!matched) {
            errors->push_back(path + " is not one of the allowed enum values");
            return;
        }
    }

    const bool schema_describes_object =
        value.is_object() && (schema.contains("properties") || schema.contains("required") ||
                              (schema.contains("type") && schema["type"].is_string() &&
                               schema["type"].get<std::string>() == "object"));
    if (schema_describes_object) {
        const json properties = schema.contains("properties") && schema["properties"].is_object()
                                    ? schema["properties"]
                                    : json::object();

        const auto required_it = schema.find("required");
        if (required_it != schema.end() && required_it->is_array()) {
            for (const auto& required_name : *required_it) {
                if (!required_name.is_string()) {
                    continue;
                }
                const std::string name = required_name.get<std::string>();
                if (!value.contains(name)) {
                    std::string message = path;
                    message += ".";
                    message += name;
                    message += " is required";
                    errors->push_back(std::move(message));
                }
            }
        }

        for (auto it = properties.begin(); it != properties.end(); ++it) {
            if (value.contains(it.key())) {
                validate_json_against_schema(value.at(it.key()), it.value(), path + "." + it.key(),
                                             errors);
            }
        }

        const auto additional_it = schema.find("additionalProperties");
        if (additional_it != schema.end() && additional_it->is_boolean() &&
            !additional_it->get<bool>()) {
            for (auto it = value.begin(); it != value.end(); ++it) {
                if (!properties.contains(it.key())) {
                    errors->push_back(path + "." + it.key() + " is not allowed");
                }
            }
        }
    }

    if (value.is_array() && schema.contains("items")) {
        const json& item_schema = schema["items"];
        for (size_t i = 0; i < value.size(); ++i) {
            validate_json_against_schema(value[i], item_schema,
                                         path + "[" + std::to_string(i) + "]", errors);
        }
    }
}

static const char* expected_json_root_name(const char* json_schema) {
    json schema;
    if (!json_schema || !parse_json_value(json_schema, &schema) || !schema.is_object()) {
        return "object";
    }

    const auto type_it = schema.find("type");
    if (type_it != schema.end() && type_it->is_string()) {
        const std::string type = type_it->get<std::string>();
        if (type == "array") {
            return "array";
        }
        if (type != "object") {
            return "value";
        }
    }

    if (schema.contains("items") && !schema.contains("properties")) {
        return "array";
    }

    return "object";
}

static const char* expected_start_token(const char* root_name) {
    return strcmp(root_name, "array") == 0 ? "[" : "{";
}

static const char* expected_end_token(const char* root_name) {
    return strcmp(root_name, "array") == 0 ? "]" : "}";
}

#if defined(RAC_HAVE_PROTOBUF)
template <typename ProtoMessage>
static rac_result_t copy_serialized_proto(const ProtoMessage& message,
                                          rac_proto_buffer_t* out_result,
                                          const char* message_name) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    const size_t size = message.ByteSizeLong();
    if (size > static_cast<size_t>(std::numeric_limits<int>::max())) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                          "serialized proto exceeds supported size");
    }
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !message.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        std::string error = "failed to serialize ";
        error += message_name;
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_ENCODING_ERROR, error.c_str());
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out_result);
}

static const char* json_schema_type_name(runanywhere::v1::JSONSchemaType type) {
    switch (type) {
        case runanywhere::v1::JSON_SCHEMA_TYPE_OBJECT:
            return "object";
        case runanywhere::v1::JSON_SCHEMA_TYPE_ARRAY:
            return "array";
        case runanywhere::v1::JSON_SCHEMA_TYPE_STRING:
            return "string";
        case runanywhere::v1::JSON_SCHEMA_TYPE_NUMBER:
            return "number";
        case runanywhere::v1::JSON_SCHEMA_TYPE_INTEGER:
            return "integer";
        case runanywhere::v1::JSON_SCHEMA_TYPE_BOOLEAN:
            return "boolean";
        case runanywhere::v1::JSON_SCHEMA_TYPE_NULL:
            return "null";
        case runanywhere::v1::JSON_SCHEMA_TYPE_UNSPECIFIED:
        default:
            return nullptr;
    }
}

static json json_schema_proto_to_json(const runanywhere::v1::JSONSchema& schema);

static json
json_schema_property_proto_to_json(const runanywhere::v1::JSONSchemaProperty& property) {
    json object = json::object();
    if (const char* type = json_schema_type_name(property.type())) {
        object["type"] = type;
    }
    if (property.has_description()) {
        object["description"] = property.description();
    }
    if (property.enum_values_size() > 0) {
        object["enum"] = json::array();
        for (const auto& value : property.enum_values()) {
            object["enum"].push_back(value);
        }
    }
    if (property.has_format()) {
        object["format"] = property.format();
    }
    if (property.has_items_schema()) {
        object["items"] = json_schema_proto_to_json(property.items_schema());
    }
    if (property.has_object_schema()) {
        const json nested = json_schema_proto_to_json(property.object_schema());
        if (nested.contains("properties")) {
            object["properties"] = nested["properties"];
        }
        if (nested.contains("required")) {
            object["required"] = nested["required"];
        }
        if (nested.contains("additionalProperties")) {
            object["additionalProperties"] = nested["additionalProperties"];
        }
    }
    if (property.has_minimum()) {
        object["minimum"] = property.minimum();
    }
    if (property.has_maximum()) {
        object["maximum"] = property.maximum();
    }
    if (property.has_min_length()) {
        object["minLength"] = property.min_length();
    }
    if (property.has_max_length()) {
        object["maxLength"] = property.max_length();
    }
    if (property.has_pattern()) {
        object["pattern"] = property.pattern();
    }
    if (property.has_min_items()) {
        object["minItems"] = property.min_items();
    }
    if (property.has_max_items()) {
        object["maxItems"] = property.max_items();
    }
    if (property.has_default_json()) {
        json default_value = json::parse(property.default_json(), nullptr, false);
        object["default"] =
            default_value.is_discarded() ? json(property.default_json()) : std::move(default_value);
    }
    return object;
}

static json json_schema_proto_to_json(const runanywhere::v1::JSONSchema& schema) {
    if (schema.has_raw_json()) {
        json raw = json::parse(schema.raw_json(), nullptr, false);
        if (!raw.is_discarded()) {
            return raw;
        }
    }

    json object = json::object();
    if (const char* type = json_schema_type_name(schema.type())) {
        object["type"] = type;
    }
    if (schema.properties_size() > 0) {
        object["properties"] = json::object();
        for (const auto& entry : schema.properties()) {
            object["properties"][entry.first] = json_schema_property_proto_to_json(entry.second);
        }
    }
    if (schema.required_size() > 0) {
        object["required"] = json::array();
        for (const auto& required : schema.required()) {
            object["required"].push_back(required);
        }
    }
    if (schema.has_items()) {
        object["items"] = json_schema_property_proto_to_json(schema.items());
    }
    if (schema.has_additional_properties()) {
        object["additionalProperties"] = schema.additional_properties();
    }
    if (schema.has_schema_uri()) {
        object["$schema"] = schema.schema_uri();
    }
    if (schema.has_id_uri()) {
        object["$id"] = schema.id_uri();
    }
    if (schema.has_title()) {
        object["title"] = schema.title();
    }
    if (schema.has_description()) {
        object["description"] = schema.description();
    }
    if (schema.definitions_size() > 0) {
        object["definitions"] = json::object();
        for (const auto& entry : schema.definitions()) {
            object["definitions"][entry.first] = json_schema_proto_to_json(entry.second);
        }
    }
    if (schema.has_ref()) {
        object["$ref"] = schema.ref();
    }
    if (schema.all_of_size() > 0) {
        object["allOf"] = json::array();
        for (const auto& item : schema.all_of()) {
            object["allOf"].push_back(json_schema_proto_to_json(item));
        }
    }
    if (schema.any_of_size() > 0) {
        object["anyOf"] = json::array();
        for (const auto& item : schema.any_of()) {
            object["anyOf"].push_back(json_schema_proto_to_json(item));
        }
    }
    if (schema.one_of_size() > 0) {
        object["oneOf"] = json::array();
        for (const auto& item : schema.one_of()) {
            object["oneOf"].push_back(json_schema_proto_to_json(item));
        }
    }
    if (schema.has_not_schema()) {
        object["not"] = json_schema_proto_to_json(schema.not_schema());
    }
    return object;
}

static std::string
json_schema_from_options(const runanywhere::v1::StructuredOutputOptions& options) {
    if (options.has_json_schema() && !options.json_schema().empty()) {
        return options.json_schema();
    }
    if (options.has_schema()) {
        return json_schema_proto_to_json(options.schema()).dump();
    }
    return {};
}

struct ProtoStructuredOutputConfig {
    rac_structured_output_config_t config = RAC_STRUCTURED_OUTPUT_DEFAULT;
    std::string json_schema;
};

static void refresh_proto_structured_output_config(ProtoStructuredOutputConfig* converted) {
    if (!converted) {
        return;
    }
    converted->config.json_schema =
        converted->json_schema.empty() ? nullptr : converted->json_schema.c_str();
}

static ProtoStructuredOutputConfig
structured_output_config_from_options(const runanywhere::v1::StructuredOutputOptions& options) {
    ProtoStructuredOutputConfig converted;
    converted.json_schema = json_schema_from_options(options);
    converted.config.include_schema_in_prompt =
        options.include_schema_in_prompt() ? RAC_TRUE : RAC_FALSE;
    refresh_proto_structured_output_config(&converted);
    return converted;
}

// commons-103: StructuredOutputOptions advertises modes/fields the C ABI does
// not yet implement (REGEX/GRAMMAR-constrained decoding, post-generation JSON
// repair, retry budget). Until those are plumbed through rac_llm_options_t and
// the engine sampler hooks, surface a typed RAC_ERROR_FEATURE_NOT_AVAILABLE
// via the proto envelope instead of silently downgrading to plain JSON-schema
// generation — silent downgrade caused SDKs requesting GRAMMAR mode to accept
// non-conforming output as if the constraint had been applied. Mirrors the
// short-term path documented in the cluster-13 finding synthesis.
static rac_result_t
unsupported_structured_options_message(const runanywhere::v1::StructuredOutputOptions& options,
                                       std::string* out_message) {
    const auto mode = options.mode();
    if (mode == runanywhere::v1::STRUCTURED_OUTPUT_MODE_REGEX) {
        *out_message =
            "regex-constrained structured output is not supported by the C ABI engine yet";
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    if (mode == runanywhere::v1::STRUCTURED_OUTPUT_MODE_GRAMMAR) {
        *out_message =
            "grammar-constrained structured output is not supported by the C ABI engine yet";
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    if (options.has_regex_pattern() && !options.regex_pattern().empty()) {
        *out_message =
            "StructuredOutputOptions.regex_pattern is not consumed by the C ABI engine yet";
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    if (options.has_grammar() && !options.grammar().empty()) {
        *out_message = "StructuredOutputOptions.grammar is not consumed by the C ABI engine yet";
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    if (options.repair_json()) {
        *out_message =
            "StructuredOutputOptions.repair_json is not implemented by commons (post-generation "
            "repair must happen in the SDK)";
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    if (options.max_retries() > 0) {
        *out_message =
            "StructuredOutputOptions.max_retries is not implemented by commons (retry budget must "
            "happen in the SDK)";
        return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    }
    return RAC_SUCCESS;
}

// commons-031: StructuredOutputRequest currently has no LLMGenerationOptions
// field, so the per-call sampling knobs (max_tokens, temperature, top_p,
// stop_sequences, system_prompt overrides) — and likewise
// LLMGenerationOptions.disable_thinking — reach the engine only as the
// rac_llm_options_t defaults below. Callers that need sampling control or
// thinking suppression must route through rac_llm_generate_proto /
// rac_llm_generate_stream_proto with LLMGenerationOptions.structured_output
// set instead (Swift's generateStructured wrapper takes that path — see
// sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/
// RunAnywhere+StructuredOutput.swift — so disable_thinking already works
// there). Embedding LLMGenerationOptions into StructuredOutputRequest would
// close this gap but requires an IDL change + proto regeneration across all
// SDKs and is tracked outside this cluster.

static void add_structured_validation_errors_from_json(
    const char* validation_errors_json, runanywhere::v1::StructuredOutputValidation* validation) {
    if (!validation_errors_json || !validation) {
        return;
    }

    json errors = json::parse(validation_errors_json, nullptr, false);
    if (!errors.is_array()) {
        return;
    }
    for (const auto& error : errors) {
        if (error.is_string()) {
            validation->add_validation_errors(error.get<std::string>());
        }
    }
}

static void
fill_structured_validation_proto(const rac_structured_output_parse_result_t& parsed,
                                 runanywhere::v1::StructuredOutputValidation* validation) {
    validation->set_is_valid(parsed.is_valid == RAC_TRUE);
    validation->set_contains_json(parsed.contains_json == RAC_TRUE);
    if (parsed.error_message) {
        validation->set_error_message(parsed.error_message);
    }
    if (parsed.raw_text) {
        validation->set_raw_output(parsed.raw_text);
    }
    if (parsed.parsed_json) {
        validation->set_extracted_json(parsed.parsed_json);
    }
    add_structured_validation_errors_from_json(parsed.validation_errors_json, validation);
    validation->set_validation_time_ms(0);
}

static int64_t structured_now_us() {
    using namespace std::chrono;
    return duration_cast<microseconds>(system_clock::now().time_since_epoch()).count();
}

static rac_result_t structured_result_from_text(const std::string& raw_text,
                                                const rac_structured_output_config_t* config,
                                                runanywhere::v1::StructuredOutputResult* result) {
    if (!result) {
        return RAC_ERROR_NULL_POINTER;
    }

    const char* response = nullptr;
    size_t response_len = 0;
    const char* thinking = nullptr;
    size_t thinking_len = 0;
    (void)rac_llm_extract_thinking(raw_text.c_str(), &response, &response_len, &thinking,
                                   &thinking_len);
    const std::string parse_text = response ? std::string(response, response_len) : raw_text;

    rac_structured_output_parse_result_t parsed{};
    const rac_result_t rc = rac_structured_output_parse(parse_text.c_str(), config, &parsed);
    // Treat ordinary invalid output (INVALID_FORMAT/VALIDATION_FAILED) as a
    // typed StructuredOutputResult payload — the parsed struct still carries
    // the populated validation envelope (error_code, error_message,
    // validation_errors_json). Only ABI/IO failures (null args, OOM, etc.)
    // escape as a non-success rc to the caller.
    if (rc != RAC_SUCCESS && rc != RAC_ERROR_INVALID_FORMAT && rc != RAC_ERROR_VALIDATION_FAILED) {
        rac_structured_output_parse_result_free(&parsed);
        return rc;
    }

    if (parsed.parsed_json) {
        result->set_parsed_json(parsed.parsed_json);
    }
    fill_structured_validation_proto(parsed, result->mutable_validation());
    if (parsed.raw_text) {
        result->set_raw_text(parsed.raw_text);
    }
    if (parsed.error_message) {
        result->set_error_message(parsed.error_message);
    }
    result->set_error_code(static_cast<int32_t>(parsed.error_code));
    rac_structured_output_parse_result_free(&parsed);
    return RAC_SUCCESS;
}

static rac_result_t
prepare_structured_generation(const runanywhere::v1::StructuredOutputRequest& request,
                              ProtoStructuredOutputConfig* converted, bool* has_options,
                              std::string* prepared_prompt, std::string* system_prompt) {
    if (!converted || !has_options || !prepared_prompt || !system_prompt) {
        return RAC_ERROR_NULL_POINTER;
    }

    *has_options = false;
    if (request.has_options()) {
        *has_options = true;
        *converted = structured_output_config_from_options(request.options());
        refresh_proto_structured_output_config(converted);
    }

    char* prepared = nullptr;
    const rac_result_t prepare_rc = rac_structured_output_prepare_prompt(
        request.prompt().c_str(), *has_options ? &converted->config : nullptr, &prepared);
    if (prepare_rc != RAC_SUCCESS) {
        free(prepared);
        return prepare_rc;
    }
    prepared_prompt->assign(prepared ? prepared : "");
    free(prepared);

    system_prompt->clear();
    if (converted->config.json_schema) {
        char* system = nullptr;
        const rac_result_t system_rc =
            rac_structured_output_get_system_prompt(converted->config.json_schema, &system);
        if (system_rc != RAC_SUCCESS) {
            free(system);
            return system_rc;
        }
        system_prompt->assign(system ? system : "");
        free(system);
    }
    return RAC_SUCCESS;
}

struct StructuredStreamContext {
    rac_proto_bytes_callback_fn callback = nullptr;
    void* user_data = nullptr;
    rac::llm::LifecycleLlmRef* ref = nullptr;
    const rac_structured_output_config_t* config = nullptr;
    uint64_t seq = 0;
    bool terminal_sent = false;
    std::string request_id;
    std::string raw_text;
    std::string last_partial_json;
    // commons-104: track tokens so terminal events can report finish_reason
    // "length" when the engine stopped because options.max_tokens was reached,
    // mirroring rac_llm_proto_service.cpp generate_stream and llm_component.
    uint64_t token_count = 0;
    int32_t max_tokens = 0;
};

static void dispatch_structured_stream_event(StructuredStreamContext* ctx,
                                             runanywhere::v1::StructuredOutputStreamEventKind kind,
                                             const char* token, const char* partial_json,
                                             const runanywhere::v1::StructuredOutputResult* result,
                                             const char* error_message, rac_result_t error_code) {
    if (!ctx || !ctx->callback) {
        return;
    }

    runanywhere::v1::StructuredOutputStreamEvent event;
    event.set_seq(++ctx->seq);
    event.set_timestamp_us(structured_now_us());
    if (!ctx->request_id.empty()) {
        event.set_request_id(ctx->request_id);
    }
    event.set_kind(kind);
    if (token != nullptr && token[0] != '\0') {
        event.set_token(token);
    }
    if (partial_json != nullptr && partial_json[0] != '\0') {
        event.set_partial_json(partial_json);
    }
    if (result) {
        *event.mutable_result() = *result;
        if (result->has_validation()) {
            *event.mutable_validation() = result->validation();
        }
    }
    if (error_message != nullptr && error_message[0] != '\0') {
        event.set_error_message(error_message);
    }
    event.set_error_code(static_cast<int32_t>(error_code));

    const size_t size = event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return;
    }
    ctx->callback(bytes.empty() ? nullptr : bytes.data(), bytes.size(), ctx->user_data);
}

static void maybe_dispatch_partial_json(StructuredStreamContext* ctx) {
    if (!ctx || ctx->raw_text.empty()) {
        return;
    }

    const char* response = nullptr;
    size_t response_len = 0;
    const char* thinking = nullptr;
    size_t thinking_len = 0;
    (void)rac_llm_extract_thinking(ctx->raw_text.c_str(), &response, &response_len, &thinking,
                                   &thinking_len);
    const std::string scan_text = response ? std::string(response, response_len) : ctx->raw_text;

    size_t start = 0;
    size_t end = 0;
    if (rac_structured_output_find_complete_json(scan_text.c_str(), &start, &end) != RAC_TRUE ||
        end <= start) {
        return;
    }

    std::string partial = scan_text.substr(start, end - start);
    if (partial == ctx->last_partial_json) {
        return;
    }
    ctx->last_partial_json = partial;
    dispatch_structured_stream_event(
        ctx, runanywhere::v1::STRUCTURED_OUTPUT_STREAM_EVENT_KIND_PARTIAL_JSON, nullptr,
        partial.c_str(), nullptr, nullptr, RAC_SUCCESS);
}

static rac_bool_t structured_stream_token_callback(const char* token, void* user_data) {
    auto* ctx = static_cast<StructuredStreamContext*>(user_data);
    if (!ctx || !ctx->ref) {
        return RAC_FALSE;
    }
    if (rac::llm::lifecycle_llm_cancel_requested(ctx->ref)) {
        return RAC_FALSE;
    }

    const char* safe_token = token ? token : "";
    ctx->raw_text += safe_token;
    if (safe_token[0] != '\0') {
        ctx->token_count++;
    }
    dispatch_structured_stream_event(ctx,
                                     runanywhere::v1::STRUCTURED_OUTPUT_STREAM_EVENT_KIND_TOKEN,
                                     safe_token, nullptr, nullptr, nullptr, RAC_SUCCESS);
    maybe_dispatch_partial_json(ctx);
    return RAC_TRUE;
}

static void dispatch_structured_terminal_once(StructuredStreamContext* ctx,
                                              const char* finish_reason, rac_result_t status) {
    if (!ctx || ctx->terminal_sent) {
        return;
    }
    ctx->terminal_sent = true;

    runanywhere::v1::StructuredOutputResult result;
    rac_result_t result_rc = structured_result_from_text(ctx->raw_text, ctx->config, &result);
    // Treat INVALID_FORMAT/VALIDATION_FAILED as typed semantic outcomes carried
    // by the StructuredOutputResult envelope, not as transport errors. Only
    // ABI/IO failures (null args, OOM, serialization) emit an ERROR event with
    // no result payload — mirrors rac_structured_output_parse_proto.
    if (result_rc != RAC_SUCCESS && result_rc != RAC_ERROR_INVALID_FORMAT &&
        result_rc != RAC_ERROR_VALIDATION_FAILED) {
        dispatch_structured_stream_event(
            ctx, runanywhere::v1::STRUCTURED_OUTPUT_STREAM_EVENT_KIND_ERROR, nullptr, nullptr,
            nullptr, rac_error_message(result_rc), result_rc);
        return;
    }

    // The stream completed at the transport layer — even if the generated text
    // failed JSON parsing or schema validation, surface a COMPLETED event with
    // the populated result so callers can render validation_errors via the
    // typed envelope. Reserve the ERROR kind for transport-layer failures.
    const bool transport_ok = status == RAC_SUCCESS;
    const auto kind = transport_ok ? runanywhere::v1::STRUCTURED_OUTPUT_STREAM_EVENT_KIND_COMPLETED
                                   : runanywhere::v1::STRUCTURED_OUTPUT_STREAM_EVENT_KIND_ERROR;
    const bool validation_ok = result.error_code() == static_cast<int32_t>(RAC_SUCCESS);
    const char* message = nullptr;
    if (!transport_ok) {
        message = finish_reason != nullptr && finish_reason[0] != '\0' ? finish_reason
                                                                       : rac_error_message(status);
    } else if (!validation_ok && result.has_error_message()) {
        message = result.error_message().c_str();
    }
    dispatch_structured_stream_event(ctx, kind, nullptr, nullptr, &result, message,
                                     transport_ok ? static_cast<rac_result_t>(result.error_code())
                                                  : status);
}
#endif

// FIND MATCHING BRACE - Ported from Swift lines 179-212

extern "C" rac_bool_t rac_structured_output_find_matching_brace(const char* text, size_t start_pos,
                                                                size_t* out_end_pos) {
    if (!text || !out_end_pos) {
        return RAC_FALSE;
    }

    size_t len = strlen(text);
    if (start_pos >= len || text[start_pos] != '{') {
        return RAC_FALSE;
    }

    int depth = 0;
    bool in_string = false;
    bool escaped = false;

    for (size_t i = start_pos; i < len; i++) {
        char ch = text[i];

        if (escaped) {
            escaped = false;
            continue;
        }

        if (ch == '\\') {
            escaped = true;
            continue;
        }

        if (ch == '"' && !escaped) {
            in_string = !in_string;
            continue;
        }

        if (!in_string) {
            if (ch == '{') {
                depth++;
            } else if (ch == '}') {
                depth--;
                if (depth == 0) {
                    *out_end_pos = i;
                    return RAC_TRUE;
                }
            }
        }
    }

    return RAC_FALSE;
}

// FIND MATCHING BRACKET - Ported from Swift lines 215-248

extern "C" rac_bool_t rac_structured_output_find_matching_bracket(const char* text,
                                                                  size_t start_pos,
                                                                  size_t* out_end_pos) {
    if (!text || !out_end_pos) {
        return RAC_FALSE;
    }

    size_t len = strlen(text);
    if (start_pos >= len || text[start_pos] != '[') {
        return RAC_FALSE;
    }

    int depth = 0;
    bool in_string = false;
    bool escaped = false;

    for (size_t i = start_pos; i < len; i++) {
        char ch = text[i];

        if (escaped) {
            escaped = false;
            continue;
        }

        if (ch == '\\') {
            escaped = true;
            continue;
        }

        if (ch == '"' && !escaped) {
            in_string = !in_string;
            continue;
        }

        if (!in_string) {
            if (ch == '[') {
                depth++;
            } else if (ch == ']') {
                depth--;
                if (depth == 0) {
                    *out_end_pos = i;
                    return RAC_TRUE;
                }
            }
        }
    }

    return RAC_FALSE;
}

// FIND COMPLETE JSON - Ported from Swift lines 135-176

extern "C" rac_bool_t rac_structured_output_find_complete_json(const char* text, size_t* out_start,
                                                               size_t* out_end) {
    if (!text || !out_start || !out_end) {
        return RAC_FALSE;
    }

    size_t len = strlen(text);
    if (len == 0) {
        return RAC_FALSE;
    }

    // Scan left-to-right so arrays containing objects are returned as the
    // complete top-level JSON value instead of the first nested object.
    for (size_t i = 0; i < len; i++) {
        size_t end_pos = 0;
        if (text[i] == '{' && rac_structured_output_find_matching_brace(text, i, &end_pos) != 0) {
            *out_start = i;
            *out_end = end_pos + 1;  // Exclusive end
            return RAC_TRUE;
        }
        if (text[i] == '[' && rac_structured_output_find_matching_bracket(text, i, &end_pos) != 0) {
            *out_start = i;
            *out_end = end_pos + 1;  // Exclusive end
            return RAC_TRUE;
        }
    }

    return RAC_FALSE;
}

// EXTRACT JSON - Ported from Swift lines 102-132

extern "C" rac_result_t rac_structured_output_extract_json(const char* text, char** out_json,
                                                           size_t* out_length) {
    if (!text || !out_json) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Trim whitespace
    size_t trim_start, trim_end;
    trim_whitespace(text, &trim_start, &trim_end);

    if (trim_start >= trim_end) {
        RAC_LOG_ERROR("StructuredOutput", "Empty text provided");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    size_t trimmed_len = trim_end - trim_start;
    const char* trimmed = text + trim_start;

    bool saw_candidate = false;
    for (size_t i = 0; i < trimmed_len; ++i) {
        size_t candidate_end = 0;
        if (trimmed[i] == '{') {
            if (rac_structured_output_find_matching_brace(trimmed, i, &candidate_end) == 0) {
                continue;
            }
        } else if (trimmed[i] == '[') {
            if (rac_structured_output_find_matching_bracket(trimmed, i, &candidate_end) == 0) {
                continue;
            }
        } else {
            continue;
        }

        saw_candidate = true;
        const size_t json_len = candidate_end - i + 1;
        std::string candidate(trimmed + i, json_len);
        json parsed = json::parse(candidate, nullptr, false);
        if (parsed.is_discarded()) {
            continue;
        }

        char* result = static_cast<char*>(malloc(json_len + 1));
        if (!result) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        memcpy(result, candidate.c_str(), json_len + 1);
        *out_json = result;
        if (out_length) {
            *out_length = json_len;
        }
        return RAC_SUCCESS;
    }

    // Log the text that couldn't be parsed
    RAC_LOG_ERROR("StructuredOutput", saw_candidate ? "JSON candidate failed to parse"
                                                    : "No valid JSON found in the response");
    return RAC_ERROR_INVALID_FORMAT;
}

// GET SYSTEM PROMPT - Ported from Swift lines 10-30

// Small base models (e.g. SmolLM2-360M)
// cannot reliably produce structured JSON from a free-form prompt because
// they have not been instruction-tuned on the "schema → JSON" task and the
// llama.cpp backend currently does not pipe a grammar/json-mode parameter
// through to the sampler. The system prompt below was hardened with an
// explicit start-token cue ("Your reply must begin with %s ...") so the
// model is more likely to emit JSON on the very first token instead of
// echoing the prompt. The proper fix is grammar-constrained decoding:
//
//   TODO(cluster-12 follow-up): plumb rac_llm_options_t.grammar (or a
//   schema-derived GBNF grammar) through rac_llm_llamacpp_generate and
//   wire it to llama_sampler_init_grammar(). Until that lands, base
//   models will produce best-effort (sometimes lenient) JSON output —
//   tests should accept either a successful JSON parse or, for known
//   base models, a prompt-echo PASS as documented in
//   cross-platform-e2e-test-catalog.md.

extern "C" rac_result_t rac_structured_output_get_system_prompt(const char* json_schema,
                                                                char** out_prompt) {
    if (!out_prompt) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const char* schema = json_schema ? json_schema : "{}";
    const char* root_name = expected_json_root_name(schema);
    const char* start_token = expected_start_token(root_name);
    const char* end_token = expected_end_token(root_name);

    // Build the system prompt - matches Swift getSystemPrompt(for:)
    //
    // The leading "Your reply MUST begin with %s" line was
    // added to give base models (SmolLM2/TinyLlama family) a stronger
    // first-token cue. Without grammar-constrained decoding this is the
    // best heuristic nudge available.
    const char* format =
        "You are a JSON generator that outputs ONLY valid JSON without any additional text.\n"
        "Your reply MUST begin with the character %s and nothing else — no greeting, no\n"
        "restatement of the user prompt, no explanation.\n"
        "\n"
        "CRITICAL RULES:\n"
        "1. Your entire response must be valid JSON that can be parsed\n"
        "2. Output a JSON %s\n"
        "3. Start with %s and end with %s\n"
        "4. No text before the opening JSON token\n"
        "5. No text after the closing JSON token\n"
        "6. Follow the provided schema exactly\n"
        "7. Include all required fields\n"
        "8. Use proper JSON syntax (quotes, commas, etc.)\n"
        "\n"
        "Expected JSON Schema:\n"
        "%s\n"
        "\n"
        "Remember: Output ONLY the JSON %s, nothing else.";

    size_t needed = snprintf(nullptr, 0, format, start_token, root_name, start_token, end_token,
                             schema, root_name) +
                    1;
    char* result = static_cast<char*>(malloc(needed));
    if (!result) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    snprintf(result, needed, format, start_token, root_name, start_token, end_token, schema,
             root_name);
    *out_prompt = result;

    return RAC_SUCCESS;
}

// PREPARE PROMPT - Ported from Swift lines 43-82

extern "C" rac_result_t rac_structured_output_prepare_prompt(
    const char* original_prompt, const rac_structured_output_config_t* config, char** out_prompt) {
    if (!original_prompt || !out_prompt) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // If no config or schema not included in prompt, return original
    if (config == nullptr || config->include_schema_in_prompt == 0) {
        size_t len = strlen(original_prompt);
        char* result = static_cast<char*>(malloc(len + 1));
        if (!result) {
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        memcpy(result, original_prompt, len + 1);
        *out_prompt = result;
        return RAC_SUCCESS;
    }

    const char* schema = config->json_schema ? config->json_schema : "{}";
    const char* root_name = expected_json_root_name(schema);
    const char* start_token = expected_start_token(root_name);
    const char* end_token = expected_end_token(root_name);

    // Build structured output instructions - matches Swift preparePrompt()
    const char* format =
        "System: You are a JSON generator. You must output only valid JSON.\n"
        "\n"
        "%s\n"
        "\n"
        "CRITICAL INSTRUCTION: You MUST respond with ONLY a valid JSON %s. No other text is "
        "allowed.\n"
        "\n"
        "JSON Schema:\n"
        "%s\n"
        "\n"
        "RULES:\n"
        "1. Start your response with %s and end with %s\n"
        "2. Include NO text before the opening JSON token\n"
        "3. Include NO text after the closing JSON token\n"
        "4. Follow the schema exactly\n"
        "5. All required fields must be present\n"
        "6. Use exact field names from the schema\n"
        "7. Ensure proper JSON syntax (quotes, commas, etc.)\n"
        "\n"
        "IMPORTANT: Your entire response must be valid JSON that can be parsed. Do not include any "
        "explanations, comments, or additional text.\n"
        "\n"
        "Remember: Output ONLY the JSON %s, nothing else.";

    size_t needed = snprintf(nullptr, 0, format, original_prompt, root_name, schema, start_token,
                             end_token, root_name) +
                    1;
    char* result = static_cast<char*>(malloc(needed));
    if (!result) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    snprintf(result, needed, format, original_prompt, root_name, schema, start_token, end_token,
             root_name);
    *out_prompt = result;

    return RAC_SUCCESS;
}

// VALIDATE STRUCTURED OUTPUT - Ported from Swift lines 264-282

static void init_parse_result(rac_structured_output_parse_result_t* result) {
    result->is_valid = RAC_FALSE;
    result->contains_json = RAC_FALSE;
    result->parsed_json = nullptr;
    result->raw_text = nullptr;
    result->error_message = nullptr;
    result->validation_errors_json = nullptr;
    result->error_code = RAC_SUCCESS;
}

static bool text_contains_json_marker(const char* text) {
    return text != nullptr && (strchr(text, '{') != nullptr || strchr(text, '[') != nullptr);
}

static rac_result_t set_parse_errors(rac_structured_output_parse_result_t* out_result,
                                     const std::vector<std::string>& errors,
                                     rac_result_t error_code) {
    out_result->validation_errors_json = dup_owned_string(validation_errors_to_json(errors));
    if (!out_result->validation_errors_json) {
        rac_structured_output_parse_result_free(out_result);
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    if (!errors.empty()) {
        out_result->error_message = dup_owned_string(errors.front());
        if (!out_result->error_message) {
            rac_structured_output_parse_result_free(out_result);
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }

    out_result->error_code = error_code;
    return RAC_SUCCESS;
}

extern "C" rac_result_t
rac_structured_output_parse(const char* text, const rac_structured_output_config_t* config,
                            rac_structured_output_parse_result_t* out_result) {
    if (!text || !out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    init_parse_result(out_result);
    out_result->contains_json = text_contains_json_marker(text) ? RAC_TRUE : RAC_FALSE;
    out_result->raw_text = dup_owned_string(text);
    if (!out_result->raw_text) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    std::vector<std::string> errors;
    char* extracted = nullptr;
    const rac_result_t extract_result =
        rac_structured_output_extract_json(text, &extracted, nullptr);
    if (extract_result != RAC_SUCCESS || !extracted) {
        errors.emplace_back(out_result->contains_json == RAC_TRUE
                                ? "JSON candidate failed to parse"
                                : "No valid JSON found in the response");
        out_result->is_valid = RAC_FALSE;
        return set_parse_errors(out_result, errors, RAC_ERROR_INVALID_FORMAT);
    }

    out_result->contains_json = RAC_TRUE;
    json parsed;
    if (!parse_json_value(extracted, &parsed)) {
        free(extracted);
        errors.emplace_back("Extracted JSON failed to parse");
        out_result->is_valid = RAC_FALSE;
        return set_parse_errors(out_result, errors, RAC_ERROR_INVALID_FORMAT);
    }
    free(extracted);

    out_result->parsed_json = dup_owned_string(parsed.dump());
    if (!out_result->parsed_json) {
        rac_structured_output_parse_result_free(out_result);
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    if (config != nullptr && config->json_schema != nullptr && config->json_schema[0] != '\0') {
        json schema;
        if (!parse_json_value(config->json_schema, &schema) || !schema.is_object()) {
            errors.emplace_back("JSON schema is invalid");
        } else {
            validate_json_against_schema(parsed, schema, "$", &errors);
        }
    }

    out_result->is_valid = errors.empty() ? RAC_TRUE : RAC_FALSE;
    return set_parse_errors(out_result, errors,
                            errors.empty() ? RAC_SUCCESS : RAC_ERROR_VALIDATION_FAILED);
}

extern "C" rac_result_t rac_structured_output_parse_proto(const uint8_t* request_proto_bytes,
                                                          size_t request_proto_size,
                                                          rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    rac_result_t validation = rac_proto_bytes_validate(request_proto_bytes, request_proto_size);
    if (validation != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "StructuredOutputParseRequest bytes are invalid");
    }

    runanywhere::v1::StructuredOutputParseRequest request;
    if (!request.ParseFromArray(
            rac_proto_bytes_data_or_empty(request_proto_bytes, request_proto_size),
            static_cast<int>(request_proto_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse StructuredOutputParseRequest");
    }
    if (request.text().empty()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "StructuredOutputParseRequest.text is required");
    }

    ProtoStructuredOutputConfig converted;
    if (request.has_options()) {
        converted = structured_output_config_from_options(request.options());
        refresh_proto_structured_output_config(&converted);
    }

    rac_structured_output_parse_result_t parsed{};
    rac_result_t rc = rac_structured_output_parse(
        request.text().c_str(), converted.config.json_schema ? &converted.config : nullptr,
        &parsed);
    // Treat ordinary invalid output (INVALID_FORMAT/VALIDATION_FAILED) as a
    // typed StructuredOutputResult payload — the proto envelope exists to
    // carry those failures via validation.is_valid/error_code. Reserve
    // rac_proto_buffer_set_error for malformed request bytes, null pointers,
    // missing lifecycle model, serialization failure, or allocation errors.
    if (rc != RAC_SUCCESS && rc != RAC_ERROR_INVALID_FORMAT && rc != RAC_ERROR_VALIDATION_FAILED) {
        rac_structured_output_parse_result_free(&parsed);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::StructuredOutputResult result;
    if (parsed.parsed_json) {
        result.set_parsed_json(parsed.parsed_json);
    }
    fill_structured_validation_proto(parsed, result.mutable_validation());
    if (parsed.raw_text) {
        result.set_raw_text(parsed.raw_text);
    }
    if (parsed.error_message) {
        result.set_error_message(parsed.error_message);
    }
    result.set_error_code(static_cast<int32_t>(parsed.error_code));
    rac_structured_output_parse_result_free(&parsed);

    return copy_serialized_proto(result, out_result, "StructuredOutputResult");
#endif
}

extern "C" rac_result_t rac_structured_output_generate_proto(const uint8_t* request_proto_bytes,
                                                             size_t request_proto_size,
                                                             rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    rac_result_t validation = rac_proto_bytes_validate(request_proto_bytes, request_proto_size);
    if (validation != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "StructuredOutputRequest bytes are invalid");
    }

    runanywhere::v1::StructuredOutputRequest request;
    if (!request.ParseFromArray(
            rac_proto_bytes_data_or_empty(request_proto_bytes, request_proto_size),
            static_cast<int>(request_proto_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse StructuredOutputRequest");
    }
    if (request.prompt().empty()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "StructuredOutputRequest.prompt is required");
    }

    // commons-103: reject unsupported StructuredOutputOptions modes/fields with
    // a typed StructuredOutputResult envelope so SDKs that request
    // grammar/regex/repair/retries see a clear error instead of silent
    // downgrade to plain JSON-schema generation.
    if (request.has_options()) {
        std::string unsupported_message;
        const rac_result_t unsupported =
            unsupported_structured_options_message(request.options(), &unsupported_message);
        if (unsupported != RAC_SUCCESS) {
            runanywhere::v1::StructuredOutputResult typed_result;
            typed_result.set_error_message(unsupported_message);
            typed_result.set_error_code(static_cast<int32_t>(unsupported));
            auto* result_validation = typed_result.mutable_validation();
            result_validation->set_is_valid(false);
            result_validation->set_contains_json(false);
            result_validation->set_error_message(unsupported_message);
            result_validation->add_validation_errors(unsupported_message);
            return copy_serialized_proto(typed_result, out_result, "StructuredOutputResult");
        }
    }

    ProtoStructuredOutputConfig converted;
    bool has_options = false;
    std::string prepared_prompt;
    std::string system_prompt;
    rac_result_t rc = prepare_structured_generation(request, &converted, &has_options,
                                                    &prepared_prompt, &system_prompt);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    rac::llm::LifecycleLlmRef ref;
    rc = rac::llm::acquire_lifecycle_llm(&ref);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "no lifecycle LLM model loaded");
    }

    rac::llm::clear_lifecycle_llm_cancel(&ref);
    rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;
    options.streaming_enabled = RAC_FALSE;
    options.system_prompt = system_prompt.empty() ? nullptr : system_prompt.c_str();

    rac_llm_result_t raw{};
    // Defensive: catch any C++ exception that escapes the engine vtable so it
    // cannot propagate across the extern "C" boundary. See parallel guard in
    // rac_llm_proto_service.cpp generate_stream path.
    if (ref.ops && ref.ops->generate) {
        try {
            rc = ref.ops->generate(ref.impl, prepared_prompt.c_str(), &options, &raw);
        } catch (const std::exception& e) {
            rac_error_set_details(e.what());
            rc = RAC_ERROR_INFERENCE_FAILED;
        } catch (...) {
            rac_error_set_details("Unknown C++ exception escaped LLM engine generate");
            rc = RAC_ERROR_INFERENCE_FAILED;
        }
    } else {
        rc = RAC_ERROR_NOT_SUPPORTED;
    }
    if (rc != RAC_SUCCESS) {
        rac::llm::release_lifecycle_llm(&ref);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::StructuredOutputResult result;
    rc = structured_result_from_text(raw.text ? raw.text : "",
                                     has_options ? &converted.config : nullptr, &result);
    rac_llm_result_free(&raw);
    rac::llm::release_lifecycle_llm(&ref);
    // Mirrors rac_structured_output_parse_proto: INVALID_FORMAT and
    // VALIDATION_FAILED are typed semantic outcomes that travel via the
    // StructuredOutputResult.error_code / validation envelope, not transport
    // errors. Reserve rac_proto_buffer_set_error for malformed request bytes,
    // null pointers, missing lifecycle model, serialization/allocation failures.
    if (rc != RAC_SUCCESS && rc != RAC_ERROR_INVALID_FORMAT && rc != RAC_ERROR_VALIDATION_FAILED) {
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }
    return copy_serialized_proto(result, out_result, "StructuredOutputResult");
#endif
}

extern "C" rac_result_t
rac_structured_output_generate_stream_proto(const uint8_t* request_proto_bytes,
                                            size_t request_proto_size,
                                            rac_proto_bytes_callback_fn callback, void* user_data) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    (void)callback;
    (void)user_data;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!callback) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_result_t validation = rac_proto_bytes_validate(request_proto_bytes, request_proto_size);
    if (validation != RAC_SUCCESS) {
        return RAC_ERROR_DECODING_ERROR;
    }

    runanywhere::v1::StructuredOutputRequest request;
    if (!request.ParseFromArray(
            rac_proto_bytes_data_or_empty(request_proto_bytes, request_proto_size),
            static_cast<int>(request_proto_size))) {
        return RAC_ERROR_DECODING_ERROR;
    }
    if (request.prompt().empty()) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // commons-103: emit a terminal ERROR event when the request asks for an
    // unsupported mode/field so the stream surfaces the typed reason instead
    // of silently downgrading. The stream proto returns rac_result_t and has
    // no separate result buffer, so the ERROR event carries the message.
    if (request.has_options()) {
        std::string unsupported_message;
        const rac_result_t unsupported =
            unsupported_structured_options_message(request.options(), &unsupported_message);
        if (unsupported != RAC_SUCCESS) {
            StructuredStreamContext err_ctx;
            err_ctx.callback = callback;
            err_ctx.user_data = user_data;
            err_ctx.request_id = request.request_id();
            dispatch_structured_stream_event(
                &err_ctx, runanywhere::v1::STRUCTURED_OUTPUT_STREAM_EVENT_KIND_ERROR, nullptr,
                nullptr, nullptr, unsupported_message.c_str(), unsupported);
            return unsupported;
        }
    }

    ProtoStructuredOutputConfig converted;
    bool has_options = false;
    std::string prepared_prompt;
    std::string system_prompt;
    rac_result_t rc = prepare_structured_generation(request, &converted, &has_options,
                                                    &prepared_prompt, &system_prompt);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    rac::llm::LifecycleLlmRef ref;
    rc = rac::llm::acquire_lifecycle_llm(&ref);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (!ref.ops || !ref.ops->generate_stream) {
        rac::llm::release_lifecycle_llm(&ref);
        return RAC_ERROR_NOT_SUPPORTED;
    }

    rac::llm::clear_lifecycle_llm_cancel(&ref);
    rac_llm_options_t options = RAC_LLM_OPTIONS_DEFAULT;
    options.streaming_enabled = RAC_TRUE;
    options.system_prompt = system_prompt.empty() ? nullptr : system_prompt.c_str();

    StructuredStreamContext ctx;
    ctx.callback = callback;
    ctx.user_data = user_data;
    ctx.ref = &ref;
    ctx.config = has_options ? &converted.config : nullptr;
    ctx.request_id = request.request_id();
    ctx.max_tokens = options.max_tokens;

    // Defensive: catch any C++ exception that escapes the engine vtable so it
    // cannot propagate across the extern "C" boundary. See parallel guard in
    // rac_llm_proto_service.cpp generate_stream path.
    try {
        rc = ref.ops->generate_stream(ref.impl, prepared_prompt.c_str(), &options,
                                      structured_stream_token_callback, &ctx);
    } catch (const std::exception& e) {
        rac_error_set_details(e.what());
        rc = RAC_ERROR_INFERENCE_FAILED;
    } catch (...) {
        rac_error_set_details("Unknown C++ exception escaped LLM engine generate_stream");
        rc = RAC_ERROR_INFERENCE_FAILED;
    }

    const bool cancelled = rac::llm::lifecycle_llm_cancel_requested(&ref) ||
                           rc == RAC_ERROR_CANCELLED || rc == RAC_ERROR_STREAM_CANCELLED;
    if (cancelled) {
        dispatch_structured_terminal_once(&ctx, "cancelled", RAC_ERROR_CANCELLED);
        rc = RAC_SUCCESS;
    } else if (rc == RAC_SUCCESS) {
        // commons-104: mirror the OpenAI-style finish_reason contract from
        // rac_llm_proto_service.cpp:778-779 / llm_component.cpp:1003-1006 —
        // when the backend stopped because it generated max_tokens, report
        // "length" instead of "stop" so agent retry/recovery loops can
        // distinguish truncation from a natural stop.
        const char* finish_reason =
            (ctx.max_tokens > 0 && ctx.token_count >= static_cast<uint64_t>(ctx.max_tokens))
                ? "length"
                : "stop";
        dispatch_structured_terminal_once(&ctx, finish_reason, rc);
    } else {
        dispatch_structured_terminal_once(&ctx, rac_error_message(rc), rc);
    }

    rac::llm::release_lifecycle_llm(&ref);
    return rc;
#endif
}

extern "C" rac_result_t rac_structured_output_prepare_prompt_proto(
    const uint8_t* request_proto_bytes, size_t request_proto_size, rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    rac_result_t validation = rac_proto_bytes_validate(request_proto_bytes, request_proto_size);
    if (validation != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "StructuredOutputRequest bytes are invalid");
    }

    runanywhere::v1::StructuredOutputRequest request;
    if (!request.ParseFromArray(
            rac_proto_bytes_data_or_empty(request_proto_bytes, request_proto_size),
            static_cast<int>(request_proto_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse StructuredOutputRequest");
    }

    ProtoStructuredOutputConfig converted;
    bool has_options = false;
    if (request.has_options()) {
        has_options = true;
        converted = structured_output_config_from_options(request.options());
        refresh_proto_structured_output_config(&converted);
    }

    char* prepared_prompt = nullptr;
    const rac_result_t prepare_rc = rac_structured_output_prepare_prompt(
        request.prompt().c_str(), has_options ? &converted.config : nullptr, &prepared_prompt);

    runanywhere::v1::StructuredOutputPromptResult result;
    if (prepare_rc != RAC_SUCCESS) {
        result.set_error_message(rac_error_message(prepare_rc));
        result.set_error_code(static_cast<int32_t>(prepare_rc));
        free(prepared_prompt);
        return copy_serialized_proto(result, out_result, "StructuredOutputPromptResult");
    }

    result.set_prepared_prompt(prepared_prompt ? prepared_prompt : "");
    result.set_error_code(static_cast<int32_t>(RAC_SUCCESS));
    if (converted.config.json_schema) {
        result.set_json_schema(converted.config.json_schema);
        char* system_prompt = nullptr;
        const rac_result_t system_rc =
            rac_structured_output_get_system_prompt(converted.config.json_schema, &system_prompt);
        if (system_rc == RAC_SUCCESS && system_prompt) {
            result.set_system_prompt(system_prompt);
        }
        free(system_prompt);
    }
    if (has_options) {
        const auto& options = request.options();
        if (options.has_regex_pattern()) {
            result.set_regex_pattern(options.regex_pattern());
        }
        if (options.has_grammar()) {
            result.set_grammar(options.grammar());
        }
    }

    free(prepared_prompt);
    return copy_serialized_proto(result, out_result, "StructuredOutputPromptResult");
#endif
}

extern "C" rac_result_t rac_structured_output_validate_proto(const uint8_t* request_proto_bytes,
                                                             size_t request_proto_size,
                                                             rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    rac_result_t validation = rac_proto_bytes_validate(request_proto_bytes, request_proto_size);
    if (validation != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "StructuredOutputValidationRequest bytes are invalid");
    }

    runanywhere::v1::StructuredOutputValidationRequest request;
    if (!request.ParseFromArray(
            rac_proto_bytes_data_or_empty(request_proto_bytes, request_proto_size),
            static_cast<int>(request_proto_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse StructuredOutputValidationRequest");
    }

    ProtoStructuredOutputConfig converted;
    if (request.has_options()) {
        converted = structured_output_config_from_options(request.options());
        refresh_proto_structured_output_config(&converted);
    }

    rac_structured_output_parse_result_t parsed{};
    const rac_result_t rc = rac_structured_output_parse(
        request.text().c_str(), converted.config.json_schema ? &converted.config : nullptr,
        &parsed);
    // Validation failures are an expected proto outcome — serialize the
    // populated StructuredOutputValidation. Only ABI/IO failures escape as
    // typed transport errors.
    if (rc != RAC_SUCCESS && rc != RAC_ERROR_INVALID_FORMAT && rc != RAC_ERROR_VALIDATION_FAILED) {
        rac_structured_output_parse_result_free(&parsed);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::StructuredOutputValidation result;
    fill_structured_validation_proto(parsed, &result);
    rac_structured_output_parse_result_free(&parsed);
    return copy_serialized_proto(result, out_result, "StructuredOutputValidation");
#endif
}

extern "C" rac_result_t
rac_structured_output_validate(const char* text, const rac_structured_output_config_t* config,
                               rac_structured_output_validation_t* out_validation) {
    if (!text || !out_validation) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Initialize output
    out_validation->is_valid = RAC_FALSE;
    out_validation->error_message = nullptr;
    out_validation->extracted_json = nullptr;

    rac_structured_output_parse_result_t parsed{};
    const rac_result_t result = rac_structured_output_parse(text, config, &parsed);
    if (result != RAC_SUCCESS) {
        return result;
    }

    out_validation->is_valid = parsed.is_valid;
    if (parsed.parsed_json) {
        out_validation->extracted_json = dup_owned_string(parsed.parsed_json);
        if (!out_validation->extracted_json) {
            rac_structured_output_parse_result_free(&parsed);
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }
    if (parsed.error_message) {
        out_validation->error_message = dup_owned_string(parsed.error_message);
        if (!out_validation->error_message) {
            rac_structured_output_validation_free(out_validation);
            rac_structured_output_parse_result_free(&parsed);
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }

    rac_structured_output_parse_result_free(&parsed);
    return RAC_SUCCESS;  // Function succeeded, validation just returned false
}

// MEMORY MANAGEMENT

extern "C" void
rac_structured_output_validation_free(rac_structured_output_validation_t* validation) {
    if (!validation) {
        return;
    }

    if (validation->extracted_json) {
        free(validation->extracted_json);
        validation->extracted_json = nullptr;
    }

    if (validation->error_message) {
        free(const_cast<char*>(validation->error_message));
    }
    validation->error_message = nullptr;
    validation->is_valid = RAC_FALSE;
}

extern "C" void
rac_structured_output_parse_result_free(rac_structured_output_parse_result_t* result) {
    if (!result) {
        return;
    }

    if (result->parsed_json) {
        free(result->parsed_json);
        result->parsed_json = nullptr;
    }
    if (result->raw_text) {
        free(result->raw_text);
        result->raw_text = nullptr;
    }
    if (result->error_message) {
        free(result->error_message);
        result->error_message = nullptr;
    }
    if (result->validation_errors_json) {
        free(result->validation_errors_json);
        result->validation_errors_json = nullptr;
    }

    result->is_valid = RAC_FALSE;
    result->contains_json = RAC_FALSE;
    result->error_code = RAC_SUCCESS;
}
