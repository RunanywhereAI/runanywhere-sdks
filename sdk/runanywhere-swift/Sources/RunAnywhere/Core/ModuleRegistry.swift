import Foundation
import os

// MARK: - Thread-Safe Model Info Cache

/// Thread-safe cache for model information that can be accessed from any isolation context
/// This allows providers to check model metadata without requiring MainActor isolation
/// Uses OSAllocatedUnfairLock (Swift 6 pattern) for efficient synchronization
public final class ModelInfoCache: Sendable {
    public static let shared = ModelInfoCache()

    private let state: OSAllocatedUnfairLock<[String: ModelInfo]>

    private init() {
        state = OSAllocatedUnfairLock(initialState: [:])
    }

    /// Cache model information for synchronous lookup by providers
    /// This should be called whenever models are loaded/updated
    public func cacheModels(_ models: [ModelInfo]) {
        state.withLock { cache in
            for model in models {
                cache[model.id] = model
            }
        }
    }

    /// Get cached model info for a given model ID
    /// Providers can use this to determine framework compatibility without async calls
    public func modelInfo(for modelId: String) -> ModelInfo? {
        state.withLock { cache in
            cache[modelId]
        }
    }

    /// Clear the model info cache
    public func clear() {
        state.withLock { cache in
            cache.removeAll()
        }
    }

    /// Check if a model exists in the cache
    public func contains(_ modelId: String) -> Bool {
        state.withLock { cache in
            cache[modelId] != nil
        }
    }
}

// MARK: - Module Registration System

/// Central registry for external AI module implementations
///
/// This allows optional dependencies to register their implementations
/// at runtime, enabling a plugin-based architecture where modules like
/// WhisperCPP, llama.cpp, and FluidAudioDiarization can be added as needed.
///
/// Example usage in your app:
/// ```swift
/// import RunAnywhere
/// import WhisperCPP  // Optional dependency
/// import LlamaCPP     // Optional dependency
///
/// // In your app initialization:
/// ModuleRegistry.shared.registerSTT(WhisperSTTProvider())
/// ModuleRegistry.shared.registerLLM(LlamaProvider())
/// ```
@MainActor
public final class ModuleRegistry {
    // MARK: - Singleton

    public static let shared = ModuleRegistry()

    // MARK: - Properties

    /// Internal structure to track providers with their priorities
    private struct PrioritizedProvider<Provider> {
        let provider: Provider
        let priority: Int
    }

    private var sttProviders: [PrioritizedProvider<STTServiceProvider>] = []
    private var llmProviders: [PrioritizedProvider<LLMServiceProvider>] = []
    private var ttsProviders: [PrioritizedProvider<TTSServiceProvider>] = []
    private var speakerDiarizationProviders: [SpeakerDiarizationServiceProvider] = []

    private init() {}

    // MARK: - Registration Methods

    /// Register a Speech-to-Text provider with optional priority (e.g., WhisperCPP)
    /// Higher priority providers are preferred (default: 100)
    public func registerSTT(_ provider: STTServiceProvider, priority: Int = 100) {
        let prioritizedProvider = PrioritizedProvider(provider: provider, priority: priority)
        sttProviders.append(prioritizedProvider)
        // Sort by priority (higher first)
        sttProviders.sort { lhs, rhs in
            lhs.priority > rhs.priority
        }
        print("[ModuleRegistry] Registered STT provider: \(provider.name) with priority: \(priority)")
    }

    /// Register a Language Model provider with optional priority (e.g., llama.cpp)
    /// Higher priority providers are preferred (default: 100)
    public func registerLLM(_ provider: LLMServiceProvider, priority: Int = 100) {
        let prioritizedProvider = PrioritizedProvider(provider: provider, priority: priority)
        llmProviders.append(prioritizedProvider)
        // Sort by priority (higher first)
        llmProviders.sort { lhs, rhs in
            lhs.priority > rhs.priority
        }
        print("[ModuleRegistry] Registered LLM provider: \(provider.name) with priority: \(priority)")
    }

    /// Register a Text-to-Speech provider with optional priority (e.g., ONNX TTS)
    /// Higher priority providers are preferred (default: 100)
    public func registerTTS(_ provider: TTSServiceProvider, priority: Int = 100) {
        let prioritizedProvider = PrioritizedProvider(provider: provider, priority: priority)
        ttsProviders.append(prioritizedProvider)
        // Sort by priority (higher first)
        ttsProviders.sort { lhs, rhs in
            lhs.priority > rhs.priority
        }
        print("[ModuleRegistry] Registered TTS provider: \(provider.name) with priority: \(priority)")
    }

