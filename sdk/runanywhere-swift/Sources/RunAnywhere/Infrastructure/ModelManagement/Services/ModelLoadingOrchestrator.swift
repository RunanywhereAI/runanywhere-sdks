import Foundation

// MARK: - Model Loading Orchestrator

/// Orchestrates model loading with lifecycle tracking, telemetry, and analytics
/// This centralizes the common pattern used for LLM, STT, and TTS model loading
public final class ModelLoadingOrchestrator {

    // MARK: - Dependencies

    private let modelLoadingService: ModelLoadingService
    private let telemetryService: TelemetryService
    private let modelRegistry: ModelRegistry
    private let logger = SDKLogger(category: "ModelLoadingOrchestrator")

    private var eventBus: EventBus {
        ServiceContainer.shared.eventBus
    }

    // MARK: - Initialization

    public init(
        modelLoadingService: ModelLoadingService,
        telemetryService: TelemetryService,
        modelRegistry: ModelRegistry
    ) {
        self.modelLoadingService = modelLoadingService
        self.telemetryService = telemetryService
        self.modelRegistry = modelRegistry
    }

    // MARK: - Model Loading Result

    /// Result of a model loading operation
    public struct LoadResult {
        public let loadedModel: LoadedModel?
        public let sttComponent: STTComponent?
        public let ttsComponent: TTSComponent?
        public let loadTimeMs: Double

        public init(
            loadedModel: LoadedModel? = nil,
            sttComponent: STTComponent? = nil,
            ttsComponent: TTSComponent? = nil,
            loadTimeMs: Double
        ) {
            self.loadedModel = loadedModel
            self.sttComponent = sttComponent
            self.ttsComponent = ttsComponent
            self.loadTimeMs = loadTimeMs
        }
    }

    // MARK: - Unified Loading Methods

    /// Load an LLM model with full lifecycle tracking, telemetry, and analytics
    /// - Parameter modelId: The model identifier
    /// - Returns: LoadResult containing the loaded model
    public func loadLLMModel(_ modelId: String) async throws -> LoadResult {
        let startTime = Date()

        // Get model info
        let modelInfo = modelRegistry.getModel(by: modelId)
        let framework = modelInfo?.preferredFramework ?? .llamaCpp
        let modelName = modelInfo?.name ?? modelId

        eventBus.publish(SDKModelEvent.loadStarted(modelId: modelId))

        // Notify lifecycle manager - will load
        await notifyWillLoad(
            modelId: modelId,
            modelName: modelName,
            framework: framework,
            modality: .llm
        )

        do {
            // Load the model
            let loadedModel = try await modelLoadingService.loadModel(modelId)

            let loadTimeMs = Date().timeIntervalSince(startTime) * 1000.0

            // Notify lifecycle manager - did load
            await notifyDidLoad(
                modelId: modelId,
                modelName: modelName,
                framework: framework,
                modality: .llm,
                memoryUsage: modelInfo?.memoryRequired,
                llmService: loadedModel.service
            )

            // Track telemetry and analytics
            await trackModelLoad(
                modelId: modelId,
                modelName: modelName,
                framework: framework,
                modality: .llm,
                loadTimeMs: loadTimeMs,
                modelSizeBytes: modelInfo?.downloadSize,
                success: true
            )

            eventBus.publish(SDKModelEvent.loadCompleted(modelId: modelId))

            return LoadResult(loadedModel: loadedModel, loadTimeMs: loadTimeMs)

        } catch {
            let loadTimeMs = Date().timeIntervalSince(startTime) * 1000.0

            await handleLoadFailure(
                modelId: modelId,
                modelInfo: modelInfo,
                modality: .llm,
                loadTimeMs: loadTimeMs,
                error: error
            )

            throw error
        }
    }

