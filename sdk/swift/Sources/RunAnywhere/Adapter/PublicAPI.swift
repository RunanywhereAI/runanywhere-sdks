// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Canonical RunAnywhere top-level public API — the methods the sample
// apps call directly. Implements the implicit-model surface
// (`initialize / loadModel / chat / generate / generateStream /
// transcribe / synthesize / registerTool / generateWithTools /
// generateStructured / shutdown`) on top of the session classes.
//
// Internally this maintains a process-wide "current" LLM/STT/TTS session
// (`SessionRegistry`) so callers don't need to thread a session handle
// through every call site. For multi-session apps, use the LLMSession /
// STTSession / TTSSession / VLMSession / DiffusionSession classes
// directly — they have no dependency on the registry.

import Foundation

// MARK: - Option / result types matching legacy shapes

public struct LLMGenerationOptions: Sendable {
    public var maxTokens: Int
    public var temperature: Float
    public var topP: Float
    public var stopSequences: [String]
    public var streamingEnabled: Bool
    public var systemPrompt: String?

    public init(maxTokens: Int = 512, temperature: Float = 0.8,
                topP: Float = 1.0, stopSequences: [String] = [],
                streamingEnabled: Bool = false, systemPrompt: String? = nil) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stopSequences = stopSequences
        self.streamingEnabled = streamingEnabled
        self.systemPrompt = systemPrompt
    }
}

public struct LLMGenerationResult: Sendable {
    public let text: String
    public let tokensUsed: Int
    public let modelUsed: String
    public let latencyMs: TimeInterval
    public let tokensPerSecond: Double

    public init(text: String, tokensUsed: Int = 0, modelUsed: String = "",
                latencyMs: TimeInterval = 0, tokensPerSecond: Double = 0) {
        self.text = text; self.tokensUsed = tokensUsed
        self.modelUsed = modelUsed; self.latencyMs = latencyMs
        self.tokensPerSecond = tokensPerSecond
    }
}

public struct LLMStreamingResult: Sendable {
    public let stream: AsyncThrowingStream<String, Error>
    public init(stream: AsyncThrowingStream<String, Error>) { self.stream = stream }
}

public struct STTOptions: Sendable {
    public var language: String
    public var enablePartials: Bool
    public init(language: String = "en", enablePartials: Bool = true) {
        self.language = language; self.enablePartials = enablePartials
    }
}

public struct STTOutput: Sendable {
    public let text: String
    public let isFinal: Bool
    public let confidence: Float
    public init(text: String, isFinal: Bool = true, confidence: Float = 1.0) {
        self.text = text; self.isFinal = isFinal; self.confidence = confidence
    }
}

public struct TTSOptions: Sendable {
    public var voice: String
    public var speakingRate: Float
    public init(voice: String = "default", speakingRate: Float = 1.0) {
        self.voice = voice; self.speakingRate = speakingRate
    }
}

public struct TTSResult: Sendable {
    public let pcm: [Float]
    public let sampleRateHz: Int
    public init(pcm: [Float], sampleRateHz: Int) {
        self.pcm = pcm; self.sampleRateHz = sampleRateHz
    }
}

public typealias SDKEnvironment = SDKState.Environment

// MARK: - Implicit-session registry

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

// MARK: - RunAnywhere legacy surface

public extension RunAnywhere {

    // --- SDK lifecycle ------------------------------------------------------

    static func initialize(apiKey: String,
                            baseURL: String? = nil,
                            environment: SDKEnvironment = .production,
                            deviceId: String? = nil,
                            logLevel: SDKState.LogLevel = .info) throws {
        try SDKState.initialize(apiKey: apiKey,
                                 environment: environment,
                                 baseUrl: baseURL,
                                 deviceId: deviceId,
                                 logLevel: logLevel)
    }

    /// No-argument initializer — used by the iOS sample's DEBUG bootstrap.
    /// Starts the SDK in development mode with a local-dev placeholder API
    /// key. Cloud features (telemetry upload, model assignment) are not
    /// usable in this mode; on-device inference works normally.
    ///
    /// The placeholder key is ≥16 chars to satisfy the core validator.
    /// Production code must call `initialize(apiKey:baseURL:environment:)`
    /// with real credentials.
    static func initialize() throws {
        try SDKState.initialize(
            apiKey: "dev-local-00000000",
            environment: .development,
            baseUrl: nil,
            deviceId: nil,
            logLevel: .info)
    }

