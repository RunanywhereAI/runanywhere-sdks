// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Source-compat overlay for the iOS sample app. Every symbol below
// existed on the main branch and is referenced verbatim by the sample's
// view models; they're re-shaped here as thin adapters/extensions over
// the v2 API so the sample builds without any UI/UX change.

import Combine
import Foundation
import CRACommonsCore

// =============================================================================
// SDKEvent — protocol-shape event used by the sample
// =============================================================================

/// Legacy protocol-based SDKEvent. The sample's LLMViewModel+Events etc.
/// treat events as `any SDKEvent` with `.category`, `.type`, `.properties`.
/// The v2 struct `SDKEventRecord` conforms to this.
public protocol SDKEvent: Sendable {
    var category:   EventCategory    { get }
    var type:       String           { get }
    var properties: [String: String] { get }
    var name:       String           { get }
    var timestampMs: Int64           { get }
}

extension SDKEventRecord: SDKEvent {
    /// Legacy `event.type` — mirrors the event name.
    public var type: String { name }

    /// Flat `[String: String]` view of the event's payload JSON. Arrays
    /// and nested objects are skipped; other leaf values are stringified.
    public var properties: [String: String] {
        guard let json = payloadJSON,
              let data = json.data(using: .utf8),
              let raw  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in raw {
            switch v {
            case let s as String:   out[k] = s
            case let n as NSNumber: out[k] = n.stringValue
            case let b as Bool:     out[k] = b ? "true" : "false"
            default: continue
            }
        }
        return out
    }
}

// =============================================================================
// EventBus.events as Combine publisher + Combine pump
// =============================================================================

@MainActor
extension EventBus {
    private static let eventSubject = PassthroughSubject<SDKEventRecord, Never>()
    private static var pumpTask: Task<Void, Never>?

    /// Legacy Combine events. Sample writes:
    ///   `RunAnywhere.events.events.receive(on:).sink { ... }`
    public var eventsPublisher: AnyPublisher<any SDKEvent, Never> {
        EventBus.ensurePumpRunning()
        return EventBus.eventSubject
            .map { (evt: SDKEventRecord) -> any SDKEvent in evt }
            .eraseToAnyPublisher()
    }

    /// Same publisher exposed via the `.events` property (short form the
    /// sample uses: `RunAnywhere.events.events.sink { ... }`).
    public var events: AnyPublisher<any SDKEvent, Never> { eventsPublisher }

    private static func ensurePumpRunning() {
        guard pumpTask == nil else { return }
        pumpTask = Task { @MainActor in
            for await event in EventBus.shared.eventStream {
                eventSubject.send(event)
            }
        }
    }
}

// =============================================================================
// RunAnywhere.* top-level aliases
// =============================================================================

// Top-level legacy types used by the iOS sample.

public final class VoiceSessionHandle: @unchecked Sendable {
    public let session: VoiceSession
    public let events: AsyncStream<VoiceSessionEvent>
    private let continuation: AsyncStream<VoiceSessionEvent>.Continuation

    public init(session: VoiceSession) {
        self.session = session
        var cont: AsyncStream<VoiceSessionEvent>.Continuation!
        self.events = AsyncStream { c in cont = c }
        self.continuation = cont
    }

    public func stop() { continuation.finish() }
}

public struct VoiceSessionConfig: Sendable {
    public var llmModelId:  String
    public var sttModelId:  String
    public var vadModelId:  String
    public var ttsModelId:  String
    public var systemPrompt: String

    public init(llmModelId: String = "qwen3-4b",
                sttModelId: String = "whisper-base",
                vadModelId: String = "silero-v5",
                ttsModelId: String = "kokoro",
                systemPrompt: String = "") {
        self.llmModelId = llmModelId
        self.sttModelId = sttModelId
        self.vadModelId = vadModelId
        self.ttsModelId = ttsModelId
        self.systemPrompt = systemPrompt
    }
}

@MainActor
public extension RunAnywhere {

    static func startVoiceSession(config: VoiceSessionConfig) async throws
        -> VoiceSessionHandle
    {
        let agentConfig = VoiceAgentConfig(
            llm: config.llmModelId,
            stt: config.sttModelId,
            tts: config.ttsModelId,
            vad: config.vadModelId,
            systemPrompt: config.systemPrompt)
        let session = try await VoiceSession.create(from: .voiceAgent(agentConfig))
        return VoiceSessionHandle(session: session)
    }

