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
 * G3: the recursive ToolValue <-> JSON walk lives in commons behind
 * `rac_tool_value_to_json_proto` / `rac_tool_value_from_json_proto` (mirroring
 * Swift `ToolCallingTypes.swift`). Kotlin only marshals the proto bytes — this
 * preserves the integer-vs-double distinction the pure-Kotlin walk used to
 * lose, and keeps the SDKs byte-identical.
 */

package com.runanywhere.sdk.public.extensions.LLM

import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.ToolValueJSON
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

// PROTO TYPEALIASES (RA-prefixed, mirroring Swift)

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

// TOOL EXECUTOR (matches Swift's typed-map signature)

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

// RAToolCallingOptions.defaults() — Swift parity

internal const val DEFAULT_MAX_TOOL_CALLS = 5

/**
 * Default tool-calling options mirroring Swift's
 * `RAToolCallingOptions.defaults()`:
 * `maxToolCalls=5, autoExecute=true, format=.json`.
 */
fun ai.runanywhere.proto.v1.ToolCallingOptions.Companion.defaults(): RAToolCallingOptions =
    RAToolCallingOptions(
        max_tool_calls = DEFAULT_MAX_TOOL_CALLS,
        auto_execute = true,
        format = ToolCallFormatName.TOOL_CALL_FORMAT_NAME_JSON,
    )

// LLMGenerationOptions -> ToolCallingOptions normalization

internal fun LLMGenerationOptions?.toToolCallingOptions(): ToolCallingOptions {
    val generationOptions = this
    val providedToolOptions = generationOptions?.tool_calling
    val base = providedToolOptions ?: ToolCallingOptions()
    return base.copy(
        max_tool_calls =
            base.max_tool_calls?.takeIf { it > 0 }
                ?: if (providedToolOptions == null) DEFAULT_MAX_TOOL_CALLS else null,
        auto_execute = if (providedToolOptions == null) true else base.auto_execute,
        temperature =
            base.temperature
                ?: generationOptions?.temperature?.takeUnless { it == 0f },
        max_tokens =
            base.max_tokens
                ?: generationOptions?.max_tokens?.takeIf { it > 0 },
        system_prompt = base.system_prompt ?: generationOptions?.system_prompt,
    )
}

internal fun ToolCallingOptions.effectiveMaxToolCalls(): Int =
    max_tool_calls?.takeIf { it > 0 } ?: DEFAULT_MAX_TOOL_CALLS

// RAToolValue ergonomic helpers (mirror Swift `RAToolValue` extension)

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
//
// The recursive walk lives in commons (G3); Kotlin only marshals bytes via
// the `rac_tool_value_{to,from}_json_proto` JNI thunks, mirroring Swift's
// ToolCallingTypes.swift. This preserves the integer-vs-double distinction the
// previous pure-Kotlin walk lost and keeps every SDK byte-identical.

/**
 * Render this value as a JSON string. Mirrors Swift
 * `RAToolValue.toJSONString(pretty:)` — routes through
 * `rac_tool_value_to_json_proto`. `pretty` re-renders the canonical JSON with
 * sorted keys for presentation; null on any failure.
 */
fun RAToolValue.toJSONString(pretty: Boolean = false): String? {
    val resultBytes =
        RunAnywhereBridge.racToolValueToJsonProto(RAToolValue.ADAPTER.encode(this)) ?: return null
    val json =
        runCatching { ToolValueJSON.ADAPTER.decode(resultBytes).json }.getOrNull() ?: return null
    if (!pretty) return json
    // Pretty-print is a presentation concern; re-render the already-canonical
    // JSON text with sorted keys (mirrors Swift's Foundation re-render).
    return runCatching {
        val pretty =
            kotlinx.serialization.json.Json {
                prettyPrint = true
            }
        val element =
            kotlinx.serialization.json.Json
                .parseToJsonElement(json)
        pretty.encodeToString(
            kotlinx.serialization.json.JsonElement
                .serializer(),
            element,
        )
    }.getOrDefault(json)
}

/**
 * Parse a JSON object string into a `[String: RAToolValue]` map via
 * `rac_tool_value_from_json_proto`. Mirrors Swift: malformed JSON and
 * non-object roots throw so callers surface a failed tool result instead of
 * executing the tool with silently-empty arguments.
 */
fun ai.runanywhere.proto.v1.ToolValue.Companion.parseObjectJSON(
    json: String,
): Map<String, RAToolValue> {
    if (json.isBlank()) {
        throw SDKException.invalidArgument("Tool arguments JSON must be a non-empty object")
    }
    val wrapper = ToolValueJSON(json = json)
    val valueBytes =
        RunAnywhereBridge.racToolValueFromJsonProto(ToolValueJSON.ADAPTER.encode(wrapper))
            ?: throw SDKException.invalidArgument("Malformed tool arguments JSON")
    val decoded =
        runCatching {
            RAToolValue.ADAPTER.decode(valueBytes)
        }.getOrElse { error ->
            throw SDKException.invalidArgument("Failed to decode tool arguments JSON", error)
        }
    return decoded
        .object_value
        ?.fields
        ?: throw SDKException.invalidArgument("Tool arguments JSON root must be an object")
}

/**
 * Serialize a `[String: RAToolValue]` map into a JSON object string. Mirrors
 * Swift `RAToolValue.jsonString(from:)`. Returns `"{}"` when serialization
 * fails so wire-shape callers always get valid JSON.
 */
fun ai.runanywhere.proto.v1.ToolValue.Companion.jsonString(
    from: Map<String, RAToolValue>,
): String = RAToolValue.`object`(from).toJSONString() ?: "{}"
