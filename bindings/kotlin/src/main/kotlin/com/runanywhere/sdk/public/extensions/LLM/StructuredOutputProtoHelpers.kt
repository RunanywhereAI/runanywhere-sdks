/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Ergonomic helpers for canonical Structured Output proto types.
 *
 * idl/structured_output.proto (API-realignment so-p1) deleted the typed
 * JSON-Schema-in-protobuf tree outright: enum `JSONSchemaType` and messages
 * `JSONSchema`/`JSONSchemaProperty` are gone. `StructuredOutputOptions.schema`
 * is now a single JSON Schema STRING (one arm of a `oneof constraint`), so
 * there is no longer a typed tree to serialize -- callers already hold the
 * JSON Schema text directly. `com.runanywhere.sdk.public.api.JsonSchema`
 * (Aliases.kt) is a lightweight wrapper around that raw text.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.StructuredOutputOptions
import com.runanywhere.sdk.public.api.JsonSchema
import com.runanywhere.sdk.public.types.RAStructuredOutputResult

// MARK: - StructuredOutputOptions

/**
 * Default structured-output options mirroring Swift
 * `RAStructuredOutputOptions.defaults(schema:includeSchemaInPrompt:strict:)`.
 *
 * `strict`/`repair` have no wire home any more (`strict_mode`/`mode`/
 * `repair_json` were all deleted from `StructuredOutputOptions`): retry
 * behaviour for an invalid first pass is owned entirely by the Kotlin-side
 * `llm.generateStructured(mode = REPAIR)` loop, not a commons flag.
 */
fun StructuredOutputOptions.Companion.defaults(
    schema: JsonSchema,
    includeSchemaInPrompt: Boolean = true,
): StructuredOutputOptions =
    StructuredOutputOptions(
        include_schema_in_prompt = includeSchemaInPrompt,
        schema = schema.rawJson,
    )

// MARK: - StructuredOutputResult

/**
 * Convenience flag mirroring Swift `RAStructuredOutputResult.success`.
 */
val RAStructuredOutputResult.success: Boolean
    get() = validation?.is_valid ?: false
