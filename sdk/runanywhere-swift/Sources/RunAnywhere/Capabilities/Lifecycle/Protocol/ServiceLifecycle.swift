//
//  ServiceLifecycle.swift
//  RunAnywhere SDK
//
//  Protocol for services that require lifecycle management
//

import Foundation

/// Protocol for services that need lifecycle management (start/stop)
public protocol LifecycleAwareService {
    /// Start the service and initialize resources
    /// - Throws: If service startup fails
    func start() async throws

    /// Stop the service and clean up resources
    /// - Throws: If service shutdown fails
    func stop() async throws

    /// Check if the service is currently running
    var isRunning: Bool { get }
}

// MARK: - Default Implementations

public extension LifecycleAwareService {
    /// Default implementation returns false
    /// Services should override to track their running state
    var isRunning: Bool {
        false
    }
}
