/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actuals for structured output generation.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.JSONSchema
import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.StructuredOutputMode
import ai.runanywhere.proto.v1.StructuredOutputOptions
import ai.runanywhere.proto.v1.StructuredOutputParseRequest
import ai.runanywhere.proto.v1.StructuredOutputPromptResult
import ai.runanywhere.proto.v1.StructuredOutputRequest
import ai.runanywhere.proto.v1.StructuredOutputResult
import ai.runanywhere.proto.v1.StructuredOutputStreamEvent
import ai.runanywhere.proto.v1.StructuredOutputStreamEventKind
import ai.runanywhere.proto.v1.StructuredOutputValidation
import ai.runanywhere.proto.v1.StructuredOutputValidationRequest
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeStructuredOutput
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext

actual suspend fun RunAnywhere.generateStructured(
    prompt: String,
    schema: JSONSchema,
    options: LLMGenerationOptions?,
): StructuredOutputResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")

    val (generationPrompt, structuredOptions, effectiveOptions) =
        prepareGeneration(prompt, schema, options, streaming = false)
    val generationResult = generate(generationPrompt, effectiveOptions)
    return parseStructuredOutput(
        StructuredOutputParseRequest(
            request_id = UUID.randomUUID().toString(),
            text = generationResult.text,
            options = structuredOptions,
        ),
    )
}

actual fun RunAnywhere.generateStructuredStream(
    prompt: String,
    schema: JSONSchema,
    options: LLMGenerationOptions?,
): Flow<StructuredOutputStreamEvent> {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")

    return flow {
        val requestId = UUID.randomUUID().toString()
        var sequence = 0L
        val accumulated = StringBuilder()

        fun event(kind: StructuredOutputStreamEventKind): StructuredOutputStreamEvent =
            StructuredOutputStreamEvent(
                seq = sequence++,
                timestamp_us = System.currentTimeMillis() * 1000L,
                request_id = requestId,
                kind = kind,
            )

        try {
            val (generationPrompt, structuredOptions, effectiveOptions) =
                prepareGeneration(prompt, schema, options, streaming = true, requestId = requestId)

            generateStream(generationPrompt, effectiveOptions).collect { llmEvent ->
                if (llmEvent.error_message.isNotBlank()) {
                    emit(
                        event(StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_ERROR)
                            .copy(
                                error_message = llmEvent.error_message,
                                error_code = llmEvent.error_code,
                            ),
                    )
                    return@collect
                }

                if (llmEvent.token.isNotEmpty()) {
                    accumulated.append(llmEvent.token)
                    emit(
                        event(StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_TOKEN)
                            .copy(
                                token = llmEvent.token,
                                partial_json = accumulated.toString(),
                            ),
                    )
                }

                if (llmEvent.is_final) {
                    val result =
                        parseStructuredOutput(
                            StructuredOutputParseRequest(
                                request_id = requestId,
                                text = accumulated.toString(),
                                options = structuredOptions,
                            ),
                        )
                    emit(
                        event(StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_COMPLETED)
                            .copy(
                                result = result,
                                validation = result.validation,
                                error_message = result.error_message,
                                error_code = result.error_code,
                            ),
                    )
                }
            }
        } catch (e: Exception) {
            emit(
                event(StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_ERROR)
                    .copy(error_message = e.message ?: "Structured output stream failed"),
            )
        }
    }
}

actual suspend fun RunAnywhere.prepareStructuredOutputPrompt(
    request: StructuredOutputRequest,
): StructuredOutputPromptResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return withContext(Dispatchers.IO) {
        CppBridgeStructuredOutput.preparePrompt(request)
    }
}

actual suspend fun RunAnywhere.validateStructuredOutput(
    request: StructuredOutputValidationRequest,
): StructuredOutputValidation {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return withContext(Dispatchers.IO) {
        CppBridgeStructuredOutput.validate(request)
    }
}

actual suspend fun RunAnywhere.parseStructuredOutput(
    request: StructuredOutputParseRequest,
): StructuredOutputResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return withContext(Dispatchers.IO) {
        CppBridgeStructuredOutput.parse(request)
    }
}

private data class StructuredGenerationPlan(
    val prompt: String,
    val structuredOptions: StructuredOutputOptions,
    val llmOptions: LLMGenerationOptions,
)

private suspend fun RunAnywhere.prepareGeneration(
    prompt: String,
    schema: JSONSchema,
    options: LLMGenerationOptions?,
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
        prepareStructuredOutputPrompt(
            StructuredOutputRequest(
                request_id = requestId,
                prompt = prompt,
                options = initialStructuredOptions,
            ),
        )
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
    val baseOptions = options ?: LLMGenerationOptions()
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
