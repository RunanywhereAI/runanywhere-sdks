// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Singleton that tracks the "current" sessions per modality. Uses the
// MainActor so consumers can access it without explicit locking — every
// sample-app call path is already main-actor bound.

import Foundation

@MainActor
internal enum SessionRegistry {
    static var currentLLM: LLMSession?
    static var currentLLMChat: ChatSession?
    static var currentSTT: STTSession?
    static var currentTTS: TTSSession?
    static var currentVAD: VADSession?
    static var currentEmbed: EmbedSession?
    static var currentModelId: String = ""
    static var currentModelPath: String = ""
    static var currentSTTModelId: String = ""
    static var currentTTSVoiceId: String = ""
    static var currentVADModelId: String = ""
    static var currentVLMModelId: String = ""
    static var currentDiffusionModelId: String = ""
    static var registeredTools: [ToolDefinition] = []
    static var toolExecutors: [String: @Sendable ([String: Any]) async throws -> String] = [:]
}
