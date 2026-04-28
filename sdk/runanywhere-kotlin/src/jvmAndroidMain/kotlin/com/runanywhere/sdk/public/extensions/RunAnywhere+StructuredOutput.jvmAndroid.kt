/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual for structured output generation.
 * Wave 2 KOTLIN: Stub implementation pending C++ rac_structured_output_* binding.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.LLMGenerationResult
import ai.runanywhere.proto.v1.StructuredOutputOptions
import ai.runanywhere.proto.v1.StructuredOutputResult
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere

actual suspend fun RunAnywhere.generateWithStructuredOutput(
    prompt: String,
    structuredOutput: StructuredOutputOptions,
    options: LLMGenerationOptions?,
): LLMGenerationResult {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    val effectiveOptions =
        (options ?: LLMGenerationOptions()).copy(
            structured_output = structuredOutput,
        )
    return generate(prompt, effectiveOptions)
}

actual suspend fun RunAnywhere.extractStructuredOutput(
    text: String,
    schemaJson: String?,
): StructuredOutputResult? {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    // Pending C++ rac_structured_output_extract_json JNI wiring; for now
    // surface as notImplemented to signal that the wire is not yet plumbed.
    throw SDKException.notImplemented("Structured output extraction (rac_structured_output_extract_json) is being wired up")
}
