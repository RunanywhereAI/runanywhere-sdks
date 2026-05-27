/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for structured output generation over generated proto messages.
 *
 * Mirrors Swift `RunAnywhere+StructuredOutput.swift`.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.StructuredOutputMode
import ai.runanywhere.proto.v1.StructuredOutputOptions
import ai.runanywhere.proto.v1.StructuredOutputParseRequest
import ai.runanywhere.proto.v1.StructuredOutputRequest
import ai.runanywhere.proto.v1.StructuredOutputStreamEvent
import ai.runanywhere.proto.v1.StructuredOutputStreamEventKind
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeStructuredOutput
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAJSONSchema
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RALLMGenerationResult
import com.runanywhere.sdk.public.types.RAStructuredOutputResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

// MARK: - Structured Output

suspend fun RunAnywhere.generateStructured(
    prompt: String,
    schema: RAJSONSchema,
    options: RALLMGenerationOptions?,
): RAStructuredOutputResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")

    val (generationPrompt, _, effectiveOptions) =
        prepareGeneration(prompt, schema, options, streaming = false)
    val generationResult = generate(generationPrompt, effectiveOptions)
    return extractStructuredOutput(generationResult.text, schema)
}

suspend fun RunAnywhere.generateWithStructuredOutput(
    prompt: String,
    structuredOutput: StructuredOutputOptions,
    options: RALLMGenerationOptions?,
): RALLMGenerationResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")

    val baseOptions = options ?: RALLMGenerationOptions()
    val schemaJson =
        structuredOutput.json_schema?.takeIf { it.isNotBlank() }
            ?: structuredOutput.schema?.jsonSchemaString
            ?: ""
    var effectiveOptions =
        baseOptions.copy(
            structured_output = structuredOutput,
            json_schema = schemaJson,
        )
    if (structuredOutput.include_schema_in_prompt) {
        val promptResult =
            withContext(Dispatchers.IO) {
                CppBridgeStructuredOutput.preparePrompt(
                    StructuredOutputRequest(
                        request_id = UUID.randomUUID().toString(),
                        prompt = prompt,
                        options = structuredOutput,
                    ),
                )
            }
        if (promptResult.error_code != 0) {
            throw SDKException.operation(
                promptResult.error_message
                    ?: "Structured output prompt preparation failed: ${promptResult.error_code}",
            )
        }
        promptResult.system_prompt?.let { sys ->
            effectiveOptions = effectiveOptions.copy(system_prompt = sys)
        }
    }
    return generate(prompt, effectiveOptions)
}

suspend fun RunAnywhere.extractStructuredOutput(
    text: String,
    schema: RAJSONSchema,
): RAStructuredOutputResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val request =
        StructuredOutputParseRequest(
            request_id = UUID.randomUUID().toString(),
            text = text,
            options = StructuredOutputOptions.defaults(schema = schema),
        )
    return withContext(Dispatchers.IO) {
        CppBridgeStructuredOutput.parse(request)
    }
}

@Suppress("UnusedParameter")
fun RunAnywhere.generateStructuredStream(
    prompt: String,
    schema: RAJSONSchema,
    options: RALLMGenerationOptions?,
): Flow<StructuredOutputStreamEvent> {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")

    // Commons owns the full streaming pipeline: it drives the LLM, emits
    // TOKEN / PARTIAL_JSON events as complete JSON values become available,
    // and a single terminal COMPLETED / ERROR event with the parsed result.
    // Kotlin simply decodes and forwards — no client-side accumulation.
    // `options` is intentionally accepted for Swift signature parity but
    // not yet threaded through the StructuredOutputRequest proto; LLM
    // generation options are picked up from the lifecycle-owned LLM
    // service. Wiring user-supplied options through the streaming proto
    // surface is a follow-up parity item.
    return callbackFlow {
        val requestId = UUID.randomUUID().toString()
        val driver =
            launch(Dispatchers.IO) {
                val structuredOptions =
                    StructuredOutputOptions(
                        schema = schema,
                        include_schema_in_prompt = true,
                        mode = StructuredOutputMode.STRUCTURED_OUTPUT_MODE_JSON_SCHEMA,
                    )
                try {
                    CppBridgeStructuredOutput.generateStream(
                        StructuredOutputRequest(
                            request_id = requestId,
                            prompt = prompt,
                            options = structuredOptions,
                        ),
                    ) { event ->
                        trySend(event)
                        val terminal =
                            event.kind == StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_COMPLETED ||
                                event.kind == StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_ERROR
                        !terminal
                    }
                    close()
                } catch (e: Exception) {
                    close(e)
                }
            }
        awaitClose {
            driver.cancel()
        }
    }.flowOn(Dispatchers.IO)
}

private data class StructuredGenerationPlan(
    val prompt: String,
    val structuredOptions: StructuredOutputOptions,
    val llmOptions: RALLMGenerationOptions,
)

private suspend fun RunAnywhere.prepareGeneration(
    prompt: String,
    schema: RAJSONSchema,
    options: RALLMGenerationOptions?,
    streaming: Boolean,
    requestId: String = UUID.randomUUID().toString(),
): StructuredGenerationPlan {
    val initialStructuredOptions =
        StructuredOutputOptions(
            schema = schema,
            include_schema_in_prompt = true,
            mode = StructuredOutputMode.STRUCTURED_OUTPUT_MODE_JSON_SCHEMA,
        )
    val promptResult =
        withContext(Dispatchers.IO) {
            CppBridgeStructuredOutput.preparePrompt(
                StructuredOutputRequest(
                    request_id = requestId,
                    prompt = prompt,
                    options = initialStructuredOptions,
                ),
            )
        }
    if (promptResult.error_code != 0) {
        throw SDKException.operation(
            promptResult.error_message
                ?: "Structured output prompt preparation failed: ${promptResult.error_code}",
        )
    }

    val structuredOptions =
        initialStructuredOptions.copy(
            json_schema = promptResult.json_schema ?: initialStructuredOptions.json_schema,
        )
    val baseOptions = options ?: RALLMGenerationOptions()
    val llmOptions =
        baseOptions.copy(
            max_tokens = baseOptions.max_tokens.takeIf { it > 0 } ?: 1500,
            temperature = baseOptions.temperature.takeUnless { it == 0f } ?: 0.7f,
            top_p = baseOptions.top_p.takeUnless { it == 0f } ?: 1.0f,
            streaming_enabled = streaming || baseOptions.streaming_enabled,
            system_prompt = promptResult.system_prompt ?: baseOptions.system_prompt,
            json_schema = promptResult.json_schema ?: baseOptions.json_schema,
            structured_output = structuredOptions,
        )
    return StructuredGenerationPlan(
        prompt = promptResult.prepared_prompt.ifBlank { prompt },
        structuredOptions = structuredOptions,
        llmOptions = llmOptions,
    )
}
