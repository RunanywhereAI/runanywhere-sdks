import Foundation

/// Service container for dependency injection.
/// Provides centralized access to SDK services.
/// Note: Capabilities have been removed - use HandleManager for C++ component access.
public class ServiceContainer {
    /// Shared instance
    public static let shared = ServiceContainer()

    // MARK: - Core Registries

    /// Model registry for managing model information
    public private(set) lazy var modelRegistry: ModelRegistry = {
        RegistryService()
    }()

    // MARK: - Infrastructure Services

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

    /// Network service (environment-based: mock or real)
    public var networkService: (any NetworkService)?

    /// Authentication service
    public var authenticationService: AuthenticationService?

    /// API client for network operations
    public var apiClient: APIClient?

    // MARK: - Data Services

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

    /// Reset service container state (for testing)
    public func reset() {
        // Reset services
        authenticationService = nil
        apiClient = nil
        networkService = nil
        backingModelInfoService = nil
        _modelAssignmentService = nil
        _deviceRegistrationService = nil
        _structuredOutputService = nil
    }
}