    /// Register a Speaker Diarization provider (e.g., FluidAudioDiarization)
    public func registerSpeakerDiarization(_ provider: SpeakerDiarizationServiceProvider) {
        speakerDiarizationProviders.append(provider)
        print("[ModuleRegistry] Registered Speaker Diarization provider: \(provider.name)")
    }

    // MARK: - Provider Access

    /// Get an STT provider for the specified model (returns highest priority match)
    public func sttProvider(for modelId: String? = nil) -> STTServiceProvider? {
        if let modelId = modelId {
            return sttProviders.first(where: { $0.provider.canHandle(modelId: modelId) })?.provider
        }
        return sttProviders.first?.provider
    }

    /// Get ALL STT providers that can handle the specified model (sorted by priority)
    public func allSTTProviders(for modelId: String? = nil) -> [STTServiceProvider] {
        if let modelId = modelId {
            return sttProviders.filter { $0.provider.canHandle(modelId: modelId) }.map { $0.provider }
        }
        return sttProviders.map { $0.provider }
    }

    /// Get an LLM provider for the specified model (returns highest priority match)
    public func llmProvider(for modelId: String? = nil) -> LLMServiceProvider? {
        if let modelId = modelId {
            return llmProviders.first(where: { $0.provider.canHandle(modelId: modelId) })?.provider
        }
        return llmProviders.first?.provider
    }

    /// Get ALL LLM providers that can handle the specified model (sorted by priority)
    public func allLLMProviders(for modelId: String? = nil) -> [LLMServiceProvider] {
        if let modelId = modelId {
            return llmProviders.filter { $0.provider.canHandle(modelId: modelId) }.map { $0.provider }
        }
        return llmProviders.map { $0.provider }
    }

    /// Get a TTS provider for the specified model (returns highest priority match)
    public func ttsProvider(for modelId: String? = nil) -> TTSServiceProvider? {
        if let modelId = modelId {
            return ttsProviders.first(where: { $0.provider.canHandle(modelId: modelId) })?.provider
        }
        return ttsProviders.first?.provider
    }

    /// Get ALL TTS providers that can handle the specified model (sorted by priority)
    public func allTTSProviders(for modelId: String? = nil) -> [TTSServiceProvider] {
        if let modelId = modelId {
            return ttsProviders.filter { $0.provider.canHandle(modelId: modelId) }.map { $0.provider }
        }
        return ttsProviders.map { $0.provider }
    }

    /// Get a Speaker Diarization provider
    public func speakerDiarizationProvider(for modelId: String? = nil) -> SpeakerDiarizationServiceProvider? {
        if let modelId = modelId {
            return speakerDiarizationProviders.first { $0.canHandle(modelId: modelId) }
        }
        return speakerDiarizationProviders.first
    }

    // MARK: - Availability Checking

    /// Check if STT is available
    public var hasSTT: Bool { !sttProviders.isEmpty }

    /// Check if LLM is available
    public var hasLLM: Bool { !llmProviders.isEmpty }

    /// Check if TTS is available
    public var hasTTS: Bool { !ttsProviders.isEmpty }

    /// Check if Speaker Diarization is available
    public var hasSpeakerDiarization: Bool { !speakerDiarizationProviders.isEmpty }

    /// Get list of all registered modules
    public var registeredModules: [String] {
        var modules: [String] = []
        if hasSTT { modules.append("STT") }
        if hasLLM { modules.append("LLM") }
        if hasTTS { modules.append("TTS") }
        if hasSpeakerDiarization { modules.append("SpeakerDiarization") }
        return modules
    }
}

// MARK: - Service Provider Protocols

// Service provider protocols are defined in their respective component files:
// - STTServiceProvider in STTComponent.swift
// - LLMServiceProvider in LLMComponent.swift
// - TTSServiceProvider and SpeakerDiarizationServiceProvider defined below

/// Provider for Text-to-Speech services
public protocol TTSServiceProvider {
    func createTTSService(configuration: TTSConfiguration) async throws -> TTSService
    func canHandle(modelId: String?) -> Bool
    var name: String { get }
    var version: String { get }
}

/// Provider for Speaker Diarization services
public protocol SpeakerDiarizationServiceProvider {
    func createSpeakerDiarizationService(configuration: SpeakerDiarizationConfiguration) async throws -> SpeakerDiarizationService
    func canHandle(modelId: String?) -> Bool
    var name: String { get }
}


// MARK: - SDK Component Extension
// Note: SDKComponent.wakeWord is now defined in the enum itself

// MARK: - Module Auto-Registration

/// Protocol for modules that can auto-register themselves
public protocol AutoRegisteringModule {
    static func register()
}

/// Example implementation for external modules:
/// ```swift
/// // In WhisperCPP module
/// public struct WhisperModule: AutoRegisteringModule {
///     public static func register() {
///         ModuleRegistry.shared.registerSTT(WhisperSTTProvider())
///     }
/// }
/// ```
