/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Ergonomic helpers for canonical Structured Output proto types.
 *
 * Mirrors Swift `StructuredOutputProto+Helpers.swift`. Schema → JSON
 * serialization uses `kotlinx.serialization.json`.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.JSONSchemaProperty
import ai.runanywhere.proto.v1.JSONSchemaType
import ai.runanywhere.proto.v1.NamedEntity
import ai.runanywhere.proto.v1.StructuredOutputMode
import ai.runanywhere.proto.v1.StructuredOutputOptions
import com.runanywhere.sdk.public.types.RAJSONSchema
import com.runanywhere.sdk.public.types.RAStructuredOutputResult
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.long
import kotlinx.serialization.json.longOrNull

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

private val jsonSerializer: Json = Json {
    prettyPrint = false
    encodeDefaults = false
}

/**
 * Canonical JSON Schema text consumed by the commons structured-output
 * C ABI. Returns the proto's `raw_json` verbatim when present and
 * non-blank; otherwise serializes the typed schema tree.
 */
val RAJSONSchema.jsonSchemaString: String
    get() {
        raw_json?.takeIf { it.isNotBlank() }?.let { return it }
        val element = jsonElement(this)
        return jsonSerializer.encodeToString(JsonElement.serializer(), element)
    }

/**
 * Map a [JSONSchemaType] to its JSON Schema string representation, or
 * null for the UNSPECIFIED case.
 */
val JSONSchemaType.jsonSchemaName: String?
    get() = when (this) {
        JSONSchemaType.JSON_SCHEMA_TYPE_OBJECT -> "object"
        JSONSchemaType.JSON_SCHEMA_TYPE_ARRAY -> "array"
        JSONSchemaType.JSON_SCHEMA_TYPE_STRING -> "string"
        JSONSchemaType.JSON_SCHEMA_TYPE_NUMBER -> "number"
        JSONSchemaType.JSON_SCHEMA_TYPE_INTEGER -> "integer"
        JSONSchemaType.JSON_SCHEMA_TYPE_BOOLEAN -> "boolean"
        JSONSchemaType.JSON_SCHEMA_TYPE_NULL -> "null"
        JSONSchemaType.JSON_SCHEMA_TYPE_UNSPECIFIED -> null
    }

private fun jsonElement(schema: RAJSONSchema): JsonObject {
    schema.raw_json?.takeIf { it.isNotBlank() }?.let { raw ->
        runCatching { jsonSerializer.parseToJsonElement(raw) }
            .getOrNull()
            ?.let { element ->
                if (element is JsonObject) return element
            }
    }

    return buildJsonObject {
        schema.type.jsonSchemaName?.let { put("type", JsonPrimitive(it)) }
        if (schema.properties.isNotEmpty()) {
            val props = JsonObject(schema.properties.mapValues { (_, value) -> jsonElement(value) })
            put("properties", props)
        }
        if (schema.required.isNotEmpty()) {
            put("required", JsonArray(schema.required.map { JsonPrimitive(it) }))
        }
        schema.items?.let { put("items", jsonElement(it)) }
        schema.additional_properties?.let { put("additionalProperties", JsonPrimitive(it)) }
        schema.schema_uri?.let { put("\$schema", JsonPrimitive(it)) }
        schema.id_uri?.let { put("\$id", JsonPrimitive(it)) }
        schema.title?.let { put("title", JsonPrimitive(it)) }
        schema.description?.let { put("description", JsonPrimitive(it)) }
        if (schema.definitions.isNotEmpty()) {
            val defs = JsonObject(schema.definitions.mapValues { (_, value) -> jsonElement(value) })
            put("definitions", defs)
        }
        schema.ref?.let { put("\$ref", JsonPrimitive(it)) }
        if (schema.all_of.isNotEmpty()) {
            put("allOf", JsonArray(schema.all_of.map { jsonElement(it) }))
        }
        if (schema.any_of.isNotEmpty()) {
            put("anyOf", JsonArray(schema.any_of.map { jsonElement(it) }))
        }
        if (schema.one_of.isNotEmpty()) {
            put("oneOf", JsonArray(schema.one_of.map { jsonElement(it) }))
        }
        schema.not_schema?.let { put("not", jsonElement(it)) }
    }
}

private fun jsonElement(property: JSONSchemaProperty): JsonObject {
    // Start from the embedded object_schema (if any), then layer property-specific fields on top.
    val base: Map<String, JsonElement> = property.object_schema?.let { jsonElement(it).toMap() }.orEmpty()
    val result = LinkedHashMap<String, JsonElement>(base)

    property.type.jsonSchemaName?.let { result["type"] = JsonPrimitive(it) }
    property.description?.let { result["description"] = JsonPrimitive(it) }
    if (property.enum_values.isNotEmpty()) {
        result["enum"] = JsonArray(property.enum_values.map { JsonPrimitive(it) })
    }
    property.format?.let { result["format"] = JsonPrimitive(it) }
    property.items_schema?.let { result["items"] = jsonElement(it) }
    property.minimum?.let { result["minimum"] = JsonPrimitive(it) }
    property.maximum?.let { result["maximum"] = JsonPrimitive(it) }
    property.min_length?.let { result["minLength"] = JsonPrimitive(it) }
    property.max_length?.let { result["maxLength"] = JsonPrimitive(it) }
    property.pattern?.let { result["pattern"] = JsonPrimitive(it) }
    property.min_items?.let { result["minItems"] = JsonPrimitive(it) }
    property.max_items?.let { result["maxItems"] = JsonPrimitive(it) }
    property.default_json?.let { raw ->
        result["default"] = parseJsonValue(raw)
    }
    return JsonObject(result)
}

private fun JsonObject.toMap(): Map<String, JsonElement> = LinkedHashMap(this)

private fun parseJsonValue(raw: String): JsonElement =
    runCatching { jsonSerializer.parseToJsonElement(raw) }
        .getOrDefault(JsonPrimitive(raw))

@Suppress("unused")
private fun jsonPrimitiveAsAny(primitive: JsonPrimitive): Any? =
    when {
        primitive is JsonNull -> null
        primitive.isString -> primitive.content
        primitive.booleanOrNull != null -> primitive.boolean
        primitive.longOrNull != null -> primitive.long
        primitive.doubleOrNull != null -> primitive.doubleOrNull
        else -> primitive.content
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
