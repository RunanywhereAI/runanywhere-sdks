import Foundation

/// Service container for dependency injection.
/// Provides centralized access to SDK services.
///
/// Note: Network services (HTTP, Auth) are now handled by CppBridge.
/// Model registry is now directly accessed via CppBridge.ModelRegistry.shared.
/// This container manages platform-specific services only.
public class ServiceContainer {
    /// Shared instance
    public static let shared = ServiceContainer()

    // MARK: - Infrastructure Services

    /// Simplified file manager for platform-specific file operations
    private(set) lazy var fileManager: SimplifiedFileManager = {
        do {
            return try SimplifiedFileManager()
        } catch {
            fatalError("Failed to initialize file manager: \(error)")
        }
    }()

    // MARK: - Data Services

    /// Model assignment service - fetches model assignments from backend
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

    // MARK: - Initialization

    public init() {
        // Container is ready for lazy initialization
    }

    // MARK: - Reset (for testing)

    /// Reset service container state (for testing)
    public func reset() {
        _modelAssignmentService = nil
        _deviceRegistrationService = nil
    }
}
