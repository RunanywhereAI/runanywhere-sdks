/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for structured output generation over generated proto messages.
 *
 * Mirrors Swift `RunAnywhere+StructuredOutput.swift`.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.JSONSchema
import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.LLMGenerationResult
import ai.runanywhere.proto.v1.StructuredOutputOptions
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
 * Canonical cross-SDK name; mirrors Swift `RunAnywhere.generateStructured`.
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
 * Generate text with structured output configuration.
 *
 * Mirrors Swift `RunAnywhere.generateWithStructuredOutput`. Returns the raw
 * [LLMGenerationResult]; callers parse `text` via [extractStructuredOutput]
 * if a typed structured value is required.
 *
 * @param prompt The prompt to generate from
 * @param structuredOutput Structured output configuration
 * @param options Optional generation options
 * @return [LLMGenerationResult] for the underlying generation
 */
expect suspend fun RunAnywhere.generateWithStructuredOutput(
    prompt: String,
    structuredOutput: StructuredOutputOptions,
    options: LLMGenerationOptions? = null,
): LLMGenerationResult

/**
 * Extract structured output from a raw text string using a JSON schema.
 *
 * Delegates to the generated structured-output parse proto ABI so commons
 * owns extraction, canonicalization, and schema validation. Mirrors Swift
 * `RunAnywhere.extractStructuredOutput(text:schema:)`.
 *
 * @param text The raw model output text to parse
 * @param schema JSON schema that the output must conform to
 * @return [StructuredOutputResult] with the parsed JSON and validation info
 */
expect suspend fun RunAnywhere.extractStructuredOutput(
    text: String,
    schema: JSONSchema,
): StructuredOutputResult

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
