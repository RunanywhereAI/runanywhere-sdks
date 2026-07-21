/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Cross-platform RA-prefix typealiases mirroring Swift's RunAnywhere SDK public type names.
 * Lets Kotlin call-sites read like Swift sources for the on-device AI architecture.
 *
 * Each alias resolves to the Wire-generated proto type under
 * `ai.runanywhere.proto.v1.*` so there is exactly one source of truth (idl/proto files).
 * Adopting these aliases is a separate task — this file only declares them.
 */

package com.runanywhere.sdk.public.types

// ─── LLM ────────────────────────────────────────────────────────────────────

public typealias RALLMGenerationOptions = ai.runanywhere.proto.v1.LLMGenerationOptions
public typealias RALLMGenerationResult = ai.runanywhere.proto.v1.LLMGenerationResult
public typealias RALLMGenerateRequest = ai.runanywhere.proto.v1.LLMGenerateRequest
public typealias RALLMStreamEvent = ai.runanywhere.proto.v1.LLMStreamEvent
public typealias RAThinkingTagPattern = ai.runanywhere.proto.v1.ThinkingTagPattern
public typealias RAExecutionTarget = ai.runanywhere.proto.v1.ExecutionTarget
public typealias RAToolDefinition = ai.runanywhere.proto.v1.ToolDefinition
public typealias RAToolCall = ai.runanywhere.proto.v1.ToolCall
public typealias RAToolResult = ai.runanywhere.proto.v1.ToolResult
public typealias RAJSONSchema = ai.runanywhere.proto.v1.JSONSchema
public typealias RAStructuredOutputResult = ai.runanywhere.proto.v1.StructuredOutputResult
public typealias RAEmbeddingsResult = ai.runanywhere.proto.v1.EmbeddingsResult
public typealias RALoRAApplyRequest = ai.runanywhere.proto.v1.LoRAApplyRequest
public typealias RALoRARemoveRequest = ai.runanywhere.proto.v1.LoRARemoveRequest
public typealias RALoRAState = ai.runanywhere.proto.v1.LoRAState
public typealias RALoRAAdapterConfig = ai.runanywhere.proto.v1.LoRAAdapterConfig

// ─── Audio (STT / TTS / VAD) ────────────────────────────────────────────────

public typealias RASTTOutput = ai.runanywhere.proto.v1.STTOutput
public typealias RASTTOptions = ai.runanywhere.proto.v1.STTOptions
public typealias RATTSOptions = ai.runanywhere.proto.v1.TTSOptions
public typealias RATTSOutput = ai.runanywhere.proto.v1.TTSOutput
public typealias RAVADOptions = ai.runanywhere.proto.v1.VADOptions
public typealias RAVADResult = ai.runanywhere.proto.v1.VADResult
public typealias RAVoiceAgentComposeConfig = ai.runanywhere.proto.v1.VoiceAgentComposeConfig
public typealias RAVoiceEvent = ai.runanywhere.proto.v1.VoiceEvent
public typealias RAVoiceAgentComponentStates = ai.runanywhere.proto.v1.VoiceAgentComponentStates

// ─── VLM ────────────────────────────────────────────────────────────────────

public typealias RAVLMImage = ai.runanywhere.proto.v1.VLMImage
public typealias RAVLMResult = ai.runanywhere.proto.v1.VLMResult
public typealias RAVLMGenerationOptions = ai.runanywhere.proto.v1.VLMGenerationOptions
public typealias RAVLMStreamEvent = ai.runanywhere.proto.v1.VLMStreamEvent
public typealias RAVLMStreamEventKind = ai.runanywhere.proto.v1.VLMStreamEventKind

// ─── Diffusion / Inpainting ─────────────────────────────────────────────────

public typealias RADiffusionGenerationOptions = ai.runanywhere.proto.v1.DiffusionGenerationOptions
public typealias RADiffusionGenerationRequest = ai.runanywhere.proto.v1.DiffusionGenerationRequest
public typealias RADiffusionResult = ai.runanywhere.proto.v1.DiffusionResult
public typealias RADiffusionMode = ai.runanywhere.proto.v1.DiffusionMode

// Semantic Segmentation
public typealias RASegmentationPixelFormat = ai.runanywhere.proto.v1.SegmentationPixelFormat
public typealias RASegmentationImage = ai.runanywhere.proto.v1.SegmentationImage
public typealias RASegmentationOptions = ai.runanywhere.proto.v1.SegmentationOptions
public typealias RASegmentationRequest = ai.runanywhere.proto.v1.SegmentationRequest
public typealias RASegmentationClassSummary = ai.runanywhere.proto.v1.SegmentationClassSummary
public typealias RASegmentationResult = ai.runanywhere.proto.v1.SegmentationResult

// Speaker Diarization
public typealias RADiarizationAudioEncoding = ai.runanywhere.proto.v1.DiarizationAudioEncoding
public typealias RADiarizationOptions = ai.runanywhere.proto.v1.DiarizationOptions
public typealias RADiarizationRequest = ai.runanywhere.proto.v1.DiarizationRequest
public typealias RADiarizationSegment = ai.runanywhere.proto.v1.DiarizationSegment
public typealias RADiarizationResult = ai.runanywhere.proto.v1.DiarizationResult
public typealias RADiarizationStreamEvent = ai.runanywhere.proto.v1.DiarizationStreamEvent
public typealias RADiarizationStreamEventKind = ai.runanywhere.proto.v1.DiarizationStreamEventKind

// ─── RAG ────────────────────────────────────────────────────────────────────

public typealias RARAGConfiguration = ai.runanywhere.proto.v1.RAGConfiguration
public typealias RARAGStatistics = ai.runanywhere.proto.v1.RAGStatistics
public typealias RARAGDocument = ai.runanywhere.proto.v1.RAGDocument

// ─── Models / Storage / Hardware / Errors ───────────────────────────────────

public typealias RAModelInfo = ai.runanywhere.proto.v1.ModelInfo
public typealias RAModelLoadRequest = ai.runanywhere.proto.v1.ModelLoadRequest
public typealias RAModelLoadResult = ai.runanywhere.proto.v1.ModelLoadResult
public typealias RAModelCategory = ai.runanywhere.proto.v1.ModelCategory
public typealias RAModelFormat = ai.runanywhere.proto.v1.ModelFormat
public typealias RAModelSource = ai.runanywhere.proto.v1.ModelSource
public typealias RAInferenceFramework = ai.runanywhere.proto.v1.InferenceFramework
public typealias RAArchiveType = ai.runanywhere.proto.v1.ArchiveType
public typealias RAArchiveStructure = ai.runanywhere.proto.v1.ArchiveStructure
public typealias RAStorageInfo = ai.runanywhere.proto.v1.StorageInfo
public typealias RAHardwareProfile = ai.runanywhere.proto.v1.HardwareProfile
public typealias RAAcceleratorInfo = ai.runanywhere.proto.v1.AcceleratorInfo
public typealias RAAccelerationPreference = ai.runanywhere.proto.v1.AccelerationPreference
public typealias RASDKError = ai.runanywhere.proto.v1.SDKError
