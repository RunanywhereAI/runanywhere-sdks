//
//  ServiceLifecycleManager.swift
//  RunAnywhere SDK
//
//  Manages the lifecycle of services (start/stop)
//

import Foundation

/// Manages the lifecycle of services
public actor ServiceLifecycleManager {

    // MARK: - Properties

    private var services: [String: LifecycleAwareService] = [:]
    private var startedServices: Set<String> = []
    private let logger = SDKLogger(category: "ServiceLifecycleManager")

    // MARK: - Initialization

    public init() {}

    // MARK: - Registration

    /// Register a service for lifecycle management
    /// - Parameters:
    ///   - service: The service to register
    ///   - name: Unique name for the service
    public func register(_ service: LifecycleAwareService, name: String) {
        logger.debug("Registering service: \(name)")
        services[name] = service
    }

    /// Unregister a service
    /// - Parameter name: The name of the service to unregister
    public func unregister(name: String) {
        logger.debug("Unregistering service: \(name)")
        services.removeValue(forKey: name)
        startedServices.remove(name)
    }

    // MARK: - Lifecycle Operations

    /// Start all registered services
    /// - Throws: If any service fails to start
    public func startAll() async throws {
        logger.info("Starting all services (\(services.count) total)")

        for (name, service) in services where !startedServices.contains(name) {
            do {
                try await service.start()
                startedServices.insert(name)
                logger.debug("Started service: \(name)")
            } catch {
                logger.error("Failed to start service '\(name)': \(error.localizedDescription)")
                throw LifecycleError.serviceStartupFailed(name: name, error: error)
            }
        }

        logger.info("All services started successfully")
    }

    /// Stop all registered services in reverse order
    /// - Throws: If any service fails to stop
    public func stopAll() async throws {
        logger.info("Stopping all services")

        let servicesToStop = services.filter { startedServices.contains($0.key) }

        // Stop in reverse order of starting
        for (name, service) in servicesToStop.reversed() {
            do {
                try await service.stop()
                startedServices.remove(name)
                logger.debug("Stopped service: \(name)")
            } catch {
                logger.error("Failed to stop service '\(name)': \(error.localizedDescription)")
                throw LifecycleError.serviceShutdownFailed(name: name, error: error)
            }
        }

        logger.info("All services stopped successfully")
    }

    /// Start a specific service by name
    /// - Parameter name: The name of the service to start
    /// - Throws: If service not found or fails to start
    public func start(_ name: String) async throws {
        guard let service = services[name] else {
            logger.error("Service not found: \(name)")
            throw LifecycleError.serviceNotFound(name)
        }

        if !startedServices.contains(name) {
            logger.debug("Starting service: \(name)")
            do {
                try await service.start()
                startedServices.insert(name)
                logger.debug("Service started: \(name)")
            } catch {
                logger.error("Failed to start service '\(name)': \(error.localizedDescription)")
                throw LifecycleError.serviceStartupFailed(name: name, error: error)
            }
        } else {
            logger.debug("Service '\(name)' already started")
        }
    }

    /// Stop a specific service by name
    /// - Parameter name: The name of the service to stop
    /// - Throws: If service not found or fails to stop
    public func stop(_ name: String) async throws {
        guard let service = services[name] else {
            logger.error("Service not found: \(name)")
            throw LifecycleError.serviceNotFound(name)
        }

        if startedServices.contains(name) {
            logger.debug("Stopping service: \(name)")
            do {
                try await service.stop()
                startedServices.remove(name)
                logger.debug("Service stopped: \(name)")
            } catch {
                logger.error("Failed to stop service '\(name)': \(error.localizedDescription)")
                throw LifecycleError.serviceShutdownFailed(name: name, error: error)
            }
        } else {
            logger.debug("Service '\(name)' not started")
        }
    }

    /// Restart a specific service
    /// - Parameter name: The name of the service to restart
    /// - Throws: If service not found or fails to restart
    public func restart(_ name: String) async throws {
        logger.info("Restarting service: \(name)")
        try await stop(name)
        try await start(name)
        logger.info("Service restarted: \(name)")
    }

    // MARK: - Query Methods

    /// Check if a service is started
    /// - Parameter name: The name of the service
    /// - Returns: Whether the service is started
    public func isStarted(_ name: String) -> Bool {
        startedServices.contains(name)
    }

    /// Get all registered service names
    public var registeredServices: [String] {
        Array(services.keys)
    }

    /// Get all started service names
    public var activeServices: [String] {
        Array(startedServices)
    }

    /// Get the number of registered services
    public var serviceCount: Int {
        services.count
    }

    /// Get the number of active services
    public var activeServiceCount: Int {
        startedServices.count
    }

    // MARK: - Cleanup

    /// Remove all services and reset state
    public func clear() async throws {
        logger.info("Clearing all services")
        try await stopAll()
        services.removeAll()
        startedServices.removeAll()
        logger.info("All services cleared")
    }
}
