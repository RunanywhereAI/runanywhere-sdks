/**
 * @file rac_tool_value_json.cpp
 * @brief ToolValue <-> JSON proto-byte ABI (G3).
 *
 * Replaces the per-SDK hand-written walk over the ToolValue oneof:
 *   - Swift   ToolCallingTypes.swift   jsonObject / fromJSONObject (~80 LOC)
 *   - Kotlin  ToolValueJson.kt          toJsonElement / fromJsonElement
 *   - Dart    tool_value_json.dart      toJsonValue / fromJsonValue
 *   - RN      ToolValueJSON.ts          toJSON / fromJSON
 *   - Web     toolValueJson.ts          toJSON / fromJSON
 *
 * SINGLE SOURCE OF TRUTH for ToolValue <-> JSON canonicalization.
 */

#include <cstdint>
#include <limits>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_tool_calling.h"
#include "rac/foundation/rac_proto_buffer.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "tool_calling.pb.h"
#endif

using nlohmann::json;

#if defined(RAC_HAVE_PROTOBUF)
namespace {

// Forward decls for the recursive walk.
json tool_value_proto_to_json(const runanywhere::v1::ToolValue& value);
void json_to_tool_value_proto(const json& j, runanywhere::v1::ToolValue* out);

json tool_value_proto_to_json(const runanywhere::v1::ToolValue& value) {
    using ToolValue = runanywhere::v1::ToolValue;
    switch (value.kind_case()) {
        case ToolValue::kStringValue:
            return json(value.string_value());
        case ToolValue::kNumberValue:
            return json(value.number_value());
        case ToolValue::kBoolValue:
            return json(value.bool_value());
        case ToolValue::kArrayValue: {
            json arr = json::array();
            for (const auto& item : value.array_value().values()) {
                arr.push_back(tool_value_proto_to_json(item));
            }
            return arr;
        }
        case ToolValue::kObjectValue: {
            json obj = json::object();
            for (const auto& entry : value.object_value().fields()) {
                obj[entry.first] = tool_value_proto_to_json(entry.second);
            }
            return obj;
        }
        case ToolValue::kNullValue:
        case ToolValue::KIND_NOT_SET:
        default:
            return json(nullptr);
    }
}

void json_to_tool_value_proto(const json& j, runanywhere::v1::ToolValue* out) {
    if (!out) {
        return;
    }
    out->Clear();
    if (j.is_null()) {
        out->set_null_value(true);
    } else if (j.is_boolean()) {
        out->set_bool_value(j.get<bool>());
    } else if (j.is_number()) {
        // Lossless for floats; ints widen to double, mirroring the Swift
        // hand-written bridge which collapsed integers via NSNumber.doubleValue.
        out->set_number_value(j.get<double>());
    } else if (j.is_string()) {
        out->set_string_value(j.get<std::string>());
    } else if (j.is_array()) {
        auto* arr = out->mutable_array_value();
        for (const auto& item : j) {
            json_to_tool_value_proto(item, arr->add_values());
        }
    } else if (j.is_object()) {
        auto* obj = out->mutable_object_value();
        auto& fields = *obj->mutable_fields();
        for (auto it = j.begin(); it != j.end(); ++it) {
            json_to_tool_value_proto(it.value(), &fields[it.key()]);
        }
    } else {
        // discarded / binary — fall back to JSON null.
        out->set_null_value(true);
    }
}

template <typename ProtoMessage>
rac_result_t serialize_to_buffer(const ProtoMessage& message, rac_proto_buffer_t* out,
                                 const char* message_name) {
    const size_t size = message.ByteSizeLong();
    if (size > static_cast<size_t>(std::numeric_limits<int>::max())) {
        return rac_proto_buffer_set_error(out, RAC_ERROR_ENCODING_ERROR,
                                          "serialized proto exceeds supported size");
    }
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !message.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        std::string error = "failed to serialize ";
        error += message_name;
        return rac_proto_buffer_set_error(out, RAC_ERROR_ENCODING_ERROR, error.c_str());
    }
    return rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(), out);
}

}  // namespace
#endif  // RAC_HAVE_PROTOBUF

extern "C" rac_result_t rac_tool_value_to_json_proto(const uint8_t* in_tool_value_bytes,
                                                     size_t in_size,
                                                     rac_proto_buffer_t* out_string_proto) {
    if (!out_string_proto) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)in_tool_value_bytes;
    (void)in_size;
    return rac_proto_buffer_set_error(out_string_proto, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    rac_result_t validation = rac_proto_bytes_validate(in_tool_value_bytes, in_size);
    if (validation != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_string_proto, RAC_ERROR_DECODING_ERROR,
                                          "ToolValue bytes are invalid");
    }

    runanywhere::v1::ToolValue value;
    if (!value.ParseFromArray(rac_proto_bytes_data_or_empty(in_tool_value_bytes, in_size),
                              static_cast<int>(in_size))) {
        return rac_proto_buffer_set_error(out_string_proto, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse ToolValue");
    }

    json j = tool_value_proto_to_json(value);
    runanywhere::v1::ToolValueJSON wrapper;
    // Preserve key order via dump(); the Swift hand-written bridge used
    // .sortedKeys, which is a stronger guarantee. Nlohmann's object stores
    // map<string,...> by default which already sorts lexicographically.
    wrapper.set_json(j.dump());
    return serialize_to_buffer(wrapper, out_string_proto, "ToolValueJSON");
#endif
}

extern "C" rac_result_t rac_tool_value_from_json_proto(const uint8_t* in_string_bytes,
                                                       size_t in_size,
                                                       rac_proto_buffer_t* out_tool_value) {
    if (!out_tool_value) {
        return RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)in_string_bytes;
    (void)in_size;
    return rac_proto_buffer_set_error(out_tool_value, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    rac_result_t validation = rac_proto_bytes_validate(in_string_bytes, in_size);
    if (validation != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_tool_value, RAC_ERROR_DECODING_ERROR,
                                          "ToolValueJSON bytes are invalid");
    }

    runanywhere::v1::ToolValueJSON wrapper;
    if (!wrapper.ParseFromArray(rac_proto_bytes_data_or_empty(in_string_bytes, in_size),
                                static_cast<int>(in_size))) {
        return rac_proto_buffer_set_error(out_tool_value, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse ToolValueJSON");
    }

    runanywhere::v1::ToolValue value;
    const std::string& text = wrapper.json();
    if (text.empty()) {
        // Empty JSON wrapper == JSON null per the Swift bridge fallback.
        value.set_null_value(true);
    } else {
        json parsed = json::parse(text, nullptr, /*allow_exceptions=*/false);
        if (parsed.is_discarded()) {
            return rac_proto_buffer_set_error(out_tool_value, RAC_ERROR_DECODING_ERROR,
                                              "ToolValueJSON.json is not valid JSON");
        }
        json_to_tool_value_proto(parsed, &value);
    }

    return serialize_to_buffer(value, out_tool_value, "ToolValue");
#endif
}
