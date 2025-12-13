// swiftlint:disable file_length
import Foundation
import Pulse

/// Service container for dependency injection
public class ServiceContainer { // swiftlint:disable:this type_body_length
    /// Shared instance
    public static let shared = ServiceContainer()
    // MARK: - Core Services

    /// Model registry
    private(set) lazy var modelRegistry: ModelRegistry = {
        RegistryService()
    }()

    /// Single adapter registry for all frameworks (text and voice)
    internal let adapterRegistry = AdapterRegistry()

    // MARK: - Capability Services

    /// Model loading service
    private(set) lazy var modelLoadingService: ModelLoadingService = {
        ModelLoadingService(
            registry: modelRegistry,
            adapterRegistry: adapterRegistry
        )
    }()

    /// Model loading orchestrator for unified model loading with lifecycle, telemetry, and analytics
    private var _modelLoadingOrchestrator: ModelLoadingOrchestrator?
    public var modelLoadingOrchestrator: ModelLoadingOrchestrator {
        guard let orchestrator = _modelLoadingOrchestrator else {
            fatalError("ModelLoadingOrchestrator not initialized. Call RunAnywhere.initialize() first.")
        }
        return orchestrator
    }

    internal func setModelLoadingOrchestrator(_ orchestrator: ModelLoadingOrchestrator) {
        _modelLoadingOrchestrator = orchestrator
    }

    /// Generation service
    private(set) lazy var generationService: LLMGenerationService = {
        LLMGenerationService(
            modelLoadingService: modelLoadingService
        )
    }()

    /// Streaming service
    private(set) lazy var streamingService: LLMStreamingService = {
        LLMStreamingService(generationService: generationService, modelLoadingService: modelLoadingService)
    }()

    /// Voice capability service
    private(set) lazy var voiceCapabilityService: VoiceCapabilityService = {
        VoiceCapabilityService()
    }()

    /// Voice orchestrator for voice pipeline operations
    private(set) lazy var voiceOrchestrator: VoiceOrchestrator = {
        VoiceOrchestrator()
    }()

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

    /// Configuration service
    private var _configurationService: ConfigurationService?
    public var configurationService: ConfigurationService {
        guard let service = _configurationService else {
            fatalError("ConfigurationService not initialized. Call RunAnywhere.initialize() first.")
        }
        return service
    }

    internal func setConfigurationService(_ service: ConfigurationService) {
        _configurationService = service
    }

    /// Telemetry service
    private var _telemetryService: TelemetryService?
    public var telemetryService: TelemetryService {
        guard let service = _telemetryService else {
            fatalError("TelemetryService not initialized. Call RunAnywhere.initialize() first.")
        }
        return service
    }

    internal func setTelemetryService(_ service: TelemetryService) {
        _telemetryService = service
    }

    /// Model info service
    private var _modelInfoService: ModelInfoService?
    public var modelInfoService: ModelInfoService {
        guard let service = _modelInfoService else {
            fatalError("ModelInfoService not initialized. Call RunAnywhere.initialize() first.")
        }
        return service
    }

    internal func setModelInfoService(_ service: ModelInfoService) {
        _modelInfoService = service
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

    /// Generation analytics service - using unified pattern
    private var _generationAnalytics: GenerationAnalyticsService?
    public var generationAnalytics: GenerationAnalyticsService {
        get async {
            if let service = _generationAnalytics {
                return service
            }
            let service = GenerationAnalyticsService(queueManager: analyticsQueueManager)
            _generationAnalytics = service
            return service
        }
    }

    // MARK: - Unified Analytics Services

    /// Analytics queue manager - centralized queue for all analytics
    public var analyticsQueueManager: AnalyticsQueueManager {
        AnalyticsQueueManager.shared
    }

    /// STT Analytics Service - using unified pattern
    private var _sttAnalytics: STTAnalyticsService?
    public var sttAnalytics: STTAnalyticsService {
        get async {
            if let service = _sttAnalytics {
                return service
            }
            let service = STTAnalyticsService(queueManager: analyticsQueueManager)
            _sttAnalytics = service
            return service
        }
    }

    /// Voice Analytics Service - using unified pattern
    private var _voiceAnalytics: VoiceAnalyticsService?
    public var voiceAnalytics: VoiceAnalyticsService {
        get async {
            if let service = _voiceAnalytics {
                return service
            }
            let service = VoiceAnalyticsService(queueManager: analyticsQueueManager)
            _voiceAnalytics = service
            return service
        }
    }

    /// TTS Analytics Service - using unified pattern
    private var _ttsAnalytics: TTSAnalyticsService?
    public var ttsAnalytics: TTSAnalyticsService {
        get async {
            if let service = _ttsAnalytics {
                return service
            }
            let service = TTSAnalyticsService(queueManager: analyticsQueueManager)
            _ttsAnalytics = service
            return service
        }
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
        _configurationService = nil
        _telemetryService = nil
        _modelInfoService = nil
        _modelAssignmentService = nil
        _generationAnalytics = nil
        _sttAnalytics = nil
        _voiceAnalytics = nil
        _ttsAnalytics = nil
        _deviceRegistrationService = nil
        _structuredOutputService = nil
        _modelLoadingOrchestrator = nil
    }
}