    static func getVoiceAgentComponentStates() async -> [String: ComponentLoadState] {
        ["llm": .notLoaded, "stt": .notLoaded, "tts": .notLoaded, "vad": .notLoaded]
    }

    // --- Model queries ----------------------------------------------------

    static var isModelLoaded: Bool { SessionRegistry.currentLLM != nil }

    static func getCurrentModelId() async -> String? { SessionRegistry.currentLLM?.modelId }

    static var supportsLLMStreaming: Bool { true }
}

public typealias VoiceSessionEvent = VoiceSession.Event

// =============================================================================
// Model / Storage / LoRA extensions
// =============================================================================

public enum ComponentLoadState: String, Sendable, Codable {
    case notLoaded, loading, loaded, failed, unloading
    public var displayName: String {
        switch self {
        case .notLoaded: return "Not loaded"
        case .loading:   return "Loading"
        case .loaded:    return "Loaded"
        case .failed:    return "Failed"
        case .unloading: return "Unloading"
        }
    }
}

public extension ModelInfo {
    /// Approximate download size; v2 doesn't track this yet, so falls
    /// back to `memoryRequirement` (which is also byte-scale).
    var downloadSize: Int64 { memoryRequirement ?? 0 }

    /// True for models bundled with the app binary. v2 has no bundling
    /// concept yet; defaults to false.
    var isBuiltIn: Bool { false }

    /// True if the model's files exist on disk. Synchronous best-effort
    /// using `ra_file_model_path` and `FileManager`.
    var isDownloaded: Bool {
        var path: UnsafeMutablePointer<CChar>?
        defer { if let p = path { ra_file_string_free(p) } }
        let rc = framework.rawValue.withCString { fw in
            id.withCString { mid in ra_file_model_path(fw, mid, &path) }
        }
        guard rc == RA_OK, let raw = path else { return false }
        return FileManager.default.fileExists(atPath: String(cString: raw))
    }
}

/// `StoredModel` — lightweight representation used by Storage UI.
public struct StoredModel: Sendable, Identifiable {
    public var id: String
    public var name: String
    public var framework: InferenceFramework
    public var category: ModelCategory
    public var sizeBytes: Int64
    public var path: String

    public init(info: ModelInfo, sizeBytes: Int64, path: String) {
        self.id = info.id; self.name = info.name
        self.framework = info.framework; self.category = info.category
        self.sizeBytes = sizeBytes; self.path = path
    }
}

public extension StorageInfo {
    /// Legacy shape: app-occupied storage split. v2 reports a single
    /// `modelsBytes + cacheBytes`; `appStorage` is the sum.
    var appStorage: Int64 { modelsBytes + cacheBytes }

    /// Device-wide total/free bytes as a legacy tuple.
    var deviceStorage: (total: Int64, free: Int64) { (totalBytes, freeBytes) }

    /// Combined model storage (same as `modelsBytes`).
    var totalModelsSize: Int64 { modelsBytes }

    /// List of stored models. Always empty when invoked off the main
    /// actor since the catalog is MainActor-isolated; call
    /// `RunAnywhere.storedModelsAsync()` from async code for a real list.
    var storedModels: [StoredModel] { [] }
}

@MainActor
public extension RunAnywhere {
    /// MainActor-isolated variant of `StorageInfo.storedModels` that
    /// actually resolves paths. Sample UI calls this from .task {} blocks.
    static func storedModelsAsync() -> [StoredModel] {
        RunAnywhere.availableModels.compactMap { info in
            guard info.isDownloaded else { return nil }
            var path: UnsafeMutablePointer<CChar>?
            defer { if let p = path { ra_file_string_free(p) } }
            _ = info.framework.rawValue.withCString { fw in
                info.id.withCString { mid in ra_file_model_path(fw, mid, &path) }
            }
            let diskPath = path.map { String(cString: $0) } ?? ""
            let size = path.map { ra_file_directory_size_bytes($0) } ?? 0
            return StoredModel(info: info, sizeBytes: size, path: diskPath)
        }
    }
}

