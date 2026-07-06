/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for structured output generation over generated proto messages.
 *
 * Mirrors Swift `RunAnywhere+StructuredOutput.swift`.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.StructuredOutputOptions
import ai.runanywhere.proto.v1.StructuredOutputParseRequest
import ai.runanywhere.proto.v1.StructuredOutputRequest
import ai.runanywhere.proto.v1.StructuredOutputStreamEvent
import ai.runanywhere.proto.v1.StructuredOutputStreamEventKind
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeStructuredOutput
import com.runanywhere.sdk.foundation.bridge.extensions.defaults
import com.runanywhere.sdk.foundation.bridge.extensions.toRALLMGenerateRequest
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.types.RAJSONSchema
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RALLMGenerationResult
import com.runanywhere.sdk.public.types.RAStructuredOutputResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.withContext
import java.util.UUID

// MARK: - Structured Output

suspend fun RunAnywhere.generateStructured(
    prompt: String,
    schema: RAJSONSchema,
    options: RALLMGenerationOptions? = null,
): RAStructuredOutputResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")

    val generation =
        generateWithStructuredOutput(
            prompt = prompt,
            structuredOutput = StructuredOutputOptions.defaults(schema = schema),
            options = options,
        )
    return extractStructuredOutput(generation.text, schema)
}

suspend fun RunAnywhere.generateWithStructuredOutput(
    prompt: String,
    structuredOutput: StructuredOutputOptions,
    options: RALLMGenerationOptions? = null,
): RALLMGenerationResult {
    var internalOptions =
        (options ?: RALLMGenerationOptions.defaults()).copy(
            structured_output = structuredOutput,
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
            internalOptions = internalOptions.copy(system_prompt = sys)
        }
    }
    val request = internalOptions.copy(streaming_enabled = false).toRALLMGenerateRequest(prompt)
    return generate(request)
}

suspend fun RunAnywhere.extractStructuredOutput(
    text: String,
    schema: RAJSONSchema,
): RAStructuredOutputResult {
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

fun RunAnywhere.generateStructuredStream(
    prompt: String,
    schema: RAJSONSchema,
    options: RALLMGenerationOptions? = null,
): Flow<StructuredOutputStreamEvent> {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")

    val internalOptions =
        (options ?: RALLMGenerationOptions.defaults()).copy(
            structured_output = StructuredOutputOptions.defaults(schema = schema),
        )
    val request = internalOptions.copy(streaming_enabled = true).toRALLMGenerateRequest(prompt)

    return flow {
        var accumulated = ""
        var seq = 0L
        generateStream(request).collect { event ->
            if (event.token.isNotEmpty()) {
                accumulated += event.token
                seq += 1
                emit(
                    StructuredOutputStreamEvent(
                        kind = StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_TOKEN,
                        token = event.token,
                        seq = seq,
                    ),
                )
            }
        }

        seq += 1
        val parsed = extractStructuredOutput(accumulated, schema)
        emit(
            StructuredOutputStreamEvent(
                kind = StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_COMPLETED,
                result = parsed,
                seq = seq,
            ),
        )
    }.onCompletion { cause ->
        // Mirrors Swift's `continuation.onTermination`: fire the native cancel
        // only on consumer cancellation, never on normal/error completion —
        // cancelling there would race a follow-up `generate(...)` call.
        if (cause is CancellationException) {
            withContext(NonCancellable) { cancelGeneration() }
        }
    }.flowOn(Dispatchers.IO)
}
