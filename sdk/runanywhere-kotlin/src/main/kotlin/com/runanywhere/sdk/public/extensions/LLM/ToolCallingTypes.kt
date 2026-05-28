/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public tool-calling type aliases + RAToolValue ergonomic helpers.
 *
 * Tool definitions, calls, values, options, and results are generated from
 * idl/tool_calling.proto. This file mirrors Swift `ToolCallingTypes.swift`:
 *
 *  - typealiases to the generated Wire proto messages (RA-prefixed),
 *  - `ToolExecutor` shape matching Swift's
 *    `([String: RAToolValue]) async throws -> [String: RAToolValue]`,
 *  - RAToolValue constructor / accessor / JSON helpers,
 *  - `RAToolCallingOptions.defaults()` factory.
 *
 * The JSON round-trip lives in pure Kotlin via `kotlinx.serialization.json`
 * (Swift uses the `rac_tool_value_{to,from}_json_proto` ABIs, which Kotlin
 * does not currently expose through JNI).
 */

package com.runanywhere.sdk.public.extensions.LLM

import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.LLMGenerationResult
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull

// =============================================================================
// PROTO TYPEALIASES (RA-prefixed, mirroring Swift)
// =============================================================================

typealias ToolValue = ai.runanywhere.proto.v1.ToolValue
typealias ToolValueArray = ai.runanywhere.proto.v1.ToolValueArray
typealias ToolValueObject = ai.runanywhere.proto.v1.ToolValueObject
typealias ToolParameterType = ai.runanywhere.proto.v1.ToolParameterType
typealias ToolParameter = ai.runanywhere.proto.v1.ToolParameter
typealias ToolDefinition = ai.runanywhere.proto.v1.ToolDefinition
typealias ToolCall = ai.runanywhere.proto.v1.ToolCall
typealias ToolResult = ai.runanywhere.proto.v1.ToolResult
typealias ToolCallFormatName = ai.runanywhere.proto.v1.ToolCallFormatName
typealias ToolCallingOptions = ai.runanywhere.proto.v1.ToolCallingOptions
typealias ToolCallingResult = ai.runanywhere.proto.v1.ToolCallingResult

// RA-prefixed aliases co-located with the helpers below. The SDK-wide
// canonical aliases live in `public/types/SwiftAliases.kt`; these mirror
// Swift's `RAToolValue`/`RAToolCallingOptions`/`RAToolCallingResult` names
// for the tool-calling surface specifically.
typealias RAToolValue = ai.runanywhere.proto.v1.ToolValue
typealias RAToolValueArray = ai.runanywhere.proto.v1.ToolValueArray
typealias RAToolValueObject = ai.runanywhere.proto.v1.ToolValueObject
typealias RAToolCallingOptions = ai.runanywhere.proto.v1.ToolCallingOptions
typealias RAToolCallingResult = ai.runanywhere.proto.v1.ToolCallingResult

// =============================================================================
// TOOL EXECUTOR (matches Swift's typed-map signature)
// =============================================================================

/**
 * Function type for host tool executors.
 *
 * Mirrors Swift's
 * `public typealias ToolExecutor = @Sendable ([String: RAToolValue]) async throws -> [String: RAToolValue]`.
 *
 * Arguments and return values are typed `RAToolValue` maps. The SDK marshals
 * to/from JSON (`ToolCall.arguments_json`, `ToolResult.result_json`) via the
 * `RAToolValue.parseObjectJSON` / `RAToolValue.jsonString` helpers below.
 */
typealias ToolExecutor = suspend (Map<String, RAToolValue>) -> Map<String, RAToolValue>

internal data class RegisteredTool(
    val definition: ToolDefinition,
    val executor: ToolExecutor,
)

// =============================================================================
// RAToolCallingOptions.defaults() — Swift parity
// =============================================================================

internal const val DEFAULT_TOOL_CALL_MAX_ITERATIONS = 5

/**
 * Default tool-calling options mirroring Swift's
 * `RAToolCallingOptions.defaults()`:
 * `maxIterations=5, maxToolCalls=5, autoExecute=true, format=.json,
 * formatHint="default"`.
 */
fun ai.runanywhere.proto.v1.ToolCallingOptions.Companion.defaults(): RAToolCallingOptions =
    RAToolCallingOptions(
        max_iterations = DEFAULT_TOOL_CALL_MAX_ITERATIONS,
        max_tool_calls = DEFAULT_TOOL_CALL_MAX_ITERATIONS,
        auto_execute = true,
        format = ToolCallFormatName.TOOL_CALL_FORMAT_NAME_JSON,
        format_hint = "default",
    )

// =============================================================================
// LLMGenerationOptions -> ToolCallingOptions normalization
// =============================================================================

