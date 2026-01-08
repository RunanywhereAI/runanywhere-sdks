//
//  SystemFoundationModelsModule.swift
//  RunAnywhere SDK
//
//  Built-in Apple Foundation Models (Apple Intelligence) module.
//  Platform-specific LLM provider available on iOS 26+ / macOS 26+.
//
//  Registration is now handled by the C++ platform backend. This module
//  provides the Swift service implementation that the C++ backend calls.
//

import CRACommons
import Foundation

// MARK: - System Foundation Models Module

/// Built-in Apple Foundation Models (Apple Intelligence) module.
///
/// This is a platform-specific (iOS 26+/macOS 26+) LLM provider that uses
/// Apple's built-in Foundation Models powered by Apple Intelligence.
///
/// The C++ platform backend handles registration with the service registry.
/// This Swift module provides the actual implementation through callbacks.
///
/// ## Availability
///
/// Requires:
/// - iOS 26.0+ or macOS 26.0+
/// - Apple Intelligence enabled on the device
/// - Apple Intelligence capable hardware
///
/// ## Usage
///
/// ```swift
/// import RunAnywhere
///
/// // Platform backend is registered automatically during SDK init
/// // Load the built-in model
/// try await RunAnywhere.loadModel("foundation-models-default")
///
/// // Generate text
/// let response = try await RunAnywhere.chat("Hello!")
/// ```
public enum SystemFoundationModels: RunAnywhereModule {
    // MARK: - RunAnywhereModule Conformance

    public static let moduleId = "system-foundation-models"
    public static let moduleName = "System Foundation Models"
    public static let capabilities: Set<SDKComponent> = [.llm]
    public static let defaultPriority: Int = 50  // Lower than LlamaCPP (100)

    /// System Foundation Models uses Apple's built-in Foundation Models
    public static let inferenceFramework: InferenceFramework = .foundationModels

    // MARK: - Public API

    /// Check if Foundation Models is available on this device
    public static var isAvailable: Bool {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            return false
        }
        return true
    }

    /// Check if this module can handle the given model ID
    public static func canHandle(modelId: String?) -> Bool {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            return false
        }

        guard let modelId = modelId, !modelId.isEmpty else {
            return false
        }

        let lowercasedId = modelId.lowercased()
        return lowercasedId.contains("foundation-models")
            || lowercasedId.contains("foundation")
            || lowercasedId.contains("apple-intelligence")
            || lowercasedId == "foundation-models-default"
            || lowercasedId == "system-llm"
    }

    /// Create a SystemFoundationModelsService instance directly
    ///
    /// Use this for direct access without going through the service registry.
    @available(iOS 26.0, macOS 26.0, *)
    public static func createService() async throws -> SystemFoundationModelsService {
        let service = SystemFoundationModelsService()
        try await service.initialize(modelPath: "built-in")
        return service
    }
}
