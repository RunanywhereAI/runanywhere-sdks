/**
 * @file schema_to_json.cpp
 * @brief Implementation of rac_structured_output_schema_to_json_proto.
 *
 * Direct C++ port of Swift's RAJSONSchema.jsonSchemaString computed property
 * + JSONSchemaWriter (sdk/runanywhere-swift/Sources/RunAnywhere/Public/
 *  Extensions/LLM/StructuredOutputProto+Helpers.swift, lines 30-177).
 *
 * Two paths matching the Swift public API:
 *   1. Top-level raw_json short-circuit: when the input schema carries a
 *      non-empty raw_json (after whitespace trim), return that text as-is
 *      without canonicalization. Mirrors lines 32-34 of the Swift extension.
 *   2. Otherwise build a json dictionary via the writer and emit compact,
 *      key-sorted text. Mirrors lines 37-44 of the Swift extension and the
 *      JSONSchemaWriter helper at lines 47-177.
 *
 * This file is intentionally self-contained — it does NOT reuse the
 * pre-existing helpers in structured_output.cpp because that converter has a
 * lossy fast-path for nested object schemas (only carries properties /
 * required / additionalProperties). The Swift writer is the source of truth
 * and pulls every field from a nested object schema, so we replicate that
 * algorithm field-for-field here.
 *
 * Output canonicalization (path 2) matches Swift's
 * `JSONSerialization.data(withJSONObject:options:[.sortedKeys])`:
 *   - compact (no whitespace)
 *   - keys sorted lexicographically
 * nlohmann::json's default backing store is std::map, so dump() with no
 * indent produces the same compact, key-sorted text for object members.
 */

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

#include "rac/features/llm/rac_llm_schema_to_json.h"
#include "rac/foundation/rac_proto_buffer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "structured_output.pb.h"
#endif

#if defined(RAC_HAVE_PROTOBUF)
namespace {

using nlohmann::json;

const char* schema_type_name(::runanywhere::v1::JSONSchemaType type) {
    switch (type) {
        case ::runanywhere::v1::JSON_SCHEMA_TYPE_OBJECT:
            return "object";
        case ::runanywhere::v1::JSON_SCHEMA_TYPE_ARRAY:
            return "array";
        case ::runanywhere::v1::JSON_SCHEMA_TYPE_STRING:
            return "string";
        case ::runanywhere::v1::JSON_SCHEMA_TYPE_NUMBER:
            return "number";
        case ::runanywhere::v1::JSON_SCHEMA_TYPE_INTEGER:
            return "integer";
        case ::runanywhere::v1::JSON_SCHEMA_TYPE_BOOLEAN:
            return "boolean";
        case ::runanywhere::v1::JSON_SCHEMA_TYPE_NULL:
            return "null";
        case ::runanywhere::v1::JSON_SCHEMA_TYPE_UNSPECIFIED:
        default:
            return nullptr;
    }
}

json schema_to_json_object(const ::runanywhere::v1::JSONSchema& schema);

// Mirrors Swift JSONSchemaWriter.dictionary(from:) — accepts a raw JSON string
// and returns the parsed object as a dictionary, or nullopt if it does not
// decode to an object.
bool parse_raw_json_object(const std::string& raw, json* out_object) {
    if (raw.empty()) {
        return false;
    }
    json parsed = json::parse(raw, nullptr, false);
    if (parsed.is_discarded() || !parsed.is_object()) {
        return false;
    }
    *out_object = std::move(parsed);
    return true;
}

// Mirrors Swift JSONSchemaWriter.jsonValue(from:) — parses an arbitrary JSON
// scalar/array/object string. Returns the parsed value, or the raw string
// itself when parsing fails.
json parse_json_value_or_raw(const std::string& raw) {
    if (raw.empty()) {
        return json(raw);
    }
    json parsed = json::parse(raw, nullptr, false);
    if (parsed.is_discarded()) {
        return json(raw);
    }
    return parsed;
}

// Port of Swift JSONSchemaWriter.object(from property: RAJSONSchemaProperty).
// Mirrors lines 102-145 of StructuredOutputProto+Helpers.swift exactly.
json property_to_json_object(const ::runanywhere::v1::JSONSchemaProperty& property) {
    // Swift seeds the object from the nested object schema (full recursion);
    // C-side mirror must do the same to preserve nested-object metadata.
    json object = property.has_object_schema() ? schema_to_json_object(property.object_schema())
                                               : json::object();

    if (const char* type = schema_type_name(property.type())) {
        object["type"] = type;
    }
    if (property.has_description()) {
        object["description"] = property.description();
    }
    if (property.enum_values_size() > 0) {
        json arr = json::array();
        for (const auto& value : property.enum_values()) {
            arr.push_back(value);
        }
        object["enum"] = std::move(arr);
    }
    if (property.has_format()) {
        object["format"] = property.format();
    }
    if (property.has_items_schema()) {
        // Swift recurses through the schema-level writer for items_schema.
        object["items"] = schema_to_json_object(property.items_schema());
    }
    if (property.has_minimum()) {
        object["minimum"] = property.minimum();
    }
    if (property.has_maximum()) {
        object["maximum"] = property.maximum();
    }
    if (property.has_min_length()) {
        // Swift writes Int(property.minLength); int32 from proto coerces 1:1.
        object["minLength"] = static_cast<int>(property.min_length());
    }
    if (property.has_max_length()) {
        object["maxLength"] = static_cast<int>(property.max_length());
    }
    if (property.has_pattern()) {
        object["pattern"] = property.pattern();
    }
    if (property.has_min_items()) {
        object["minItems"] = static_cast<int>(property.min_items());
    }
    if (property.has_max_items()) {
        object["maxItems"] = static_cast<int>(property.max_items());
    }
    if (property.has_default_json()) {
        object["default"] = parse_json_value_or_raw(property.default_json());
    }
    return object;
}

// Port of Swift JSONSchemaWriter.object(from schema: RAJSONSchema).
// Mirrors lines 48-100 of StructuredOutputProto+Helpers.swift exactly.
json schema_to_json_object(const ::runanywhere::v1::JSONSchema& schema) {
    if (schema.has_raw_json()) {
        json raw_object;
        if (parse_raw_json_object(schema.raw_json(), &raw_object)) {
            return raw_object;
        }
        // Swift falls through to the structured branch when raw_json is empty
        // or fails to decode as a [String: Any].
    }

    json schema_object = json::object();
    if (const char* type = schema_type_name(schema.type())) {
        schema_object["type"] = type;
    }
    if (schema.properties_size() > 0) {
        json properties = json::object();
        for (const auto& entry : schema.properties()) {
            properties[entry.first] = property_to_json_object(entry.second);
        }
        schema_object["properties"] = std::move(properties);
    }
    if (schema.required_size() > 0) {
        json required = json::array();
        for (const auto& name : schema.required()) {
            required.push_back(name);
        }
        schema_object["required"] = std::move(required);
    }
    if (schema.has_items()) {
        schema_object["items"] = property_to_json_object(schema.items());
    }
    if (schema.has_additional_properties()) {
        schema_object["additionalProperties"] = schema.additional_properties();
    }
    if (schema.has_schema_uri()) {
        schema_object["$schema"] = schema.schema_uri();
    }
    if (schema.has_id_uri()) {
        schema_object["$id"] = schema.id_uri();
    }
    if (schema.has_title()) {
        schema_object["title"] = schema.title();
    }
    if (schema.has_description()) {
        schema_object["description"] = schema.description();
    }
    if (schema.definitions_size() > 0) {
        json definitions = json::object();
        for (const auto& entry : schema.definitions()) {
            definitions[entry.first] = schema_to_json_object(entry.second);
        }
        schema_object["definitions"] = std::move(definitions);
    }
    if (schema.has_ref()) {
        schema_object["$ref"] = schema.ref();
    }
    if (schema.all_of_size() > 0) {
        json arr = json::array();
        for (const auto& item : schema.all_of()) {
            arr.push_back(schema_to_json_object(item));
        }
        schema_object["allOf"] = std::move(arr);
    }
    if (schema.any_of_size() > 0) {
        json arr = json::array();
        for (const auto& item : schema.any_of()) {
            arr.push_back(schema_to_json_object(item));
        }
        schema_object["anyOf"] = std::move(arr);
    }
    if (schema.one_of_size() > 0) {
        json arr = json::array();
        for (const auto& item : schema.one_of()) {
            arr.push_back(schema_to_json_object(item));
        }
        schema_object["oneOf"] = std::move(arr);
    }
    if (schema.has_not_schema()) {
        schema_object["not"] = schema_to_json_object(schema.not_schema());
    }
    return schema_object;
}

}  // namespace
#endif  // RAC_HAVE_PROTOBUF