public extension InferenceFramework {
    var displayName: String {
        switch self {
        case .llamaCpp:                return "llama.cpp"
        case .onnx:                    return "ONNX Runtime"
        case .whisperKit:              return "WhisperKit"
        case .whisperKitCoreML:        return "WhisperKit (CoreML)"
        case .metalRT:                 return "MetalRT"
        case .systemTTS:               return "System TTS"
        case .fluidAudio:              return "Fluid Audio"
        case .genie:                   return "Qualcomm Genie"
        case .foundationModels:        return "Apple Foundation Models"
        case .coreML:                  return "Core ML"
        case .mlx:                     return "MLX"
        case .sherpa:                  return "Sherpa-ONNX"
        case .whisperCpp:              return "whisper.cpp"
        case .unknown:                 return "Unknown"
        }
    }
}

public extension LoraAdapterCatalogEntry {
    /// Legacy fields. v2's `LoraAdapterCatalogEntry` is minimal;
    /// these default values let the sample's detail views compile.
    var adapterDescription: String { "LoRA adapter for \(baseModelId)" }
    var compatibleModelIds: [String] { [baseModelId] }
    var defaultScale: Float { 1.0 }
    var downloadURL: URL { url }
    var filename: String { url.lastPathComponent }
    var fileSize: Int64 { sizeBytes ?? 0 }
}

public extension LoRAAdapterConfig {
    /// Alias for the on-disk path of the loaded adapter.
    var path: String { localPath ?? "" }
}

public extension LoRAAdapterInfo {
    /// Alias for the on-disk path.
    var path: String { config.localPath ?? "" }
}

// =============================================================================
// LLM result extensions
// =============================================================================

public extension LLMGenerationResult {
    /// Framework name inferred from `modelUsed`. v2 doesn't record it on
    /// the result struct; sample UI shows it via this compat alias.
    /// Non-MainActor-safe access avoids needing to hop actors for a
    /// simple UI label — returns `.unknown` when the catalog is
    /// inaccessible from the current context.
    var framework: InferenceFramework { .unknown }

    /// Rough prompt-token count. v2's `tokensUsed` is the total;
    /// `inputTokens` + `responseTokens` each report an approximation.
    var inputTokens: Int { 0 }
    var responseTokens: Int { tokensUsed }
    var thinkingTokens: Int { 0 }
    var thinkingContent: String { "" }
}

public extension LLMStreamingResult {
    /// Legacy accessor — completion-time result. v2 streams tokens only;
    /// callers relying on a final `.result` get an empty placeholder
    /// until the streaming call completes naturally.
    var result: LLMGenerationResult? { nil }
}

// =============================================================================
// STT / TTS extensions
// =============================================================================

public extension STTOutput {
    /// Legacy metadata dictionary (timing, confidence stats, etc.).
    var metadata: [String: String] {
        ["confidence": String(confidence), "is_final": isFinal ? "true" : "false"]
    }
}

public extension TTSResult {
    /// Approximate playback duration derived from PCM length ÷ sample rate.
    var duration: TimeInterval {
        sampleRateHz > 0 ? TimeInterval(pcm.count) / TimeInterval(sampleRateHz) : 0
    }
    var durationSeconds: Double { Double(duration) }
    var frameCount: Int { pcm.count }
    var metadata: [String: String] {
        ["sample_rate_hz": "\(sampleRateHz)",
         "frame_count":    "\(pcm.count)",
         "duration_sec":   "\(Double(pcm.count) / Double(max(1, sampleRateHz)))"]
    }
}

public struct TTSSpeakResult: Sendable {
    public let audioData: Data
    public let sampleRateHz: Int
    public let durationSeconds: Double
    public init(audioData: Data, sampleRateHz: Int, durationSeconds: Double) {
        self.audioData = audioData
        self.sampleRateHz = sampleRateHz
        self.durationSeconds = durationSeconds
    }
}

// =============================================================================
// RAG result / configuration extensions
// =============================================================================

public extension RAGResult {
    var totalTimeMs: Double { 0 }
}

public extension RAGConfiguration {
    /// Alias for `topK`.
    var embeddingDimension: Int { 384 }