    /// Load an STT model with full lifecycle tracking, telemetry, and analytics
    /// - Parameter modelId: The model identifier
    /// - Returns: LoadResult containing the STT component
    public func loadSTTModel(_ modelId: String) async throws -> LoadResult {
        let startTime = Date()

        // Get model info
        let modelInfo = modelRegistry.getModel(by: modelId)
        let framework = modelInfo?.preferredFramework ?? .whisperKit
        let modelName = modelInfo?.name ?? modelId

        eventBus.publish(SDKModelEvent.loadStarted(modelId: modelId))

        // Notify lifecycle manager - will load
        await notifyWillLoad(
            modelId: modelId,
            modelName: modelName,
            framework: framework,
            modality: .stt
        )

        do {
            // Create STT configuration
            let sttConfig = STTConfiguration(modelId: modelId)

            // Create and initialize STT component on MainActor
            let sttComponent = await MainActor.run {
                STTComponent(configuration: sttConfig)
            }
            try await sttComponent.initialize()

            let loadTimeMs = Date().timeIntervalSince(startTime) * 1000.0

            // Notify lifecycle manager - did load
            await notifyDidLoad(
                modelId: modelId,
                modelName: modelName,
                framework: framework,
                modality: .stt,
                memoryUsage: modelInfo?.memoryRequired
            )

            // Track telemetry and analytics
            await trackSTTModelLoad(
                modelId: modelId,
                modelName: modelName,
                framework: framework,
                loadTimeMs: loadTimeMs,
                modelSizeBytes: modelInfo?.downloadSize,
                success: true
            )

            eventBus.publish(SDKModelEvent.loadCompleted(modelId: modelId))

            return LoadResult(sttComponent: sttComponent, loadTimeMs: loadTimeMs)

        } catch {
            let loadTimeMs = Date().timeIntervalSince(startTime) * 1000.0

            await handleSTTLoadFailure(
                modelId: modelId,
                modelInfo: modelInfo,
                loadTimeMs: loadTimeMs,
                error: error
            )

            throw error
        }
    }

    /// Load a TTS model with full lifecycle tracking, telemetry, and analytics
    /// - Parameter modelId: The model identifier (voice name)
    /// - Returns: LoadResult containing the TTS component
    public func loadTTSModel(_ modelId: String) async throws -> LoadResult {
        let startTime = Date()

        // Get model info
        let modelInfo = modelRegistry.getModel(by: modelId)
        let framework = modelInfo?.preferredFramework ?? .onnx
        let modelName = modelInfo?.name ?? modelId

        eventBus.publish(SDKModelEvent.loadStarted(modelId: modelId))

        // Notify lifecycle manager - will load
        await notifyWillLoad(
            modelId: modelId,
            modelName: modelName,
            framework: framework,
            modality: .tts
        )

        do {
            // Create TTS configuration
            let ttsConfig = TTSConfiguration(voice: modelId)

            // Create and initialize TTS component on MainActor
            let ttsComponent = await MainActor.run {
                TTSComponent(configuration: ttsConfig)
            }
            try await ttsComponent.initialize()

            let loadTimeMs = Date().timeIntervalSince(startTime) * 1000.0

            // Notify lifecycle manager - did load
            await notifyDidLoad(
                modelId: modelId,
                modelName: modelName,
                framework: framework,
                modality: .tts,
                memoryUsage: modelInfo?.memoryRequired
            )

            // Track telemetry and analytics
            await trackTTSModelLoad(
                modelId: modelId,
                modelName: modelName,
                framework: framework,
                loadTimeMs: loadTimeMs,
                modelSizeBytes: modelInfo?.downloadSize,
                success: true
            )

            eventBus.publish(SDKModelEvent.loadCompleted(modelId: modelId))

            return LoadResult(ttsComponent: ttsComponent, loadTimeMs: loadTimeMs)

        } catch {
            let loadTimeMs = Date().timeIntervalSince(startTime) * 1000.0

            await handleTTSLoadFailure(
                modelId: modelId,
                modelInfo: modelInfo,
                loadTimeMs: loadTimeMs,
                error: error
            )

            throw error
        }
    }

    // MARK: - Private Helpers - Lifecycle Notifications

    private func notifyWillLoad(
        modelId: String,
        modelName: String,
        framework: LLMFramework,
        modality: Modality
    ) async {
        await MainActor.run {
            ModelLifecycleTracker.shared.modelWillLoad(
                modelId: modelId,
                modelName: modelName,
                framework: framework,
                modality: modality
            )
        }
    }

