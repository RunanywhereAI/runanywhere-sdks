// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — public entry point for Swift.
//
// The 20-line developer API:
//
//     let session = try await RunAnywhere.solution(.voiceAgent(
//         llm: "qwen3-4b", stt: "whisper-base", tts: "kokoro"))
//     for try await event in session.run() {
//         switch event {
//         case .userSaid(let text):    transcript.append(.user(text))
//         case .assistantToken(let t): transcript.appendToken(t)
//         case .audio(let pcm):        player.enqueue(pcm)
//         case .interrupted:           player.flush()
//         case .error(let e):          onError(e)
//         }
//     }

import Foundation
import CRACommonsCore

@MainActor
public enum RunAnywhere {

    // MARK: - Public API

    /// Creates a `VoiceSession` from a solution config. Throws if:
    ///   - the required engines are not registered (static iOS) or cannot
    ///     be dlopen'd (macOS)
    ///   - the model files are not reachable via the model registry
    public static func solution(
        _ config: SolutionConfig
    ) async throws -> VoiceSession {
        try await VoiceSession.create(from: config)
    }

    // MARK: - Engine plugin registration (iOS/macOS static mode)

    /// Registers a static engine plugin. Called by application code at
    /// launch on iOS — iOS prohibits dlopen, so every plugin must be
    /// compiled into the XCFramework and registered explicitly.
    public static func configure(_ setup: (inout RegistrationBuilder) -> Void) {
        var b = RegistrationBuilder()
        setup(&b)
        b.apply()
    }

    /// Loads an engine plugin from a shared-library path. macOS only — iOS
    /// cannot dlopen, so iOS apps register plugins statically via
    /// `configure`. Returns true on success.
    ///
    /// Example:
    ///
    ///     RunAnywhere.loadPlugin(at: "/usr/local/lib/librunanywhere_llamacpp.dylib")
    @discardableResult
    public static func loadPlugin(at libraryPath: String) -> Bool {
        libraryPath.withCString { cstr in
            ra_registry_load_plugin(cstr) == Int32(RA_OK)
        }
    }

    /// Count of currently-registered engine plugins. Useful for tests that
    /// assert a plugin was loaded before creating a session.
    public static var registeredPluginCount: Int {
        Int(ra_registry_plugin_count())
    }
}

// MARK: - SolutionConfig

public enum SolutionConfig: Sendable {
    case voiceAgent(VoiceAgentConfig)
    case rag(RAGConfig)
    case wakeWord(WakeWordConfig)
}

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

public struct RAGConfig: Sendable {
    public var embedModel:  String
    public var rerankModel: String
    public var llm:         String
    public var vectorStorePath: String
    public var retrieveK:   Int
    public var rerankTop:   Int

    public init(
        embedModel:  String = "bge-small-en-v1.5",
        rerankModel: String = "bge-reranker-v2-m3",
        llm:         String = "qwen3-4b",
        vectorStorePath: String = "",
        retrieveK:  Int = 24,
        rerankTop:  Int = 6
    ) {
        self.embedModel       = embedModel
        self.rerankModel      = rerankModel
        self.llm              = llm
        self.vectorStorePath  = vectorStorePath
        self.retrieveK        = retrieveK
        self.rerankTop        = rerankTop
    }
}

public struct WakeWordConfig: Sendable {
    public var model:     String
    public var keyword:   String
    public var threshold: Float
    public var preRollMs: Int

    public init(
        model: String = "kws-zipformer-gigaspeech",
        keyword: String = "hey mycroft",
        threshold: Float = 0.5,
        preRollMs: Int = 250
    ) {
        self.model     = model
        self.keyword   = keyword
        self.threshold = threshold
        self.preRollMs = preRollMs
    }
}
