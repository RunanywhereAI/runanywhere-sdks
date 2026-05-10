/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for structured output generation over generated proto messages.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.JSONSchema
import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.StructuredOutputParseRequest
import ai.runanywhere.proto.v1.StructuredOutputPromptResult
import ai.runanywhere.proto.v1.StructuredOutputRequest
import ai.runanywhere.proto.v1.StructuredOutputResult
import ai.runanywhere.proto.v1.StructuredOutputStreamEvent
import ai.runanywhere.proto.v1.StructuredOutputValidation
import ai.runanywhere.proto.v1.StructuredOutputValidationRequest
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.flow.Flow

// MARK: - Structured Output

/**
 * Generate structured output (JSON conforming to a schema) from a prompt.
 *
 * Canonical cross-SDK name. Replaces the deleted `generateWithStructuredOutput`.
 *
 * @param prompt The prompt to generate from
 * @param schema JSON schema that the output must conform to
 * @param options Optional generation options
 * @return [StructuredOutputResult] with the extracted JSON and validation info
 */
expect suspend fun RunAnywhere.generateStructured(
    prompt: String,
    schema: JSONSchema,
    options: LLMGenerationOptions? = null,
): StructuredOutputResult

/**
 * Stream structured output results for a prompt.
 *
 * @param prompt The prompt to generate from
 * @param schema JSON schema that the output must conform to
 * @param options Optional generation options
 * @return Flow of generated [StructuredOutputStreamEvent] values
 */
expect fun RunAnywhere.generateStructuredStream(
    prompt: String,
    schema: JSONSchema,
    options: LLMGenerationOptions? = null,
): Flow<StructuredOutputStreamEvent>

/**
 * Prepare a structured-output prompt through the generated proto commons ABI.
 */
expect suspend fun RunAnywhere.prepareStructuredOutputPrompt(
    request: StructuredOutputRequest,
): StructuredOutputPromptResult

/** Validate structured output through the generated proto commons ABI. */
expect suspend fun RunAnywhere.validateStructuredOutput(
    request: StructuredOutputValidationRequest,
): StructuredOutputValidation

/** Parse structured output through the generated proto commons ABI. */
expect suspend fun RunAnywhere.parseStructuredOutput(
    request: StructuredOutputParseRequest,
): StructuredOutputResult
