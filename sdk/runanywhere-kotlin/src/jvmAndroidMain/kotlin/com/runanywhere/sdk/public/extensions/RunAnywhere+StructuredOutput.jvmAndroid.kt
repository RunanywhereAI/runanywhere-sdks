/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual for structured output generation.
 *
 * Round 2 KOTLIN: Renamed generateWithStructuredOutput → generateStructured,
 * added generateStructuredStream. extractStructuredOutput still delegates to
 * racStructuredOutputExtractJson JNI thunk (CPP-BLOCKED at runtime until
 * runanywhere_commons_jni.cpp wires the symbol).
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.JSONSchema
import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.LLMStreamEvent
import ai.runanywhere.proto.v1.StructuredOutputOptions
import ai.runanywhere.proto.v1.StructuredOutputResult
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

actual suspend fun RunAnywhere.generateStructured(
    prompt: String,
    schema: JSONSchema,
    options: LLMGenerationOptions?,
): StructuredOutputResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val effectiveOptions =
        (options ?: LLMGenerationOptions()).copy(
            structured_output = StructuredOutputOptions(schema = schema),
        )
    val result = generate(prompt, effectiveOptions)
    // Attempt extraction of JSON from the generated text via the JNI thunk.
    val schemaJsonForExtraction = schema.type.name
    val extracted =
        withContext(Dispatchers.IO) {
            val bytes = RunAnywhereBridge.racStructuredOutputExtractJson(result.text, schemaJsonForExtraction)
            bytes?.let { StructuredOutputResult.ADAPTER.decode(it) }
        }
    return extracted ?: StructuredOutputResult(raw_text = result.text)
}

actual fun RunAnywhere.generateStructuredStream(
    prompt: String,
    schema: JSONSchema,
    options: LLMGenerationOptions?,
): Flow<StructuredOutputResult> {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val effectiveOptions =
        (options ?: LLMGenerationOptions()).copy(
            structured_output = StructuredOutputOptions(schema = schema),
        )
    // Adapt the token stream: collect tokens and emit an accumulating StructuredOutputResult.
    val accumulated = StringBuilder()
    return generateStream(prompt, effectiveOptions).map { event: LLMStreamEvent ->
        if (!event.is_final) {
            accumulated.append(event.token)
        }
        // Emit a partial result on each token (raw_text accumulates)
        StructuredOutputResult(raw_text = accumulated.toString())
    }
}

actual suspend fun RunAnywhere.extractStructuredOutput(
    text: String,
    schemaJson: String?,
): StructuredOutputResult? {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    return withContext(Dispatchers.IO) {
        // [CPP-BLOCKED] rac_structured_output_extract_json JNI thunk is
        // declared in RunAnywhereBridge; the C++ implementation lands as
        // part of the parallel commons track. Until then callers receive
        // UnsatisfiedLinkError at runtime (Iron Rule 4 — no pre-emptive
        // notImplemented throw).
        val bytes =
            RunAnywhereBridge.racStructuredOutputExtractJson(text, schemaJson)
                ?: return@withContext null
        StructuredOutputResult.ADAPTER.decode(bytes)
    }
}
