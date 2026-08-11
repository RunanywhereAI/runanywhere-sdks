package com.runanywhere.sdk.public.extensions.LLM

import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.StructuredOutputOptions
import ai.runanywhere.proto.v1.StructuredOutputParseRequest
import com.runanywhere.sdk.foundation.bridge.extensions.toRALLMGenerateRequest
import com.runanywhere.sdk.generated.convenience.defaults
import com.runanywhere.sdk.public.api.JsonSchema
import com.runanywhere.sdk.public.extensions.defaults
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Mirrors Swift `StructuredOutputProtoHelpersTests.swift`.
 *
 * `JSONSchema`/`JSONSchemaProperty`/`JSONSchemaType` are deleted outright
 * (idl/structured_output.proto): `StructuredOutputOptions.schema` is now a
 * single raw JSON Schema STRING (the `oneof constraint` arm), so these
 * tests build schema text directly rather than a typed tree.
 *
 * Focused tests for generated structured-output helpers exposed by
 * `StructuredOutputProtoHelpers.kt` and the canonical proto types.
 */
class StructuredOutputProtoHelpersTest {
    private val objectSchemaWithAnswerAndScore =
        """{"type":"object","properties":{"answer":{"type":"string","description":"Short answer"},""" +
            """"score":{"type":"number","minimum":0,"maximum":1}},"required":["answer"],"additionalProperties":false}"""

    @Test
    fun testStructuredOutputOptionsCarrySchemaStringForCABI() {
        val schema = """{"type":"array"}"""
        val options = StructuredOutputOptions.defaults(JsonSchema(schema))
        assertTrue(options.include_schema_in_prompt ?: false)

        // `schema` is a plain string on the oneof `constraint` arm now -- no
        // typed tree, no separate json_schema field to decode.
        val json = parseObject(options.schema ?: "")
        assertEquals("array", json["type"]?.jsonPrimitive?.content)
    }

    @Test
    fun testLLMRequestUsesStructuredOutputSchemaString() {
        val schema = objectSchemaWithAnswerAndScore

        val generationOptions =
            LLMGenerationOptions.defaults().copy(
                structured_output = StructuredOutputOptions.defaults(JsonSchema(schema)),
            )

        val request = generationOptions.toRALLMGenerateRequest(prompt = "Return a value")
        val structuredOutput = assertNotNull(request.options?.structured_output)
        val json = parseObject(structuredOutput.schema ?: "")

        assertNotNull(request.options)
        assertEquals("object", json["type"]?.jsonPrimitive?.content)
        val properties = assertNotNull(json["properties"]?.jsonObject)
        val answerSchema = assertNotNull(properties["answer"]?.jsonObject)
        assertEquals("string", answerSchema["type"]?.jsonPrimitive?.content)
        assertEquals("Short answer", answerSchema["description"]?.jsonPrimitive?.content)
        val scoreSchema = assertNotNull(properties["score"]?.jsonObject)
        assertEquals("number", scoreSchema["type"]?.jsonPrimitive?.content)
        assertEquals(0.0, scoreSchema["minimum"]?.jsonPrimitive?.double)
        assertEquals(1.0, scoreSchema["maximum"]?.jsonPrimitive?.double)
        assertEquals(false, json["additionalProperties"]?.jsonPrimitive?.boolean)
    }

    @Test
    fun testStructuredOutputParseRequestUsesGeneratedOptions() {
        val schema = """{"type":"object","properties":{"status":{"type":"string"}},"required":["status"]}"""

        val request =
            StructuredOutputParseRequest(
                request_id = "structured-test",
                text = "answer {\"status\":\"ok\"}",
                options = StructuredOutputOptions.defaults(JsonSchema(schema)),
            )

        assertEquals("structured-test", request.request_id)
        assertEquals("answer {\"status\":\"ok\"}", request.text)
        val opts = assertNotNull(request.options)
        assertTrue(opts.include_schema_in_prompt ?: false)
        assertTrue((opts.schema ?: "").contains("\"status\""))
    }

    @Test
    fun testStructuredOutputParseRequestEnvelopeCarriesPromptAsText() {
        // `StructuredOutputRequest`/`makeGenerateRequest` are deleted
        // outright: `StructuredOutputParseRequest` (request_id, text,
        // options, metadata) is now the sole envelope shared by
        // parse/validate/prepare-prompt, with `text` playing the role the
        // old `prompt` field did.
        val schema = """{"type":"array"}"""
        val request =
            StructuredOutputParseRequest(
                request_id = "prepare-test",
                text = "Return rows",
                options = StructuredOutputOptions.defaults(JsonSchema(schema)),
            )

        assertEquals("prepare-test", request.request_id)
        assertEquals("Return rows", request.text)
        assertTrue((request.options?.schema ?: "").contains("array"))
    }

    private fun parseObject(json: String): JsonObject {
        val element = Json.parseToJsonElement(json)
        return element.jsonObject
    }
}