internal fun LLMGenerationOptions?.toToolCallingOptions(): ToolCallingOptions {
    val generationOptions = this
    val providedToolOptions = generationOptions?.tool_calling
    val base = providedToolOptions ?: ToolCallingOptions()
    return base.copy(
        max_iterations =
            base.max_iterations.takeIf { it > 0 }
                ?: base.max_tool_calls?.takeIf { it > 0 }
                ?: if (providedToolOptions == null) DEFAULT_TOOL_CALL_MAX_ITERATIONS else 0,
        auto_execute = if (providedToolOptions == null) true else base.auto_execute,
        temperature =
            base.temperature
                ?: generationOptions?.temperature?.takeUnless { it == 0f },
        max_tokens =
            base.max_tokens
                ?: generationOptions?.max_tokens?.takeIf { it > 0 },
        system_prompt = base.system_prompt ?: generationOptions?.system_prompt,
        format_hint = base.effectiveToolFormatHint(),
    )
}

internal fun ToolCallingOptions.effectiveMaxIterations(): Int =
    max_iterations.takeIf { it > 0 }
        ?: max_tool_calls?.takeIf { it > 0 }
        ?: DEFAULT_TOOL_CALL_MAX_ITERATIONS

internal fun ToolCallingOptions.effectiveToolFormatHint(): String =
    format_hint.ifBlank { format.toToolFormatHint() }.ifBlank { "default" }

/**
 * Lossy conversion from a tool-calling result back into the canonical LLM
 * generation result. Preserved so callers that still want the LLM-shaped
 * payload (text + tool_calls + tool_results) can opt in explicitly; the
 * public `generateWithTools` API now returns `RAToolCallingResult` directly
 * (Swift parity).
 */
internal fun ToolCallingResult.toLLMGenerationResult(modelUsed: String = ""): LLMGenerationResult =
    LLMGenerationResult(
        text = text,
        model_used = modelUsed,
        finish_reason =
            when {
                error_message != null || error_code != 0 -> "error"
                is_complete -> "stop"
                else -> "tool_calls"
            },
        error_message = error_message,
        error_code = error_code,
        tool_calls = tool_calls,
        tool_results = tool_results,
    )

/**
 * Map the generated [ToolCallFormatName] proto enum to its canonical runtime
 * hint string.
 *
 * This mirrors commons' single source of truth
 * `rac_tool_call_format_hint_from_format_name` (sdk/runanywhere-commons/
 * src/features/llm/tool_calling.cpp) exactly: PYTHONIC/HERMES -> "lfm2",
 * everything else -> "default". The previous table emitted "pythonic" /
 * "hermes" / "xml" / "native" / "openai", which the commons accept-list
 * (rac_tool_call_format_from_name) does not recognize and silently downgrades —
 * a per-SDK divergence from iOS. Returns only values commons accepts so the
 * Kotlin and Swift SDKs resolve identical format routes.
 */
private fun ToolCallFormatName?.toToolFormatHint(): String =
    when (this) {
        ToolCallFormatName.TOOL_CALL_FORMAT_NAME_PYTHONIC,
        ToolCallFormatName.TOOL_CALL_FORMAT_NAME_HERMES,
        -> "lfm2"
        ToolCallFormatName.TOOL_CALL_FORMAT_NAME_JSON,
        ToolCallFormatName.TOOL_CALL_FORMAT_NAME_XML,
        ToolCallFormatName.TOOL_CALL_FORMAT_NAME_NATIVE,
        ToolCallFormatName.TOOL_CALL_FORMAT_NAME_OPENAI_FUNCTIONS,
        -> "default"
        else -> ""
    }

// =============================================================================
// RAToolValue ergonomic helpers (mirror Swift `RAToolValue` extension)
// =============================================================================

// MARK: Constructors -----------------------------------------------------------

/** `RAToolValue.string("hi")` — string scalar (Swift: `RAToolValue("hi")`). */
fun ai.runanywhere.proto.v1.ToolValue.Companion.string(v: String): RAToolValue = RAToolValue(string_value = v)

/** `RAToolValue.int(42)` — integer scalar (Swift: `RAToolValue(42)`). */
fun ai.runanywhere.proto.v1.ToolValue.Companion.int(v: Int): RAToolValue =
    RAToolValue(number_value = v.toDouble())

/** `RAToolValue.double(3.14)` — floating-point scalar (Swift: `RAToolValue(3.14)`). */
fun ai.runanywhere.proto.v1.ToolValue.Companion.double(v: Double): RAToolValue =
    RAToolValue(number_value = v)

/** `RAToolValue.bool(true)` — boolean scalar (Swift: `RAToolValue(true)`). */
fun ai.runanywhere.proto.v1.ToolValue.Companion.bool(v: Boolean): RAToolValue =
    RAToolValue(bool_value = v)

/**
 * `RAToolValue.array(listOf(...))` — repeated `RAToolValue` (Swift:
 * `RAToolValue.array(_:)`). Pass `emptyList()` for an empty JSON array.
 */
