import Foundation
import Pulse

/// Service container for dependency injection
/// Provides centralized access to all SDK capabilities and services
public class ServiceContainer {
    /// Shared instance
    public static let shared = ServiceContainer()

    // MARK: - Core Registries

    /// Model registry for managing model information
    public private(set) lazy var modelRegistry: ModelRegistry = {
        RegistryService()
    }()

    // MARK: - Simplified Capabilities (New Architecture)

    /// LLM capability - handles all text generation operations
    private(set) lazy var llmCapability: LLMCapability = {
        LLMCapability()
    }()

    /// STT capability - handles speech-to-text operations
    private(set) lazy var sttCapability: STTCapability = {
        STTCapability()
    }()

    /// TTS capability - handles text-to-speech operations
    private(set) lazy var ttsCapability: TTSCapability = {
        TTSCapability()
    }()

    /// VAD capability - handles voice activity detection
    private(set) lazy var vadCapability: VADCapability = {
        VADCapability()
    }()

    /// Speaker Diarization capability - handles speaker identification
    private(set) lazy var speakerDiarizationCapability: SpeakerDiarizationCapability = {
        SpeakerDiarizationCapability()
    }()

    /// Voice Agent capability - composes STT, LLM, TTS, VAD for full voice pipeline
    private(set) lazy var voiceAgentCapability: VoiceAgentCapability = {
        VoiceAgentCapability(
            llm: llmCapability,
            stt: sttCapability,
            tts: ttsCapability,
            vad: vadCapability
        )
    }()

    // MARK: - Infrastructure Services

    /// Download service
    private(set) lazy var downloadService: AlamofireDownloadService = {
        AlamofireDownloadService()
    }()

    /// Simplified file manager
    private(set) lazy var fileManager: SimplifiedFileManager = {
        do {
            return try SimplifiedFileManager()
        } catch {
            fatalError("Failed to initialize file manager: \(error)")
        }
    }()

    /// Storage analyzer for storage operations
    private(set) lazy var storageAnalyzer: StorageAnalyzer = {
        DefaultStorageAnalyzer(fileManager: fileManager, modelRegistry: modelRegistry)
    }()

    // MARK: - Infrastructure

    /// Logger
    private(set) lazy var logger: SDKLogger = {
        SDKLogger()
    }()

    /// Database manager
    internal lazy var databaseManager: DatabaseManager = {
        DatabaseManager.shared
    }()

    /// Network service (environment-based: mock or real)
    public var networkService: (any NetworkService)?

    /// Authentication service
    public var authenticationService: AuthenticationService?

    /// API client for sync operations
    public var apiClient: APIClient?

    /// Sync coordinator for centralized sync management
    private var _syncCoordinator: SyncCoordinator?
    public var syncCoordinator: SyncCoordinator? {
        _syncCoordinator
    }

    internal func setSyncCoordinator(_ coordinator: SyncCoordinator?) {
        _syncCoordinator = coordinator
    }

    // MARK: - Data Services

    /// Configuration service (internal access for optional checking in development mode)
    internal var backingConfigurationService: ConfigurationService?
    public var configurationService: ConfigurationService {
        guard let service = backingConfigurationService else {
            fatalError("ConfigurationService not initialized. Call RunAnywhere.initialize() first.")
        }
        return service
    }

    internal func setConfigurationService(_ service: ConfigurationService) {
        backingConfigurationService = service
    }

    /// Model info service (internal access for optional checking in development mode)
    internal var backingModelInfoService: ModelInfoService?
    public var modelInfoService: ModelInfoService {
        guard let service = backingModelInfoService else {
            fatalError("ModelInfoService not initialized. Call RunAnywhere.initialize() first.")
        }
        return service
    }

    internal func setModelInfoService(_ service: ModelInfoService) {
        backingModelInfoService = service
    }

    /// Model assignment service
    private var _modelAssignmentService: ModelAssignmentService?
    public var modelAssignmentService: ModelAssignmentService {
        guard let service = _modelAssignmentService else {
            fatalError("ModelAssignmentService not initialized. Call RunAnywhere.initialize() first.")
        }
        return service
    }

    internal func setModelAssignmentService(_ service: ModelAssignmentService) {
        _modelAssignmentService = service
    }

    // MARK: - Analytics Services

    /// Analytics queue manager - centralized queue for all analytics
    public var analyticsQueueManager: AnalyticsQueueManager {
        AnalyticsQueueManager.shared
    }

    // MARK: - Device Services

    /// Device registration service - handles device registration with backend
    private var _deviceRegistrationService: DeviceRegistrationService?
    public var deviceRegistrationService: DeviceRegistrationService {
        if let service = _deviceRegistrationService {
            return service
        }
        let service = DeviceRegistrationService()
        _deviceRegistrationService = service
        return service
    }

    /// Dev analytics submission service - handles analytics in dev mode
    public var devAnalyticsService: DevAnalyticsSubmissionService {
        DevAnalyticsSubmissionService.shared
    }

    // MARK: - Event Services

    /// Event bus for publishing and subscribing to SDK events
    public var eventBus: EventBus {
        EventBus.shared
    }

    // MARK: - Structured Output Services

    /// Structured output generation service
    private var _structuredOutputService: StructuredOutputGenerationService?
    public var structuredOutputService: StructuredOutputGenerationService {
        if let service = _structuredOutputService {
            return service
        }
        let service = StructuredOutputGenerationService()
        _structuredOutputService = service
        return service
    }

    // MARK: - Initialization

    public init() {
        // Container is ready for lazy initialization
    }

    // MARK: - Internal Setters (for bootstrap services)

    /// Set the network service (internal use only)
    internal func setNetworkService(_ service: any NetworkService) {
        self.networkService = service
    }

    /// Set the API client (internal use only)
    internal func setAPIClient(_ client: APIClient) {
        self.apiClient = client
    }

    /// Set the authentication service (internal use only)
    internal func setAuthenticationService(_ service: AuthenticationService) {
        self.authenticationService = service
    }

    /// Reset service container state (for testing)
    public func reset() {
        authenticationService = nil
        apiClient = nil
        networkService = nil
        _syncCoordinator = nil
        backingConfigurationService = nil
        backingModelInfoService = nil
        _modelAssignmentService = nil
        _deviceRegistrationService = nil
        _structuredOutputService = nil
    }
}