    private func notifyDidLoad(
        modelId: String,
        modelName: String,
        framework: LLMFramework,
        modality: Modality,
        memoryUsage: Int64?,
        llmService: LLMService? = nil
    ) async {
        await MainActor.run {
            ModelLifecycleTracker.shared.modelDidLoad(
                modelId: modelId,
                modelName: modelName,
                framework: framework,
                modality: modality,
                memoryUsage: memoryUsage,
                llmService: llmService
            )
        }
    }

    private func notifyLoadFailed(modelId: String, modality: Modality, error: String) async {
        await MainActor.run {
            ModelLifecycleTracker.shared.modelLoadFailed(
                modelId: modelId,
                modality: modality,
                error: error
            )
        }
    }

    // MARK: - Private Helpers - Telemetry & Analytics

    private func trackModelLoad(
        modelId: String,
        modelName: String,
        framework: LLMFramework,
        modality: Modality,
        loadTimeMs: Double,
        modelSizeBytes: Int64?,
        success: Bool,
        errorMessage: String? = nil
    ) async {
        let deviceInfo = TelemetryDeviceInfo.current

        do {
            try await telemetryService.trackModelLoad(
                modelId: modelId,
                modelName: modelName,
                framework: framework.rawValue,
                modality: modality.rawValue,
                loadTimeMs: loadTimeMs,
                modelSizeBytes: modelSizeBytes,
                device: deviceInfo.device,
                osVersion: deviceInfo.osVersion,
                success: success,
                errorMessage: errorMessage
            )

            // Enqueue via AnalyticsQueueManager for backend transmission
            let eventData = ModelLoadingData(
                modelId: modelId,
                modelName: modelName,
                framework: framework.rawValue,
                device: deviceInfo.device,
                osVersion: deviceInfo.osVersion,
                platform: deviceInfo.platform,
                sdkVersion: SDKConstants.version,
                processingTimeMs: loadTimeMs,
                success: success,
                errorMessage: errorMessage,
                errorCode: success ? nil : errorMessage
            )

            let eventType: GenerationEventType = success ? .modelLoaded : .modelLoadFailed
            let event = GenerationEvent(type: eventType, eventData: eventData)
            await AnalyticsQueueManager.shared.enqueue(event)

            if success {
                await AnalyticsQueueManager.shared.flush()
            }
        } catch {
            // Telemetry failure is non-critical
            logger.warning("Failed to track model load telemetry: \(error.localizedDescription)")
        }
    }

    private func trackSTTModelLoad(
        modelId: String,
        modelName: String,
        framework: LLMFramework,
        loadTimeMs: Double,
        modelSizeBytes: Int64?,
        success: Bool,
        errorMessage: String? = nil
    ) async {
        let deviceInfo = TelemetryDeviceInfo.current

        do {
            try await telemetryService.trackSTTModelLoad(
                modelId: modelId,
                modelName: modelName,
                framework: framework.rawValue,
                loadTimeMs: loadTimeMs,
                modelSizeBytes: modelSizeBytes,
                device: deviceInfo.device,
                osVersion: deviceInfo.osVersion,
                success: success,
                errorMessage: errorMessage
            )

            // Enqueue via AnalyticsQueueManager
            let eventData = ModelLoadingData(
                modelId: modelId,
                modelName: modelName,
                framework: framework.rawValue,
                device: deviceInfo.device,
                osVersion: deviceInfo.osVersion,
                platform: deviceInfo.platform,
                sdkVersion: SDKConstants.version,
                processingTimeMs: loadTimeMs,
                success: success,
                errorMessage: errorMessage,
                errorCode: success ? nil : errorMessage
            )

            let eventType: STTEventType = success ? .modelLoaded : .modelLoadFailed
            let event = STTEvent(type: eventType, eventData: eventData)
            await AnalyticsQueueManager.shared.enqueue(event)

            if success {
                await AnalyticsQueueManager.shared.flush()
            }
        } catch {
            logger.warning("Failed to track STT model load telemetry: \(error.localizedDescription)")
        }
    }

