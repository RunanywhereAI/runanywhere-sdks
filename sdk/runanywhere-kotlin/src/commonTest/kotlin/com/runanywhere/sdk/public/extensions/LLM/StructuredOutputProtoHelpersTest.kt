package com.runanywhere.sdk.public.extensions.LLM

import ai.runanywhere.proto.v1.JSONSchema
import ai.runanywhere.proto.v1.JSONSchemaProperty
import ai.runanywhere.proto.v1.JSONSchemaType
import ai.runanywhere.proto.v1.StructuredOutputMode
import ai.runanywhere.proto.v1.StructuredOutputOptions
import ai.runanywhere.proto.v1.StructuredOutputParseRequest
import ai.runanywhere.proto.v1.StructuredOutputRequest
import com.runanywhere.sdk.public.extensions.defaults
import com.runanywhere.sdk.public.extensions.jsonSchemaString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Mirrors Swift `StructuredOutputProtoHelpersTests.swift`.
 *
 * Focused tests for generated structured-output helpers exposed by
 * `StructuredOutputProtoHelpers.kt` and the canonical proto types.
 */
class StructuredOutputProtoHelpersTest {
    @Test
    fun testJSONSchemaSerializesAsJSONSchemaText() {
        val answer =
            JSONSchemaProperty(
                type = JSONSchemaType.JSON_SCHEMA_TYPE_STRING,
                description = "Short answer",
            )
        val score =
            JSONSchemaProperty(
                type = JSONSchemaType.JSON_SCHEMA_TYPE_NUMBER,
                minimum = 0.0,
                maximum = 1.0,
            )

        val schema =
            JSONSchema(
                type = JSONSchemaType.JSON_SCHEMA_TYPE_OBJECT,
                properties = mapOf("answer" to answer, "score" to score),
                required = listOf("answer"),
                additional_properties = false,
            )

        val json = parseObject(schema.jsonSchemaString)
        assertEquals("object", json["type"]?.jsonPrimitive?.content)
        assertEquals(listOf("answer"), json["required"]?.jsonArray?.map { it.jsonPrimitive.content })
        assertEquals(false, json["additionalProperties"]?.jsonPrimitive?.boolean)

        val properties = assertNotNull(json["properties"]?.jsonObject)
        val answerSchema = assertNotNull(properties["answer"]?.jsonObject)
        assertEquals("string", answerSchema["type"]?.jsonPrimitive?.content)
        assertEquals("Short answer", answerSchema["description"]?.jsonPrimitive?.content)

        val scoreSchema = assertNotNull(properties["score"]?.jsonObject)
        assertEquals("number", scoreSchema["type"]?.jsonPrimitive?.content)
        assertEquals(0.0, scoreSchema["minimum"]?.jsonPrimitive?.double)
        assertEquals(1.0, scoreSchema["maximum"]?.jsonPrimitive?.double)
    }

    @Test
    fun testStructuredOutputOptionsCarrySchemaJsonForCABI() {
        val schema = JSONSchema(type = JSONSchemaType.JSON_SCHEMA_TYPE_ARRAY)

        val options = StructuredOutputOptions.defaults(schema = schema)
        assertEquals(StructuredOutputMode.STRUCTURED_OUTPUT_MODE_JSON_SCHEMA, options.mode)
        assertTrue(options.include_schema_in_prompt)
        assertEquals(JSONSchemaType.JSON_SCHEMA_TYPE_ARRAY, options.schema?.type)

        val json = parseObject(options.json_schema ?: "")
        assertEquals("array", json["type"]?.jsonPrimitive?.content)
    }

    @Test
    fun testStructuredOutputParseRequestUsesGeneratedOptions() {
        val value = JSONSchemaProperty(type = JSONSchemaType.JSON_SCHEMA_TYPE_STRING)
        val schema =
            JSONSchema(
                type = JSONSchemaType.JSON_SCHEMA_TYPE_OBJECT,
                properties = mapOf("status" to value),
                required = listOf("status"),
            )

        val request =
            StructuredOutputParseRequest(
                request_id = "structured-test",
                text = "answer {\"status\":\"ok\"}",
                options = StructuredOutputOptions.defaults(schema = schema),
            )

        assertEquals("structured-test", request.request_id)
        assertEquals("answer {\"status\":\"ok\"}", request.text)
        val opts = assertNotNull(request.options)
        assertEquals(JSONSchemaType.JSON_SCHEMA_TYPE_OBJECT, opts.schema?.type)
        assertEquals(StructuredOutputMode.STRUCTURED_OUTPUT_MODE_JSON_SCHEMA, opts.mode)
        assertTrue(opts.include_schema_in_prompt)
        assertTrue((opts.json_schema ?: "").contains("\"status\""))
    }

    @Test
    fun testStructuredOutputPreparePromptRequestUsesGeneratedContract() {
        val schema = JSONSchema(type = JSONSchemaType.JSON_SCHEMA_TYPE_ARRAY)
        val options = StructuredOutputOptions.defaults(schema = schema)

        val request =
            StructuredOutputRequest(
                request_id = "prepare-test",
                prompt = "Return rows",
                options = options,
            )

        assertEquals("prepare-test", request.request_id)
        assertEquals("Return rows", request.prompt)
        val opts = assertNotNull(request.options)
        assertEquals(JSONSchemaType.JSON_SCHEMA_TYPE_ARRAY, opts.schema?.type)
        assertEquals(StructuredOutputMode.STRUCTURED_OUTPUT_MODE_JSON_SCHEMA, opts.mode)
        assertTrue((opts.json_schema ?: "").contains("\"array\""))
    }

    @Test
    fun testRawJsonRoundTripsThroughJsonSchemaString() {
        // jsonSchemaString returns raw_json verbatim when present and non-blank.
        val raw = """{"type":"string","minLength":3}"""
        val schema = JSONSchema(raw_json = raw)
        assertEquals(raw, schema.jsonSchemaString)
    }

    private fun parseObject(json: String): JsonObject {
        val element = Json.parseToJsonElement(json)
        return element.jsonObject
    }
}
