import Foundation

/// Protocol for services that need lifecycle management
public protocol LifecycleAware {
    func start() async throws
    func stop() async throws
}

/// Manages the lifecycle of services
public actor ServiceLifecycle {
    private var services: [String: LifecycleAware] = [:]
    private var startedServices: Set<String> = []

    /// Register a service for lifecycle management
    public func register(_ service: LifecycleAware, name: String) {
        services[name] = service
    }

    /// Start all registered services
    public func startAll() async throws {
        for (name, service) in services where !startedServices.contains(name) {
            try await service.start()
            startedServices.insert(name)
        }
    }

    /// Stop all registered services
    public func stopAll() async throws {
        let servicesToStop = services.filter { startedServices.contains($0.key) }

        // Stop in reverse order of starting
        for (name, service) in servicesToStop.reversed() {
            try await service.stop()
            startedServices.remove(name)
        }
    }

    /// Start a specific service
    public func start(_ name: String) async throws {
        guard let service = services[name] else {
            throw ServiceLifecycleError.serviceNotFound(name)
        }

        if !startedServices.contains(name) {
            try await service.start()
            startedServices.insert(name)
        }
    }

    /// Stop a specific service
    public func stop(_ name: String) async throws {
        guard let service = services[name] else {
            throw ServiceLifecycleError.serviceNotFound(name)
        }

        if startedServices.contains(name) {
            try await service.stop()
            startedServices.remove(name)
        }
    }

    /// Check if a service is started
    public func isStarted(_ name: String) -> Bool {
        startedServices.contains(name)
    }

    /// Restart a service
    public func restart(_ name: String) async throws {
        try await stop(name)
        try await start(name)
    }

    /// Get all registered service names
    public var registeredServices: [String] {
        Array(services.keys)
    }

    /// Get all started service names
    public var activeServices: [String] {
        Array(startedServices)
    }
}

/// Errors for service lifecycle
public enum ServiceLifecycleError: LocalizedError {
    case serviceNotFound(String)
    case startupFailed(String, Error)
    case shutdownFailed(String, Error)

    public var errorDescription: String? {
        switch self {
        case .serviceNotFound(let name):
            return "Service '\(name)' not found"
        case .startupFailed(let name, let error):
            return "Failed to start service '\(name)': \(error.localizedDescription)"
        case .shutdownFailed(let name, let error):
            return "Failed to stop service '\(name)': \(error.localizedDescription)"
        }
    }
}
