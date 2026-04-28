/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for structured output generation.
 * Mirrors Swift RunAnywhere+StructuredOutput.swift.
 *
 * Wave 2 KOTLIN: Added missing namespace extension to align with Swift.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.LLMGenerationResult
import ai.runanywhere.proto.v1.StructuredOutputOptions
import ai.runanywhere.proto.v1.StructuredOutputResult
import com.runanywhere.sdk.public.RunAnywhere

/**
 * Generate structured output (JSON conforming to a schema) from a prompt.
 *
 * @param prompt The prompt to generate from
 * @param structuredOutput Structured output configuration (schema + flags)
 * @param options Optional generation options
 * @return [LLMGenerationResult] with [LLMGenerationResult.structuredOutputValidation] populated
 */
expect suspend fun RunAnywhere.generateWithStructuredOutput(
    prompt: String,
    structuredOutput: StructuredOutputOptions,
    options: LLMGenerationOptions? = null,
): LLMGenerationResult

/**
 * Extract a JSON object from text. The C++ commons exposes this via
 * `rac_structured_output_extract_json` so the Kotlin SDK delegates.
 *
 * @param text The text containing JSON to extract
 * @param schemaJson Optional JSON Schema string used to validate the result
 * @return The extracted JSON string, or `null` if no valid JSON was found
 */
expect suspend fun RunAnywhere.extractStructuredOutput(
    text: String,
    schemaJson: String? = null,
): StructuredOutputResult?