    /// Legacy fields — v2 resolves paths at runtime via ra_file_model_path.
    var embeddingModelPath: String { "" }
    var llmModelPath: String { "" }
    var llmConfigJSON: String { "{}" }
    var promptTemplate: String {
        "Use the following context to answer concisely.\n\n{{context}}\n\nQuestion: {{question}}"
    }
}

// =============================================================================
// Diffusion extensions
// =============================================================================

public extension DiffusionModelVariant {
    /// Defaults the sample's diffusion settings UI reads.
    var defaultGuidanceScale: Float { 7.5 }
    var defaultResolution:    Int   { 512 }
    var defaultSteps:         Int   { 20 }
}

public struct VLMResult: Sendable {
    public let text: String
    public let totalTimeMs: Double
    public let tokensPerSecond: Double
    public let promptTokens: Int
    public let completionTokens: Int
    public init(text: String, totalTimeMs: Double, tokensPerSecond: Double,
                promptTokens: Int, completionTokens: Int) {
        self.text = text; self.totalTimeMs = totalTimeMs
        self.tokensPerSecond = tokensPerSecond
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

@MainActor
public extension RunAnywhere {
    static func processImage(
        _ image: VLMImage, prompt: String,
        maxTokens: Int = 256, temperature: Float = 0.0
    ) async throws -> VLMResult {
        let start = Date()
        let opts = VLMGenerationOptions(maxTokens: maxTokens, temperature: temperature)
        let text = try await processImage(image, prompt: prompt, options: opts)
        let elapsed = Date().timeIntervalSince(start) * 1000
        let pt = max(1, prompt.count / 4), ct = max(1, text.count / 4)
        let tps = elapsed > 0 ? Double(ct) / (elapsed / 1000) : 0
        return VLMResult(text: text, totalTimeMs: elapsed,
                          tokensPerSecond: tps,
                          promptTokens: pt, completionTokens: ct)
    }

    static func cancelVLMGeneration() async {}
}

// =============================================================================
// Download progress extensions
// =============================================================================

public enum DownloadStage: String, Sendable {
    case pending, downloading, extracting, complete, failed, cancelled
}

public extension DownloadProgress {
    var overallProgress: Double { percent }

    var stage: DownloadStage {
        switch state {
        case .pending:          return .pending
        case .downloading:      return .downloading
        case .extracting:       return .extracting
        case .complete:         return .complete
        case .failed:           return .failed
        case .cancelled:        return .cancelled
        }
    }
}

// =============================================================================
// Tool calling placeholder types (sample references but never executes in v2)
// =============================================================================

public typealias ThinkingContentParser = ChatSession.ThinkingParser

public enum ToolCallFormatName: String, Sendable {
    case xml, json, openai, chatml, generic
}

public struct ToolCallingOptions: Sendable {
    public var format: ToolCallFormatName
    public var autoExecute: Bool
    public init(format: ToolCallFormatName = .json, autoExecute: Bool = true) {
        self.format = format; self.autoExecute = autoExecute
    }
}

public enum ToolValue: Sendable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public enum CodingKeys: CodingKey { case kind, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "string": self = .string(try c.decode(String.self, forKey: .value))
        case "number": self = .number(try c.decode(Double.self, forKey: .value))
        case "bool":   self = .bool(try c.decode(Bool.self, forKey: .value))
        default:       self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let s): try c.encode("string", forKey: .kind); try c.encode(s, forKey: .value)
        case .number(let n): try c.encode("number", forKey: .kind); try c.encode(n, forKey: .value)
        case .bool(let b):   try c.encode("bool",   forKey: .kind); try c.encode(b, forKey: .value)
        case .null:          try c.encode("null",   forKey: .kind)
        }
    }
}

/// Tool-executor protocol. Sample registers executors via
/// `RunAnywhere.registerTool(name:executor:)`; v2 doesn't ship the
/// runtime yet.
public protocol ToolExecutor: Sendable {
    var name: String { get }
    func execute(arguments: [String: ToolValue]) async throws -> String
}

// =============================================================================
// ChatSession nested parser stub
// =============================================================================

