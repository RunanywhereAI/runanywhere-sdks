/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Ergonomic helpers for canonical Structured Output proto types.
 *
 * Mirrors Swift `StructuredOutputProto+Helpers.swift`. Schema → JSON
 * serialization delegates to the commons C ABI
 * (`rac_structured_output_schema_to_json_proto`) so every SDK shares the
 * same byte-exact, key-sorted, compact text.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.NamedEntity
import ai.runanywhere.proto.v1.StructuredOutputMode
import ai.runanywhere.proto.v1.StructuredOutputOptions
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RAJSONSchema
import com.runanywhere.sdk.public.types.RAStructuredOutputResult

// MARK: - StructuredOutputOptions

/**
 * Default structured-output options mirroring Swift
 * `RAStructuredOutputOptions.defaults(schema:includeSchemaInPrompt:strict:)`.
 *
 * Pre-serializes [schema] into the canonical JSON Schema string consumed
 * by the commons C ABI (`json_schema`) and selects
 * `STRUCTURED_OUTPUT_MODE_JSON_SCHEMA` as the mode.
 */
fun StructuredOutputOptions.Companion.defaults(
    schema: RAJSONSchema,
    includeSchemaInPrompt: Boolean = true,
    strict: Boolean = true,
): StructuredOutputOptions =
    StructuredOutputOptions(
        schema = schema,
        include_schema_in_prompt = includeSchemaInPrompt,
        strict_mode = strict,
        json_schema = schema.jsonSchemaString,
        mode = StructuredOutputMode.STRUCTURED_OUTPUT_MODE_JSON_SCHEMA,
    )

// MARK: - JSONSchema → JSON string

/**
 * Canonical JSON Schema text consumed by the commons structured-output
 * C ABI. Delegates to `rac_structured_output_schema_to_json_proto` (P2-T15)
 * so every SDK shares the same byte-exact, key-sorted, compact serializer
 * (mirrors Swift `RAJSONSchema.jsonSchemaString`). Returns `"{}"` on any
 * serialization or ABI failure to preserve the previous fallback contract.
 */
val RAJSONSchema.jsonSchemaString: String
    get() {
        val serialized = runCatching { RAJSONSchema.ADAPTER.encode(this) }.getOrNull() ?: return "{}"
        val bytes =
            runCatching { RunAnywhereBridge.racStructuredOutputSchemaToJsonProto(serialized) }
                .getOrNull() ?: return "{}"
        if (bytes.isEmpty()) return "{}"
        return runCatching { String(bytes, Charsets.UTF_8) }.getOrDefault("{}")
    }

// MARK: - StructuredOutputResult

/**
 * Convenience flag mirroring Swift `RAStructuredOutputResult.success`.
 */
val RAStructuredOutputResult.success: Boolean
    get() = validation?.is_valid ?: false

// MARK: - NamedEntity

/**
 * Span length (`endOffset - startOffset`, clamped to 0). Mirrors Swift
 * `RANamedEntity.length`.
 */
val NamedEntity.length: Int
    get() = (end_offset - start_offset).coerceAtLeast(0)
