import Combine
import Foundation

// MARK: - Component Initialization Extension

extension RunAnywhere {

    /// Component lifecycle manager for managing component initialization
    private static let componentLifecycleManager = ComponentLifecycleManager(serviceContainer: serviceContainer)

    // MARK: - Simple Initialization API

    /// Initialize components with default parameters
    /// - Parameter components: Components to initialize
    /// - Returns: Initialization result
    @discardableResult
    public static func initializeComponents(_ components: [SDKComponent]) async -> InitializationResult {
        let configs = components.map { component -> UnifiedComponentConfig in
            let params = defaultParameters(for: component)
            return UnifiedComponentConfig(parameters: params)
        }
        return await componentLifecycleManager.initialize(configs)
    }

    /// Initialize a single component with default parameters
    /// - Parameter component: Component to initialize
    /// - Returns: Initialization result
    @discardableResult
    public static func initialize(_ component: SDKComponent) async -> InitializationResult {
        return await initializeComponents([component])
    }

    // MARK: - Parameter-Based Initialization

    /// Initialize LLM with specific parameters
    @discardableResult
    public static func initializeLLM(
        modelId: String? = nil,
        contextLength: Int = 2048,
        quantization: LLMConfiguration.QuantizationLevel? = nil,
        priority: InitializationPriority = .normal
    ) async -> InitializationResult {
        let params = LLMConfiguration(
            modelId: modelId,
            contextLength: contextLength,
            quantizationLevel: quantization
        )
        let config = UnifiedComponentConfig.llm(params, priority: priority)
        return await componentLifecycleManager.initialize([config])
    }

    /// Initialize STT with specific parameters
    @discardableResult
    public static func initializeSTT(
        modelId: String? = "whisper-base",
        language: String = "en",
        enableSpeakerDiarization: Bool = false,
        priority: InitializationPriority = .normal
    ) async -> InitializationResult {
        let params = STTConfiguration(
            modelId: modelId,
            language: language,
            enableDiarization: enableSpeakerDiarization
        )
        let config = UnifiedComponentConfig.stt(params, priority: priority)
        return await componentLifecycleManager.initialize([config])
    }

    /// Initialize TTS with specific parameters
    @discardableResult
    public static func initializeTTS(
        voice: String = "com.apple.ttsbundle.siri_female_en-US_compact",
        language: String = "en-US",
        rate: Float = 1.0,
        pitch: Float = 1.0,
        priority: InitializationPriority = .normal
    ) async -> InitializationResult {
        let params = TTSConfiguration(
            voice: voice,
            language: language,
            speakingRate: rate,
            pitch: pitch
        )
        let config = UnifiedComponentConfig.tts(params, priority: priority)
        return await componentLifecycleManager.initialize([config])
    }

    /// Initialize VAD with specific parameters
    @discardableResult
    public static func initializeVAD(
        energyThreshold: Float = 0.01,
        silenceTimeout: TimeInterval = 1.0,
        priority: InitializationPriority = .normal
    ) async -> InitializationResult {
        let params = VADConfiguration(
            energyThreshold: energyThreshold
        )
        let config = UnifiedComponentConfig.vad(params, priority: priority)
        return await componentLifecycleManager.initialize([config])
    }

    // MARK: - Advanced Initialization

    /// Initialize components with full parameter control
    /// - Parameter configs: Array of unified component configurations
    /// - Returns: Initialization result
    @discardableResult
    public static func initializeComponents(configs: [UnifiedComponentConfig]) async -> InitializationResult {
        return await componentLifecycleManager.initialize(configs)
    }

    // MARK: - Preload Scenarios

    /// Preload components for voice assistant functionality
    @discardableResult
    public static func preloadVoiceAssistant(
        sttModelId: String? = "whisper-base",
        llmModelId: String? = nil
    ) async -> InitializationResult {
        let configs = [
            UnifiedComponentConfig.vad(VADConfiguration(), priority: .high),
            UnifiedComponentConfig.stt(STTConfiguration(modelId: sttModelId), priority: .critical),
            UnifiedComponentConfig.llm(LLMConfiguration(modelId: llmModelId), priority: .high),
            UnifiedComponentConfig.tts(TTSConfiguration(), priority: .normal)
        ]
        return await componentLifecycleManager.initialize(configs)
    }

