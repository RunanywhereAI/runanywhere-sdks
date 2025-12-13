//
//  LifecycleError.swift
//  RunAnywhere SDK
//
//  Typed errors for all lifecycle operations (model, service, component, adapter)
//

import Foundation

/// Errors that can occur during lifecycle operations
public enum LifecycleError: Error, LocalizedError, Sendable {

    // MARK: - Model Loading Errors

    /// Model not found in registry
    case modelNotFound(modelId: String)

    /// Model file not available locally
    case modelNotDownloaded(modelId: String)

    /// No adapter available for the model's framework
    case noAdapterAvailable(framework: LLMFramework)

    /// All adapters failed to load the model
    case allAdaptersFailed(modelId: String, lastError: String)

    /// Loading failed with specific reason
    case loadingFailed(modelId: String, reason: String)

    /// Model is already loading
    case alreadyLoading(modelId: String)

    /// Model is already loaded
    case alreadyLoaded(modelId: String)

    // MARK: - Model Unloading Errors

    /// Model not loaded
    case notLoaded(modelId: String)

    /// Unloading failed
    case unloadingFailed(modelId: String, reason: String)

    // MARK: - Service Lifecycle Errors

    /// Service not found by name
    case serviceNotFound(String)

    /// Service startup failed
    case serviceStartupFailed(name: String, error: Error)

    /// Service shutdown failed
    case serviceShutdownFailed(name: String, error: Error)

    /// Service not initialized
    case serviceNotInitialized

    /// Invalid service type returned by adapter
    case invalidServiceType(expected: String, received: String)

    /// Service deallocated unexpectedly
    case serviceDeallocated

    // MARK: - Component Lifecycle Errors

    /// Component not initialized
    case componentNotInitialized(component: String)

    /// Component initialization failed
    case componentInitializationFailed(component: String, error: Error)

    /// Component cleanup failed
    case componentCleanupFailed(component: String, error: Error)

    /// Component already exists
    case componentAlreadyExists(component: String)

    /// Invalid component configuration
    case invalidConfiguration(reason: String)

    // MARK: - Adapter Errors

    /// Adapter not registered for framework
    case adapterNotRegistered(framework: LLMFramework)

    /// Adapter registration failed
    case adapterRegistrationFailed(framework: LLMFramework, error: Error)

    /// Adapter initialization failed
    case adapterInitializationFailed(framework: LLMFramework, error: Error)

    // MARK: - State Errors

    /// Invalid state transition
    case invalidStateTransition(from: String, to: String)

    /// Operation cancelled
    case cancelled

    // MARK: - Resource Errors

    /// Insufficient memory
    case insufficientMemory(required: Int64, available: Int64)

    /// Resource allocation failed
    case resourceAllocationFailed(reason: String)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        // Model errors
        case .modelNotFound(let modelId):
            return "Model '\(modelId)' not found in registry"
        case .modelNotDownloaded(let modelId):
            return "Model '\(modelId)' is not downloaded locally"
        case .noAdapterAvailable(let framework):
            return "No adapter available for framework: \(framework.rawValue)"
        case .allAdaptersFailed(let modelId, let lastError):
            return "All adapters failed to load model '\(modelId)': \(lastError)"
        case .loadingFailed(let modelId, let reason):
            return "Failed to load model '\(modelId)': \(reason)"
        case .alreadyLoading(let modelId):
            return "Model '\(modelId)' is already being loaded"
        case .alreadyLoaded(let modelId):
            return "Model '\(modelId)' is already loaded"
        case .notLoaded(let modelId):
            return "Model '\(modelId)' is not loaded"
        case .unloadingFailed(let modelId, let reason):
            return "Failed to unload model '\(modelId)': \(reason)"

        // Service errors
        case .serviceNotFound(let name):
            return "Service '\(name)' not found"
        case .serviceStartupFailed(let name, let error):
            return "Failed to start service '\(name)': \(error.localizedDescription)"
        case .serviceShutdownFailed(let name, let error):
            return "Failed to stop service '\(name)': \(error.localizedDescription)"
        case .serviceNotInitialized:
            return "Service not initialized"
        case .invalidServiceType(let expected, let received):
            return "Invalid service type. Expected \(expected), received \(received)"
        case .serviceDeallocated:
            return "Service was deallocated during operation"

        // Component errors
        case .componentNotInitialized(let component):
            return "Component '\(component)' not initialized"
        case .componentInitializationFailed(let component, let error):
            return "Failed to initialize component '\(component)': \(error.localizedDescription)"
        case .componentCleanupFailed(let component, let error):
            return "Failed to cleanup component '\(component)': \(error.localizedDescription)"
        case .componentAlreadyExists(let component):
            return "Component '\(component)' already exists"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"

        // Adapter errors
        case .adapterNotRegistered(let framework):
            return "Adapter not registered for framework: \(framework.rawValue)"
        case .adapterRegistrationFailed(let framework, let error):
            return "Failed to register adapter for '\(framework.rawValue)': \(error.localizedDescription)"
        case .adapterInitializationFailed(let framework, let error):
            return "Failed to initialize adapter for '\(framework.rawValue)': \(error.localizedDescription)"

        // State errors
        case .invalidStateTransition(let from, let to):
            return "Invalid state transition from '\(from)' to '\(to)'"
        case .cancelled:
            return "Lifecycle operation was cancelled"

        // Resource errors
        case .insufficientMemory(let required, let available):
            return "Insufficient memory. Required: \(required) bytes, Available: \(available) bytes"
        case .resourceAllocationFailed(let reason):
            return "Resource allocation failed: \(reason)"
        }
    }
}

/// Type alias for convenience
public typealias ModelLifecycleError = LifecycleError
