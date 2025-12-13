import Foundation

/// Central registry for external AI module implementations
///
/// This allows optional dependencies to register their implementations
/// at runtime, enabling a plugin-based architecture where modules like
/// WhisperCPP, llama.cpp, and FluidAudioDiarization can be added as needed.
///
/// Example:
/// ```swift
/// import RunAnywhere
/// import WhisperCPP
///
/// ModuleRegistry.shared.registerSTT(WhisperSTTProvider())
/// ModuleRegistry.shared.registerLLM(LlamaProvider())
/// ```
@MainActor
public final class ModuleRegistry {
    public static let shared = ModuleRegistry()

    private struct PrioritizedProvider<Provider> {
        let provider: Provider
        let priority: Int
    }

    private var sttProviders: [PrioritizedProvider<STTServiceProvider>] = []
    private var llmProviders: [PrioritizedProvider<LLMServiceProvider>] = []
    private var ttsProviders: [PrioritizedProvider<TTSServiceProvider>] = []
    private var speakerDiarizationProviders: [SpeakerDiarizationServiceProvider] = []

    private init() {}

    // MARK: - Registration

    /// Register a Speech-to-Text provider (higher priority = preferred)
    public func registerSTT(_ provider: STTServiceProvider, priority: Int = 100) {
        sttProviders.append(PrioritizedProvider(provider: provider, priority: priority))
        sttProviders.sort { $0.priority > $1.priority }
        print("[ModuleRegistry] Registered STT provider: \(provider.name) with priority: \(priority)")
    }

    /// Register a Language Model provider (higher priority = preferred)
    public func registerLLM(_ provider: LLMServiceProvider, priority: Int = 100) {
        llmProviders.append(PrioritizedProvider(provider: provider, priority: priority))
        llmProviders.sort { $0.priority > $1.priority }
        print("[ModuleRegistry] Registered LLM provider: \(provider.name) with priority: \(priority)")
    }

    /// Register a Text-to-Speech provider (higher priority = preferred)
    public func registerTTS(_ provider: TTSServiceProvider, priority: Int = 100) {
        ttsProviders.append(PrioritizedProvider(provider: provider, priority: priority))
        ttsProviders.sort { $0.priority > $1.priority }
        print("[ModuleRegistry] Registered TTS provider: \(provider.name) with priority: \(priority)")
    }

    /// Register a Speaker Diarization provider
    public func registerSpeakerDiarization(_ provider: SpeakerDiarizationServiceProvider) {
        speakerDiarizationProviders.append(provider)
        print("[ModuleRegistry] Registered Speaker Diarization provider: \(provider.name)")
    }

    // MARK: - Provider Access

    /// Get highest priority STT provider for the specified model
    public func sttProvider(for modelId: String? = nil) -> STTServiceProvider? {
        if let modelId = modelId {
            return sttProviders.first { $0.provider.canHandle(modelId: modelId) }?.provider
        }
        return sttProviders.first?.provider
    }

    /// Get all STT providers that can handle the specified model (sorted by priority)
    public func allSTTProviders(for modelId: String? = nil) -> [STTServiceProvider] {
        if let modelId = modelId {
            return sttProviders.filter { $0.provider.canHandle(modelId: modelId) }.map { $0.provider }
        }
        return sttProviders.map { $0.provider }
    }

    /// Get highest priority LLM provider for the specified model
    public func llmProvider(for modelId: String? = nil) -> LLMServiceProvider? {
        if let modelId = modelId {
            return llmProviders.first { $0.provider.canHandle(modelId: modelId) }?.provider
        }
        return llmProviders.first?.provider
    }

    /// Get all LLM providers that can handle the specified model (sorted by priority)
    public func allLLMProviders(for modelId: String? = nil) -> [LLMServiceProvider] {
        if let modelId = modelId {
            return llmProviders.filter { $0.provider.canHandle(modelId: modelId) }.map { $0.provider }
        }
        return llmProviders.map { $0.provider }
    }

    /// Get highest priority TTS provider for the specified model
    public func ttsProvider(for modelId: String? = nil) -> TTSServiceProvider? {
        if let modelId = modelId {
            return ttsProviders.first { $0.provider.canHandle(modelId: modelId) }?.provider
        }
        return ttsProviders.first?.provider
    }

    /// Get all TTS providers that can handle the specified model (sorted by priority)
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

    // MARK: - Availability

    public var hasSTT: Bool { !sttProviders.isEmpty }
    public var hasLLM: Bool { !llmProviders.isEmpty }
    public var hasTTS: Bool { !ttsProviders.isEmpty }
    public var hasSpeakerDiarization: Bool { !speakerDiarizationProviders.isEmpty }

    public var registeredModules: [String] {
        var modules: [String] = []
        if hasSTT { modules.append("STT") }
        if hasLLM { modules.append("LLM") }
        if hasTTS { modules.append("TTS") }
        if hasSpeakerDiarization { modules.append("SpeakerDiarization") }
        return modules
    }
}
