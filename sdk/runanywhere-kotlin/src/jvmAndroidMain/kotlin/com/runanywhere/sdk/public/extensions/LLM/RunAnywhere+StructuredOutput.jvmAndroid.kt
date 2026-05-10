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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID

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

    // Commons owns the full streaming pipeline: it drives the LLM, emits
    // TOKEN / PARTIAL_JSON events as complete JSON values become available,
    // and a single terminal COMPLETED / ERROR event with the parsed result.
    // Kotlin simply decodes and forwards — no client-side accumulation.
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
