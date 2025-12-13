import Foundation

// MARK: - Component Initialization Builder

/// Builder for creating component initialization requests
/// Provides a fluent API for configuring multiple components before initialization
public final class ComponentInitBuilder {
    private var configs: [UnifiedComponentConfig] = []
    private let componentLifecycleManager: ComponentLifecycleManager

    /// Initialize with a lifecycle manager
    public init(componentLifecycleManager: ComponentLifecycleManager) {
        self.componentLifecycleManager = componentLifecycleManager
    }

    // MARK: - Component Configuration Methods

    /// Add LLM with parameters
    @discardableResult
    public func withLLM(
        _ params: LLMConfiguration = LLMConfiguration(),
        priority: InitializationPriority = .normal,
        downloadPolicy: DownloadPolicy = .automatic
    ) -> Self {
        configs.append(UnifiedComponentConfig.llm(params, priority: priority, downloadPolicy: downloadPolicy))
        return self
    }

    /// Add STT with parameters
    @discardableResult
    public func withSTT(
        _ params: STTConfiguration = STTConfiguration(),
        priority: InitializationPriority = .normal,
        downloadPolicy: DownloadPolicy = .automatic
    ) -> Self {
        configs.append(UnifiedComponentConfig.stt(params, priority: priority, downloadPolicy: downloadPolicy))
        return self
    }

    /// Add TTS with parameters
    @discardableResult
    public func withTTS(
        _ params: TTSConfiguration = TTSConfiguration(),
        priority: InitializationPriority = .normal
    ) -> Self {
        configs.append(UnifiedComponentConfig.tts(params, priority: priority))
        return self
    }

    /// Add VAD with parameters
    @discardableResult
    public func withVAD(
        _ params: VADConfiguration = VADConfiguration(),
        priority: InitializationPriority = .normal
    ) -> Self {
        configs.append(UnifiedComponentConfig.vad(params, priority: priority))
        return self
    }

    /// Add Speaker Diarization with parameters
    @discardableResult
    public func withSpeakerDiarization(
        _ params: SpeakerDiarizationConfiguration = SpeakerDiarizationConfiguration(),
        priority: InitializationPriority = .normal
    ) -> Self {
        configs.append(UnifiedComponentConfig.speakerDiarization(params, priority: priority))
        return self
    }

    // MARK: - Build and Initialize

    /// Build and initialize all configured components
    public func initialize() async -> InitializationResult {
        return await componentLifecycleManager.initialize(configs)
    }

    /// Get the current configuration count
    public var configurationCount: Int {
        configs.count
    }

    /// Clear all configurations
    public func reset() -> Self {
        configs.removeAll()
        return self
    }
}