fun ai.runanywhere.proto.v1.ToolValue.Companion.array(values: List<RAToolValue>): RAToolValue =
    RAToolValue(array_value = RAToolValueArray(values = values))

/**
 * `RAToolValue.object(mapOf(...))` — keyed map of `RAToolValue` (Swift:
 * `RAToolValue.object(_:)`).
 */
@Suppress("FunctionNaming")
fun ai.runanywhere.proto.v1.ToolValue.Companion.`object`(
    fields: Map<String, RAToolValue>,
): RAToolValue = RAToolValue(object_value = RAToolValueObject(fields = fields))

// MARK: Getters ----------------------------------------------------------------

/** Swift parity: `value.string -> String?`. */
val RAToolValue.string: String? get() = string_value

/** Swift parity: `value.number -> Double?`. */
val RAToolValue.number: Double? get() = number_value

/** Swift parity: `value.int -> Int?` (rounded toward zero via `Double.toInt()`). */
val RAToolValue.int: Int? get() = number_value?.toInt()

/** Swift parity: `value.bool -> Bool?`. */
val RAToolValue.bool: Boolean? get() = bool_value

/** Swift parity: `value.array -> [RAToolValue]?`. */
val RAToolValue.array: List<RAToolValue>? get() = array_value?.values

/** Swift parity: `value.object -> [String: RAToolValue]?`. */
@Suppress("VariableNaming")
val RAToolValue.`object`: Map<String, RAToolValue>? get() = object_value?.fields

// MARK: JSON bridge ------------------------------------------------------------

private val toolValueJson: Json =
    Json {
        prettyPrint = false
        encodeDefaults = false
        isLenient = true
        ignoreUnknownKeys = true
    }

private val toolValueJsonPretty: Json =
    Json(from = toolValueJson) {
        prettyPrint = true
    }

private fun RAToolValue.toJsonElement(): JsonElement =
    when {
        string_value != null -> JsonPrimitive(string_value)
        number_value != null -> JsonPrimitive(number_value)
        bool_value != null -> JsonPrimitive(bool_value)
        array_value != null ->
            buildJsonArray {
                for (v in array_value.values) add(v.toJsonElement())
            }
        object_value != null ->
            buildJsonObject {
                for ((k, v) in object_value.fields) put(k, v.toJsonElement())
            }
        null_value == true -> JsonNull
        else -> JsonNull
    }

private fun JsonElement.toRAToolValue(): RAToolValue =
    when (this) {
        is JsonNull -> RAToolValue(null_value = true)
        is JsonPrimitive ->
            when {
                this.isString -> RAToolValue(string_value = contentOrNull ?: "")
                booleanOrNull != null -> RAToolValue(bool_value = booleanOrNull)
                longOrNull != null -> RAToolValue(number_value = longOrNull!!.toDouble())
                intOrNull != null -> RAToolValue(number_value = intOrNull!!.toDouble())
                doubleOrNull != null -> RAToolValue(number_value = doubleOrNull)
                else -> RAToolValue(string_value = contentOrNull ?: "")
            }
        is JsonArray ->
            RAToolValue(
                array_value = RAToolValueArray(values = this.map { it.toRAToolValue() }),
            )
        is JsonObject ->
            RAToolValue(
                object_value =
                    RAToolValueObject(
                        fields = this.mapValues { (_, v) -> v.toRAToolValue() },
                    ),
            )
    }

/**
 * Render this value as a JSON string. Mirrors Swift
 * `RAToolValue.toJSONString(pretty:)`.
 */
fun RAToolValue.toJSONString(pretty: Boolean = false): String? =
    runCatching {
        val encoder = if (pretty) toolValueJsonPretty else toolValueJson
        encoder.encodeToString(JsonElement.serializer(), toJsonElement())
    }.getOrNull()

/**
 * Parse a JSON object string into a `[String: RAToolValue]` map. Returns an
 * empty map on any parse failure or for non-object roots, matching Swift's
 * `RAToolValue.parseObjectJSON(_:)` behavior.
 */
fun ai.runanywhere.proto.v1.ToolValue.Companion.parseObjectJSON(
    json: String,
): Map<String, RAToolValue> {
    if (json.isBlank()) return emptyMap()
    return runCatching {
        val element = toolValueJson.parseToJsonElement(json)
        if (element !is JsonObject) {
            emptyMap()
        } else {
            element.mapValues { (_, v) -> v.toRAToolValue() }
        }
    }.getOrDefault(emptyMap())
}

/**
 * Serialize a `[String: RAToolValue]` map into a JSON object string. Mirrors
 * Swift `RAToolValue.jsonString(from:)`. Returns `"{}"` when serialization
 * fails so wire-shape callers always get valid JSON.
 */
fun ai.runanywhere.proto.v1.ToolValue.Companion.jsonString(
    from: Map<String, RAToolValue>,
): String = RAToolValue.`object`(from).toJSONString() ?: "{}"
