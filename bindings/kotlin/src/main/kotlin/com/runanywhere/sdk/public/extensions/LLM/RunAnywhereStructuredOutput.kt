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
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeStructuredOutput
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.generated.convenience.defaults
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.api.JsonSchema
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RALLMGenerationResult
import com.runanywhere.sdk.public.types.RAStructuredOutputResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.UUID

// MARK: - Structured Output

@Deprecated("Use RunAnywhere.llm.generateStructured(prompt, schema, options).")
suspend fun RunAnywhere.generateStructured(
    prompt: String,
    schema: JsonSchema,
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

@Deprecated("Use RunAnywhere.llm.generateStructured(prompt, schema, options).")
suspend fun RunAnywhere.generateWithStructuredOutput(
    prompt: String,
    structuredOutput: StructuredOutputOptions,
    options: RALLMGenerationOptions? = null,
): RALLMGenerationResult {
    var internalOptions =
        (options ?: RALLMGenerationOptions.defaults()).copy(
            structured_output = structuredOutput,
        )
    if (structuredOutput.include_schema_in_prompt == true) {
        // StructuredOutputRequest was deleted outright (idl/structured_output.proto,
        // so-p2): StructuredOutputParseRequest (request_id, text, options, metadata)
        // is now the sole request envelope shared by parse/validate/prepare-prompt;
        // `text` plays the role the old `prompt` field did.
        val promptResult =
            withContext(Dispatchers.IO) {
                CppBridgeStructuredOutput.preparePrompt(
                    StructuredOutputParseRequest(
                        request_id = UUID.randomUUID().toString(),
                        text = prompt,
                        options = structuredOutput,
                    ),
                )
            }
        promptResult.error?.let { throw SDKException(it) }
        promptResult.system_prompt?.let { sys ->
            internalOptions = internalOptions.copy(system_prompt = sys)
        }
    }
    val request = internalOptions.toRALLMGenerateRequest(prompt)
    return generate(request)
}

@Deprecated("Use RunAnywhere.llm.generateStructured(prompt, schema, options).")
suspend fun RunAnywhere.extractStructuredOutput(
    text: String,
    schema: JsonSchema,
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

// generateStructuredStream(_:schema:options:) is deleted: its return type,
// StructuredOutputStreamEvent (and StructuredOutputStreamEventKind), was
// removed outright from idl/structured_output.proto (so-p2) with no
// replacement -- structured GENERATION now streams through the ordinary
// `RunAnywhere.llm.generateStream`/`generateStream(request)` path with
// `LLMGenerationOptions.structured_output` set, using the surviving
// LLMStreamEvent shape. Had zero live callers at the time of the API
// realignment (verified against the example app and this module's tests).
