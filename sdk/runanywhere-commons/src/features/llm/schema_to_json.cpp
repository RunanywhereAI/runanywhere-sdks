/**
 * @file schema_to_json.cpp
 * @brief Implementation of rac_structured_output_schema_to_json_proto.
 *
 * idl/structured_output.proto (API-realignment pass, so-p1) deleted the
 * typed JSON-Schema-in-protobuf tree this file used to walk: enum
 * JSONSchemaType and messages JSONSchemaProperty / JSONSchema are gone.
 * `StructuredOutputOptions.schema` is now a single JSON Schema STRING
 * (the `oneof constraint` arm), so there is no longer a typed tree for
 * commons to serialize — callers already hold the JSON Schema text
 * directly and have no need to round-trip it through this ABI.
 *
 * The public C ABI signature is retained (it is dlsym-bound by name from
 * Swift/Kotlin/Web/RN bridges outside this cluster); the implementation
 * now reports the removed input type as a typed, non-silent failure
 * instead of attempting to parse a message that no longer exists.
 */

#include <cstdint>

#include "rac/features/llm/rac_llm_schema_to_json.h"
#include "rac/foundation/rac_proto_buffer.h"

extern "C" rac_result_t
rac_structured_output_schema_to_json_proto(const uint8_t* in_RAJSONSchema_bytes, size_t in_size,
                                           rac_proto_buffer_t* out) {
    (void)in_RAJSONSchema_bytes;
    (void)in_size;
    if (!out) {
        return RAC_ERROR_NULL_POINTER;
    }
    // runanywhere.v1.JSONSchema was deleted from structured_output.proto:
    // StructuredOutputOptions.schema is now a plain JSON Schema string, so
    // there is no typed tree left for this ABI to serialize.
    return rac_proto_buffer_set_error(
        out, RAC_ERROR_FEATURE_NOT_AVAILABLE,
        "runanywhere.v1.JSONSchema was removed; StructuredOutputOptions.schema is now a JSON "
        "Schema string and needs no proto-to-text conversion");
}
