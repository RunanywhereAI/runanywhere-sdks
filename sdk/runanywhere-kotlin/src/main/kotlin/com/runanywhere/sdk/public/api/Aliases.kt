/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: names that resolve to canonical generated proto types.
 * Only shapes the v3 spec does not redefine are aliased here.
 */

package com.runanywhere.sdk.public.api

/**
 * JSON Schema used to constrain structured generation.
 *
 * `runanywhere.v1.JSONSchema` was deleted outright (idl/structured_output.proto):
 * `StructuredOutputOptions.schema` is now a single JSON Schema STRING, so
 * there is no typed proto tree to alias here. This wraps the raw text
 * directly, matching commons' new contract (verbatim JSON Schema text,
 * unsupported keywords rejected).
 */
public data class JsonSchema(
    val rawJson: String,
)

/** Declaration of a tool the model may call. */
public typealias ToolDefinition = ai.runanywhere.proto.v1.ToolDefinition

/** A tool invocation requested by the model. */
public typealias ToolCall = ai.runanywhere.proto.v1.ToolCall

/** The outcome of one executed tool call. */
public typealias ToolResult = ai.runanywhere.proto.v1.ToolResult

/** A single typed tool argument or return value. */
public typealias ToolValue = ai.runanywhere.proto.v1.ToolValue

/** Modality a model serves. */
public typealias ModelCategory = ai.runanywhere.proto.v1.ModelCategory

/** Backend engine that executes a model. */
public typealias InferenceFramework = ai.runanywhere.proto.v1.InferenceFramework

/** Cross-SDK name for [InferenceFramework], matching the v4 public API spec. */
public typealias Backend = InferenceFramework

/** Registry record for one model artifact. */
public typealias ModelInfo = ai.runanywhere.proto.v1.ModelInfo

/** A synthesizable voice offered by the loaded TTS model. */
public typealias Voice = ai.runanywhere.proto.v1.TTSVoiceInfo

/** Container or sample encoding of synthesized audio. */
public typealias AudioFormat = ai.runanywhere.proto.v1.AudioFormat

/** Control-plane environment the SDK talks to. */
public typealias Environment = ai.runanywhere.proto.v1.SDKEnvironment

/** Layout of an archived model artifact. */
public typealias ArchiveStructure = ai.runanywhere.proto.v1.ArchiveStructure

/** Compression format of an archived model artifact. */
public typealias ArchiveType = ai.runanywhere.proto.v1.ArchiveType

/** One file inside a multi-file model artifact. */
public typealias ModelFileDescriptor = ai.runanywhere.proto.v1.ModelFileDescriptor
