import Foundation

/// Protocol for services that need lifecycle management
public protocol LifecycleAware {
    func start() async throws
    func stop() async throws
}

/// Manages the lifecycle of services
public class ServiceLifecycle {
    private var services: [String: LifecycleAware] = [:]
    private var startedServices: Set<String> = []
    private let queue = DispatchQueue(label: "com.runanywhere.service-lifecycle", attributes: .concurrent)

    /// Register a service for lifecycle management
    public func register(_ service: LifecycleAware, name: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.services[name] = service
        }
    }

    /// Start all registered services
    public func startAll() async throws {
        let servicesToStart = queue.sync { services }

        for (name, service) in servicesToStart {
            if !isStarted(name) {
                try await service.start()
                markAsStarted(name)
            }
        }
    }

    /// Stop all registered services
    public func stopAll() async throws {
        let servicesToStop = queue.sync { services.filter { startedServices.contains($0.key) } }

        // Stop in reverse order of starting
        for (name, service) in servicesToStop.reversed() {
            try await service.stop()
            markAsStopped(name)
        }
    }

    /// Start a specific service
    public func start(_ name: String) async throws {
        guard let service = queue.sync(execute: { services[name] }) else {
            throw ServiceLifecycleError.serviceNotFound(name)
        }

        if !isStarted(name) {
            try await service.start()
            markAsStarted(name)
        }
    }

    /// Stop a specific service
    public func stop(_ name: String) async throws {
        guard let service = queue.sync(execute: { services[name] }) else {
            throw ServiceLifecycleError.serviceNotFound(name)
        }

        if isStarted(name) {
            try await service.stop()
            markAsStopped(name)
        }
    }

    /// Check if a service is started
    public func isStarted(_ name: String) -> Bool {
        queue.sync { startedServices.contains(name) }
    }

    /// Restart a service
    public func restart(_ name: String) async throws {
        try await stop(name)
        try await start(name)
    }

    // MARK: - Private Methods

    private func markAsStarted(_ name: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.startedServices.insert(name)
        }
    }

    private func markAsStopped(_ name: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.startedServices.remove(name)
        }
    }

    /// Get all registered service names
    public var registeredServices: [String] {
        queue.sync { Array(services.keys) }
    }

    /// Get all started service names
    public var activeServices: [String] {
        queue.sync { Array(startedServices) }
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