    static var isSDKInitialized: Bool { SDKState.isInitialized }
    static var isActive: Bool        { SDKState.isInitialized }
    static var version: String       { "2.0.0" }

    /// Current SDK environment, nil when not yet initialized.
    /// Preferred name: `currentEnvironment`. Legacy name `environment`
    /// kept for sample-app call-site compatibility.
    static var currentEnvironment: SDKEnvironment? {
        SDKState.isInitialized ? SDKState.environment : nil
    }

    /// Legacy alias of `currentEnvironment`. Returns the environment raw
    /// value or nil when not yet initialized.
    static var environment: SDKEnvironment? { currentEnvironment }

    static func shutdown() { SDKState.shutdown() }

    // --- LLM: chat / generate / generateStream -----------------------------

    /// Load a model by id + path. Required once before calling
    /// `chat / generate / generateStream`.
    static func loadModel(_ modelId: String, modelPath: String,
                           format: ModelFormat = .gguf) throws {
        let session = try LLMSession(modelId: modelId, modelPath: modelPath,
                                      config: .init())
        SessionRegistry.currentLLM = session
        SessionRegistry.currentLLMChat = nil  // lazy-init on first chat
        SessionRegistry.currentModelId = modelId
        SessionRegistry.currentModelPath = modelPath
    }

    static func unloadModel() {
        SessionRegistry.currentLLM = nil
        SessionRegistry.currentLLMChat = nil
        SessionRegistry.currentModelId = ""
        SessionRegistry.currentModelPath = ""
    }

    static func getCurrentModelId() -> String {
        SessionRegistry.currentModelId.isEmpty
            ? "" : SessionRegistry.currentModelId
    }

    @discardableResult
    static func chat(_ prompt: String,
                      options: LLMGenerationOptions = .init()) async throws -> String {
        let chat = try ensureChatSession(systemPrompt: options.systemPrompt)
        return try await chat.generateText(messages: [.user(prompt)])
    }

    @discardableResult
    static func generate(_ prompt: String,
                          options: LLMGenerationOptions = .init()) async throws
        -> LLMGenerationResult
    {
        let start = Date()
        let llm = try requireLLM()
        var tokenCount = 0
        var buf = ""
        for try await token in llm.generate(prompt: prompt) {
            if token.kind == .answer { buf += token.text }
            tokenCount += 1
        }
        let elapsed = Date().timeIntervalSince(start) * 1000
        let tps = elapsed > 0 ? Double(tokenCount) / (elapsed / 1000) : 0
        return LLMGenerationResult(
            text: buf,
            tokensUsed: tokenCount,
            modelUsed: SessionRegistry.currentModelId,
            latencyMs: elapsed,
            tokensPerSecond: tps)
    }