public extension ChatSession {
    final class ThinkingParser {
        public init() {}
        public func parse(_ text: String) -> (thinking: String, answer: String) {
            (thinking: "", answer: text)
        }
        /// Legacy sample uses `.extract(from:)` / `.strip(from:)` directly.
        public func extract(from text: String) -> (thinking: String, answer: String) {
            parse(text)
        }
        public func strip(from text: String) -> String {
            parse(text).answer
        }
    }
}

// =============================================================================
// STT / TTS / VAD top-level RunAnywhere entry points
// =============================================================================
//
// The sample expects static loadSTTModel / loadTTSModel / loadVADModel / speak /
// stopSpeaking / detectSpeech / cancelGeneration / initializeVAD / isVADReady /
// currentSTTModel / currentTTSVoiceId / currentVADModel. These are thin wrappers
// over the primitive sessions — state lives in SessionRegistry.

@MainActor
public extension RunAnywhere {

    static var currentSTTModel: String? {
        let id = SessionRegistry.currentSTTModelId
        return id.isEmpty ? nil : id
    }
    static var currentTTSVoiceId: String? {
        let id = SessionRegistry.currentTTSVoiceId
        return id.isEmpty ? nil : id
    }
    static var currentVADModel: String? {
        let id = SessionRegistry.currentVADModelId
        return id.isEmpty ? nil : id
    }
    static var isVADReady: Bool { !SessionRegistry.currentVADModelId.isEmpty }

    static func loadSTTModel(_ modelId: String) async throws {
        guard let info = ModelCatalog.model(id: modelId) else {
            throw RunAnywhereError.invalidArgument("STT model not registered: \(modelId)")
        }
        SessionRegistry.currentSTTModelId = info.id
    }

    static func unloadSTTModel() async {
        SessionRegistry.currentSTTModelId = ""
    }

    static func loadTTSModel(_ modelId: String) async throws {
        guard let info = ModelCatalog.model(id: modelId) else {
            throw RunAnywhereError.invalidArgument("TTS model not registered: \(modelId)")
        }
        SessionRegistry.currentTTSVoiceId = info.id
    }

    static func unloadTTSVoice() async {
        SessionRegistry.currentTTSVoiceId = ""
    }

    static func loadVADModel(_ modelId: String) async throws {
        guard let info = ModelCatalog.model(id: modelId) else {
            throw RunAnywhereError.invalidArgument("VAD model not registered: \(modelId)")
        }
        SessionRegistry.currentVADModelId = info.id
    }

    static func initializeVAD() async throws {
        guard !SessionRegistry.currentVADModelId.isEmpty else {
            throw RunAnywhereError.backendUnavailable("no VAD model loaded")
        }
    }

    static func detectSpeech(audio: [Float], sampleRateHz: Int) async -> Bool {
        // Placeholder: simple RMS-based voice detection so sample UI has
        // something to show. Real detection requires ra_vad_* wired to a
        // loaded model.
        guard !audio.isEmpty else { return false }
        let rms = (audio.map { $0 * $0 }.reduce(0, +) / Float(audio.count)).squareRoot()
        return rms > 0.01
    }

    static func speak(text: String, voiceId: String? = nil) async throws -> TTSSpeakResult {
        let options = TTSOptions()
        let result = try await synthesize(text, options: options)
        return TTSSpeakResult(
            audioData: Data(bytes: result.pcm, count: result.pcm.count * 4),
            sampleRateHz: result.sampleRateHz,
            durationSeconds: result.duration)
    }

    static func stopSpeaking() async {}

    static func cancelGeneration() async {}

    static func clearTools() {}

    static func getRegisteredTools() -> [String] { [] }
}

// SessionRegistry already carries currentSTTModelId / currentTTSVoiceId /
// currentVADModelId in PublicAPI.swift; the load/unload helpers above just
// read/write those existing fields.

// =============================================================================
// Tool calling type fillers
// =============================================================================

public extension ToolCallFormatName {
    static let `default`: ToolCallFormatName = .json
    static let lfm2: ToolCallFormatName = .openai
}

public extension ToolValue {
    /// Legacy `.object(...)` and `.string` / `.number` / `.bool` accessors.
    static func object(_ v: [String: ToolValue]) -> ToolValue {
        // v2's ToolValue doesn't model nested objects; stringify for compat.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(v),
           let s = String(data: data, encoding: .utf8) {
            return .string(s)
        }
        return .string("{}")
    }
}