    /// Preload components for text generation
    @discardableResult
    public static func preloadTextGeneration(modelId: String? = nil) async -> InitializationResult {
        let config = UnifiedComponentConfig.llm(
            LLMConfiguration(modelId: modelId),
            priority: .critical
        )
        return await componentLifecycleManager.initialize([config])
    }

    // MARK: - Builder Pattern

    /// Builder for creating component initialization requests
    public class ComponentInitBuilder {
        private var configs: [UnifiedComponentConfig] = []

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

        /// Build and initialize
        public func initialize() async -> InitializationResult {
            return await RunAnywhere.componentLifecycleManager.initialize(configs)
        }
    }

    /// Create a component initialization builder
    public static func componentBuilder() -> ComponentInitBuilder {
        ComponentInitBuilder()
    }

    // MARK: - Status and State Management

    /// Get current status of all components
    public static func getComponentStatuses() async -> [ComponentStatus] {
        await componentLifecycleManager.getAllStatuses()
    }

    /// Get status of a specific component
    public static func getComponentStatus(_ component: SDKComponent) async -> ComponentStatus {
        await componentLifecycleManager.getStatus(for: component)
    }

    /// Check if a component is ready
    public static func isComponentReady(_ component: SDKComponent) async -> Bool {
        await componentLifecycleManager.isReady(component)
    }

    /// Check if multiple components are ready
    public static func areComponentsReady(_ components: [SDKComponent]) async -> Bool {
        for component in components {
            if !(await componentLifecycleManager.isReady(component)) {
                return false
            }
        }
        return true
    }

    /// Get component status with its initialization parameters
    public static func getComponentStatusWithParameters(
        _ component: SDKComponent
    ) async -> (status: ComponentStatus, parameters: (any ComponentInitParameters)?) {
        let status = await componentLifecycleManager.getStatus(for: component)
        return (status, nil) // Parameters not tracked in new implementation
    }

    /// Get all component statuses with their initialization parameters
    public static func getAllComponentStatusesWithParameters() async -> [(status: ComponentStatus, parameters: (any ComponentInitParameters)?)] {
        let statuses = await componentLifecycleManager.getAllStatuses()
        return statuses.map { ($0, nil) } // Parameters not tracked in new implementation
    }

    // MARK: - Event Subscriptions

    /// Subscribe to component initialization events
    public static func onComponentInitialization(
        handler: @escaping (ComponentInitializationEvent) -> Void
    ) -> AnyCancellable {
        EventBus.shared.onComponentInitialization(handler: handler)
    }

    /// Subscribe to events for a specific component
    public static func onComponent(
        _ component: SDKComponent,
        handler: @escaping (ComponentInitializationEvent) -> Void
    ) -> AnyCancellable {
        EventBus.shared.onComponent(component, handler: handler)
    }

    /// Subscribe to component state changes
    public static func onComponentStateChange(
        handler: @escaping (SDKComponent, ComponentState, ComponentState) -> Void
    ) -> AnyCancellable {
        EventBus.shared.onComponentInitialization { event in
            if case .componentStateChanged(let component, let oldState, let newState) = event {
                handler(component, oldState, newState)
            }
        }
    }

    /// Subscribe to download progress events
    public static func onDownloadProgress(
        handler: @escaping (SDKComponent, String, Double) -> Void
    ) -> AnyCancellable {
        EventBus.shared.onComponentInitialization { event in
            if case .componentDownloadProgress(let component, let modelId, let progress) = event {
                handler(component, modelId, progress)
            }
        }
    }

    // MARK: - Helper Methods

    /// Get default parameters for a component
    private static func defaultParameters(for component: SDKComponent) -> any ComponentInitParameters {
        switch component {
        case .llm:
            return LLMConfiguration()
        case .stt:
            return STTConfiguration()
        case .tts:
            return TTSConfiguration()
        case .vad:
            return VADConfiguration()
        case .speakerDiarization:
            return SpeakerDiarizationConfiguration()
        case .embedding:
            return LLMConfiguration() // Use LLM config as default for embedding
        case .wakeWord:
            return WakeWordConfiguration()
        case .voiceAgent:
            // Voice agent is a composite component, use default configs
            return VoiceAgentConfiguration(
                vadConfig: VADConfiguration(),
                sttConfig: STTConfiguration(),
                llmConfig: LLMConfiguration(),
                ttsConfig: TTSConfiguration()
            )
        }
    }
}