    static func generateStream(_ prompt: String,
                                 options: LLMGenerationOptions = .init()) async throws
        -> LLMStreamingResult
    {
        let llm = try requireLLM()
        let raw = llm.generate(prompt: prompt)
        let textStream = AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    for try await token in raw {
                        if token.kind == .answer { continuation.yield(token.text) }
                        if token.isFinal { continuation.finish(); return }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        return LLMStreamingResult(stream: textStream)
    }

    // --- STT -----------------------------------------------------------------

    static func loadSTT(_ modelId: String, modelPath: String,
                         format: ModelFormat = .whisperKit) throws {
        let session = try STTSession(modelId: modelId, modelPath: modelPath,
                                       format: format)
        SessionRegistry.currentSTT = session
    }

    static func transcribe(_ audioData: Data,
                            sampleRateHz: Int = 16000) async throws -> String {
        let session = try requireSTT()
        let samples = audioData.withUnsafeBytes { raw -> [Float] in
            guard raw.count % MemoryLayout<Int16>.size == 0 else { return [] }
            let count = raw.count / MemoryLayout<Int16>.size
            var out = [Float](); out.reserveCapacity(count)
            raw.bindMemory(to: Int16.self).forEach { out.append(Float($0) / 32768.0) }
            return out
        }
        try session.feedAudio(samples: samples, sampleRateHz: sampleRateHz)
        try session.flush()
        var text = ""
        for try await chunk in session.transcripts where !chunk.isPartial {
            text += chunk.text
            break
        }
        return text
    }

    static func transcribeWithOptions(_ audioData: Data,
                                        options: STTOptions = .init(),
                                        sampleRateHz: Int = 16000) async throws
        -> STTOutput
    {
        let text = try await transcribe(audioData, sampleRateHz: sampleRateHz)
        return STTOutput(text: text, isFinal: true, confidence: 1.0)
    }

    // --- TTS -----------------------------------------------------------------

    static func loadTTS(_ modelId: String, modelPath: String,
                         format: ModelFormat = .onnx) throws {
        let session = try TTSSession(modelId: modelId, modelPath: modelPath,
                                       format: format)
        SessionRegistry.currentTTS = session
    }

    static func synthesize(_ text: String,
                            options: TTSOptions = .init()) async throws -> TTSResult {
        let session = try requireTTS()
        let (pcm, sr) = try session.synthesize(text)
        return TTSResult(pcm: pcm, sampleRateHz: sr)
    }

    // --- Tool calling --------------------------------------------------------

    static func registerTool(_ definition: ToolDefinition,
                              executor: @escaping @Sendable ([String: Any]) async throws -> String) {
        SessionRegistry.registeredTools.append(definition)
        SessionRegistry.toolExecutors[definition.name] = executor
    }

    static func generateWithTools(_ prompt: String,
                                    options: LLMGenerationOptions = .init()) async throws
        -> LLMGenerationResult
    {
        guard !SessionRegistry.currentModelId.isEmpty else {
            throw RunAnywhereError.backendUnavailable("no model loaded")
        }
        let agent = try ToolCallingAgent(
            modelId: SessionRegistry.currentModelId,
            modelPath: SessionRegistry.currentModelPath,
            tools: SessionRegistry.registeredTools,
            systemPrompt: options.systemPrompt ?? "")

        var remaining = 4
        var lastReply = try await agent.send(userMessage: prompt)
        while remaining > 0 {
            switch lastReply {
            case .assistant(let text):
                return LLMGenerationResult(text: text,
                                             modelUsed: SessionRegistry.currentModelId)
            case .toolCalls(let calls):
                var results: [(String, String)] = []
                for call in calls {
                    if let exec = SessionRegistry.toolExecutors[call.name] {
                        let r = (try? await exec(call.arguments)) ?? "error"
                        results.append((call.name, r))
                    }
                }
                lastReply = try await agent.continueAfter(toolResults: results)
                remaining -= 1
            }
        }
        throw RunAnywhereError.internalError("tool-calling agent loop exceeded")
    }

    static func generateStructured<T: Decodable>(
        _ schema: T.Type,
        prompt: String,
        options: LLMGenerationOptions = .init()
    ) async throws -> T {
        let chat = try ensureChatSession(systemPrompt: options.systemPrompt)
        return try await StructuredOutput.generate(
            from: chat, query: prompt, schema: schema)
    }

    // --- Helpers -------------------------------------------------------------

    private static func requireLLM() throws -> LLMSession {
        guard let s = SessionRegistry.currentLLM else {
            throw RunAnywhereError.backendUnavailable(
                "no LLM loaded — call RunAnywhere.loadModel(_:modelPath:) first")
        }
        return s
    }

    private static func requireSTT() throws -> STTSession {
        guard let s = SessionRegistry.currentSTT else {
            throw RunAnywhereError.backendUnavailable(
                "no STT loaded — call RunAnywhere.loadSTT(_:modelPath:) first")
        }
        return s
    }

    private static func requireTTS() throws -> TTSSession {
        guard let s = SessionRegistry.currentTTS else {
            throw RunAnywhereError.backendUnavailable(
                "no TTS loaded — call RunAnywhere.loadTTS(_:modelPath:) first")
        }
        return s
    }

    private static func ensureChatSession(systemPrompt: String?) throws -> ChatSession {
        if let existing = SessionRegistry.currentLLMChat { return existing }
        guard !SessionRegistry.currentModelId.isEmpty else {
            throw RunAnywhereError.backendUnavailable(
                "no model loaded — call RunAnywhere.loadModel first")
        }
        let chat = try ChatSession(
            modelId: SessionRegistry.currentModelId,
            modelPath: SessionRegistry.currentModelPath,
            systemPrompt: systemPrompt)
        SessionRegistry.currentLLMChat = chat
        return chat
    }
}
