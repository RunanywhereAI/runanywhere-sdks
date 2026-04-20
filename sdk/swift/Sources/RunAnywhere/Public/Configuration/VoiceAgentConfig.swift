// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation

public struct VoiceAgentConfig: Sendable {
    public var llm: String
    public var stt: String
    public var tts: String
    public var vad: String
    public var sampleRateHz: Int
    public var chunkMilliseconds: Int
    public var enableBargeIn: Bool
    public var emitPartials: Bool
    public var emitThoughts: Bool
    public var systemPrompt: String
    public var maxContextTokens: Int
    public var temperature: Float

    public init(
        llm: String              = "qwen3-4b",
        stt: String              = "whisper-base",
        tts: String              = "kokoro",
        vad: String              = "silero-v5",
        sampleRateHz: Int        = 16000,
        chunkMilliseconds: Int   = 20,
        enableBargeIn: Bool      = true,
        emitPartials: Bool       = true,
        emitThoughts: Bool       = false,
        systemPrompt: String     = "",
        maxContextTokens: Int    = 4096,
        temperature: Float       = 0.7
    ) {
        self.llm              = llm
        self.stt              = stt
        self.tts              = tts
        self.vad              = vad
        self.sampleRateHz     = sampleRateHz
        self.chunkMilliseconds = chunkMilliseconds
        self.enableBargeIn    = enableBargeIn
        self.emitPartials     = emitPartials
        self.emitThoughts     = emitThoughts
        self.systemPrompt     = systemPrompt
        self.maxContextTokens = maxContextTokens
        self.temperature      = temperature
    }
}
