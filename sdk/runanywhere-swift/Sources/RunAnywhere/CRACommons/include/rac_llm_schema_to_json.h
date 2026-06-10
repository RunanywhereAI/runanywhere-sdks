/**
 * @file rac_llm_schema_to_json.h
 * @brief RunAnywhere Commons - JSONSchema proto -> JSON Schema string ABI.
 *
 * Exposes the canonical JSON-schema text serializer that previously
 * lived in Swift's StructuredOutputProto+Helpers.swift JSONSchemaWriter
 * (~130 LOC). Letting commons own this serializer means every SDK can drop
 * its private JSON-schema writer and ride the same byte-exact text used by
 * the structured-output proto pipeline (rac_structured_output_*_proto).
 *
 * Wire shape:
 *   - Input  : serialized runanywhere.v1.JSONSchema bytes.
 *   - Output : owned UTF-8 JSON Schema text in rac_proto_buffer_t.data
 *              (size excludes trailing NUL; data is NUL-terminated for
 *               convenient C-side use).
 *
 * Output is always compact (no whitespace) with object keys sorted
 * lexicographically — matching Swift's
 * `JSONSerialization.data(withJSONObject:options:[.sortedKeys])`. When the
 * input schema carries `raw_json` and it parses, the parsed value is
 * re-serialized through the same compact-sorted writer, so callers get a
 * canonicalized text regardless of the input source.
 *
 * Failure modes:
 *   - RAC_ERROR_NULL_POINTER          : out_result is NULL.
 *   - RAC_ERROR_DECODING_ERROR        : invalid borrowed bytes or proto failed
 *                                       to parse.
 *   - RAC_ERROR_FEATURE_NOT_AVAILABLE : compiled without RAC_HAVE_PROTOBUF.
 *
 * On success, callers must release out_result with rac_proto_buffer_free().
 */

#ifndef RAC_LLM_SCHEMA_TO_JSON_H
#define RAC_LLM_SCHEMA_TO_JSON_H

#include <stddef.h>
#include <stdint.h>

#include "rac_error.h"
#include "rac_types.h"
#include "rac_proto_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Serialize a JSONSchema proto to a JSON Schema string.
 *
 * Accepts a borrowed runanywhere.v1.JSONSchema protobuf payload and writes
 * the canonical compact, key-sorted JSON Schema text into out_result. The
 * algorithm matches the Swift JSONSchemaWriter (StructuredOutputProto+Helpers
 * lines 47-177) field-for-field so that swapping the Swift implementation for
 * this ABI yields byte-identical schema text.
 *
 * @param in_RAJSONSchema_bytes Borrowed serialized JSONSchema bytes.
 * @param in_size               Size of in_RAJSONSchema_bytes.
 * @param out                   Owned JSON Schema UTF-8 text on success, or
 *                              typed error metadata on failure. Caller frees
 *                              with rac_proto_buffer_free().
 * @return RAC_SUCCESS when out carries serialized JSON text.
 */
RAC_API rac_result_t rac_structured_output_schema_to_json_proto(
    const uint8_t* in_RAJSONSchema_bytes, size_t in_size, rac_proto_buffer_t* out);

#ifdef __cplusplus
}
#endif

#endif /* RAC_LLM_SCHEMA_TO_JSON_H */