extern "C" rac_result_t
rac_structured_output_schema_to_json_proto(const uint8_t* in_RAJSONSchema_bytes, size_t in_size,
                                           rac_proto_buffer_t* out) {
    if (!out) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)in_RAJSONSchema_bytes;
    (void)in_size;
    return rac_proto_buffer_set_error(out, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    rac_result_t validation = rac_proto_bytes_validate(in_RAJSONSchema_bytes, in_size);
    if (validation != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_DECODING_ERROR,
                                          "JSONSchema bytes are invalid");
    }

    ::runanywhere::v1::JSONSchema schema;
    if (!schema.ParseFromArray(rac_proto_bytes_data_or_empty(in_RAJSONSchema_bytes, in_size),
                               static_cast<int>(in_size))) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse JSONSchema bytes");
    }

    // Path 1: Top-level raw_json short-circuit. Mirrors Swift jsonSchemaString
    // lines 32-34: if hasRawJson and trimmed is non-empty, return the raw
    // text verbatim (no canonicalization).
    if (schema.has_raw_json()) {
        const std::string& raw = schema.raw_json();
        const auto first = raw.find_first_not_of(" \t\n\r");
        if (first != std::string::npos) {
            return rac_proto_buffer_copy(reinterpret_cast<const uint8_t*>(raw.data()), raw.size(),
                                         out);
        }
    }

    // Path 2: Build dictionary and emit compact, key-sorted JSON text.
    // nlohmann::json's std::map backing yields lexicographic key ordering;
    // dump() with no indent produces the compact text Swift's [.sortedKeys]
    // option emits.
    const nlohmann::json schema_object = schema_to_json_object(schema);
    std::string text = schema_object.dump();
    return rac_proto_buffer_copy(reinterpret_cast<const uint8_t*>(text.data()), text.size(), out);
#endif
}
