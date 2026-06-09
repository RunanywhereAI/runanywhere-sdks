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

import ai.runanywhere.proto.v1.JSONSchema
import ai.runanywhere.proto.v1.JSONSchemaProperty
import ai.runanywhere.proto.v1.JSONSchemaType
import ai.runanywhere.proto.v1.NamedEntity
import ai.runanywhere.proto.v1.StructuredOutputMode
import ai.runanywhere.proto.v1.StructuredOutputOptions
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.types.RAJSONSchema
import com.runanywhere.sdk.public.types.RAStructuredOutputResult
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

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
 * C ABI. Delegates to `rac_structured_output_schema_to_json_proto`
 * so every SDK shares the same byte-exact, key-sorted, compact serializer
 * (mirrors Swift `RAJSONSchema.jsonSchemaString`). Returns `"{}"` on any
 * serialization or ABI failure to preserve the previous fallback contract.
 */
val RAJSONSchema.jsonSchemaString: String
    get() {
        raw_json?.takeIf { it.isNotBlank() }?.let { return it }
        val serialized = runCatching { RAJSONSchema.ADAPTER.encode(this) }.getOrNull() ?: return "{}"
        val bytes =
            runCatching { RunAnywhereBridge.racStructuredOutputSchemaToJsonProto(serialized) }
                .getOrNull()
        if (bytes != null && bytes.isNotEmpty()) {
            return runCatching { String(bytes, Charsets.UTF_8) }.getOrDefault("{}")
        }
        return runCatching { toJsonElement().toString() }.getOrDefault("{}")
    }

private fun JSONSchema.toJsonElement(): JsonObject =
    buildJsonObject {
        schema_uri?.takeIf { it.isNotBlank() }?.let { put("\$schema", it) }
        id_uri?.takeIf { it.isNotBlank() }?.let { put("\$id", it) }
        title?.takeIf { it.isNotBlank() }?.let { put("title", it) }
        description?.takeIf { it.isNotBlank() }?.let { put("description", it) }
        ref?.takeIf { it.isNotBlank() }?.let { put("\$ref", it) }
        type.toJsonSchemaTypeName()?.let { put("type", it) }
        if (properties.isNotEmpty()) {
            put(
                "properties",
                JsonObject(properties.toSortedMap().mapValues { (_, property) -> property.toJsonElement() }),
            )
        }
        if (required.isNotEmpty()) {
            put("required", JsonArray(required.map(::JsonPrimitive)))
        }
        items?.let { put("items", it.toJsonElement()) }
        additional_properties?.let { put("additionalProperties", it) }
        if (definitions.isNotEmpty()) {
            put(
                "definitions",
                JsonObject(definitions.toSortedMap().mapValues { (_, schema) -> schema.toJsonElement() }),
            )
        }
        if (all_of.isNotEmpty()) put("allOf", all_of.toJsonArray())
        if (any_of.isNotEmpty()) put("anyOf", any_of.toJsonArray())
        if (one_of.isNotEmpty()) put("oneOf", one_of.toJsonArray())
        not_schema?.let { put("not", it.toJsonElement()) }
    }

private fun JSONSchemaProperty.toJsonElement(): JsonObject =
    buildJsonObject {
        type.toJsonSchemaTypeName()?.let { put("type", it) }
        description?.takeIf { it.isNotBlank() }?.let { put("description", it) }
        if (enum_values.isNotEmpty()) {
            put("enum", JsonArray(enum_values.map(::JsonPrimitive)))
        }
        format?.takeIf { it.isNotBlank() }?.let { put("format", it) }
        items_schema?.let { put("items", it.toJsonElement()) }
        object_schema?.let { schema ->
            schema.toJsonElement().forEach { (key, value) -> put(key, value) }
        }
        minimum?.let { put("minimum", it) }
        maximum?.let { put("maximum", it) }
        min_length?.let { put("minLength", it) }
        max_length?.let { put("maxLength", it) }
        pattern?.takeIf { it.isNotBlank() }?.let { put("pattern", it) }
        min_items?.let { put("minItems", it) }
        max_items?.let { put("maxItems", it) }
        default_json?.takeIf { it.isNotBlank() }?.let { put("default", it) }
    }

private fun List<JSONSchema>.toJsonArray(): JsonElement =
    buildJsonArray {
        forEach { add(it.toJsonElement()) }
    }

private fun JSONSchemaType.toJsonSchemaTypeName(): String? =
    when (this) {
        JSONSchemaType.JSON_SCHEMA_TYPE_OBJECT -> "object"
        JSONSchemaType.JSON_SCHEMA_TYPE_ARRAY -> "array"
        JSONSchemaType.JSON_SCHEMA_TYPE_STRING -> "string"
        JSONSchemaType.JSON_SCHEMA_TYPE_NUMBER -> "number"
        JSONSchemaType.JSON_SCHEMA_TYPE_INTEGER -> "integer"
        JSONSchemaType.JSON_SCHEMA_TYPE_BOOLEAN -> "boolean"
        JSONSchemaType.JSON_SCHEMA_TYPE_NULL -> "null"
        JSONSchemaType.JSON_SCHEMA_TYPE_UNSPECIFIED -> null
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