    private func trackTTSModelLoad(
        modelId: String,
        modelName: String,
        framework: LLMFramework,
        loadTimeMs: Double,
        modelSizeBytes: Int64?,
        success: Bool,
        errorMessage: String? = nil
    ) async {
        let deviceInfo = TelemetryDeviceInfo.current

        do {
            try await telemetryService.trackTTSModelLoad(
                modelId: modelId,
                modelName: modelName,
                framework: framework.rawValue,
                loadTimeMs: loadTimeMs,
                modelSizeBytes: modelSizeBytes,
                device: deviceInfo.device,
                osVersion: deviceInfo.osVersion,
                success: success,
                errorMessage: errorMessage
            )

            // Enqueue via AnalyticsQueueManager
            let eventData = ModelLoadingData(
                modelId: modelId,
                modelName: modelName,
                framework: framework.rawValue,
                device: deviceInfo.device,
                osVersion: deviceInfo.osVersion,
                platform: deviceInfo.platform,
                sdkVersion: SDKConstants.version,
                processingTimeMs: loadTimeMs,
                success: success,
                errorMessage: errorMessage,
                errorCode: success ? nil : errorMessage
            )

            let eventType: TTSEventType = success ? .modelLoaded : .modelLoadFailed
            let event = TTSEvent(type: eventType, eventData: eventData)
            await AnalyticsQueueManager.shared.enqueue(event)

            if success {
                await AnalyticsQueueManager.shared.flush()
            }
        } catch {
            logger.warning("Failed to track TTS model load telemetry: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers - Error Handling

    private func handleLoadFailure(
        modelId: String,
        modelInfo: ModelInfo?,
        modality: Modality,
        loadTimeMs: Double,
        error: Error
    ) async {
        let framework = modelInfo?.preferredFramework ?? .llamaCpp
        let modelName = modelInfo?.name ?? modelId

        // Track failure telemetry
        await trackModelLoad(
            modelId: modelId,
            modelName: modelName,
            framework: framework,
            modality: modality,
            loadTimeMs: loadTimeMs,
            modelSizeBytes: modelInfo?.downloadSize,
            success: false,
            errorMessage: error.localizedDescription
        )

        // Notify lifecycle manager
        await notifyLoadFailed(modelId: modelId, modality: modality, error: error.localizedDescription)

        eventBus.publish(SDKModelEvent.loadFailed(modelId: modelId, error: error))
    }

    private func handleSTTLoadFailure(
        modelId: String,
        modelInfo: ModelInfo?,
        loadTimeMs: Double,
        error: Error
    ) async {
        let framework = modelInfo?.preferredFramework ?? .whisperKit
        let modelName = modelInfo?.name ?? modelId

        await trackSTTModelLoad(
            modelId: modelId,
            modelName: modelName,
            framework: framework,
            loadTimeMs: loadTimeMs,
            modelSizeBytes: modelInfo?.downloadSize,
            success: false,
            errorMessage: error.localizedDescription
        )

        await notifyLoadFailed(modelId: modelId, modality: .stt, error: error.localizedDescription)

        eventBus.publish(SDKModelEvent.loadFailed(modelId: modelId, error: error))
    }

    private func handleTTSLoadFailure(
        modelId: String,
        modelInfo: ModelInfo?,
        loadTimeMs: Double,
        error: Error
    ) async {
        let framework = modelInfo?.preferredFramework ?? .onnx
        let modelName = modelInfo?.name ?? modelId

        await trackTTSModelLoad(
            modelId: modelId,
            modelName: modelName,
            framework: framework,
            loadTimeMs: loadTimeMs,
            modelSizeBytes: modelInfo?.downloadSize,
            success: false,
            errorMessage: error.localizedDescription
        )

        await notifyLoadFailed(modelId: modelId, modality: .tts, error: error.localizedDescription)

        eventBus.publish(SDKModelEvent.loadFailed(modelId: modelId, error: error))
    }
}
