//
//  RunAnywhereModule.swift
//  RunAnywhere SDK
//
//  Protocol for external modules that extend SDK capabilities.
//  Modules register services (STT, TTS, LLM, etc.) with the ServiceRegistry.
//

import Foundation

// MARK: - Capability Types

/// Types of capabilities that modules can provide
public enum CapabilityType: String, CaseIterable, Sendable {
    case stt = "STT"
    case tts = "TTS"
    case llm = "LLM"
    case vad = "VAD"
    case speakerDiarization = "SpeakerDiarization"
}

// MARK: - Module Protocol

/// Protocol for RunAnywhere modules that provide AI services.
///
/// External modules (ONNX, LlamaCPP, WhisperKit, etc.) conform to this protocol
/// to register their services with the SDK in a standardized way.
///
/// ## Implementing a Module
///
/// ```swift
/// import RunAnywhere
///
/// public enum MyModule: RunAnywhereModule {
///     public static let moduleId = "my-module"
///     public static let moduleName = "My Custom Module"
///     public static let capabilities: Set<CapabilityType> = [.stt, .tts]
///
///     @MainActor
///     public static func register(priority: Int) {
///         ServiceRegistry.shared.registerSTT(
///             name: moduleName,
///             priority: priority,
///             canHandle: { modelId in ... },
///             factory: { config in ... }
///         )
///     }
/// }
/// ```
///
/// ## Registration
///
/// Modules are registered via `ModuleRegistry`:
/// ```swift
/// ModuleRegistry.shared.register(MyModule.self)
/// ```
public protocol RunAnywhereModule {
    /// Unique identifier for this module (e.g., "onnx", "llamacpp", "whisperkit")
    static var moduleId: String { get }

    /// Human-readable display name (e.g., "ONNX Runtime", "LlamaCPP")
    static var moduleName: String { get }

    /// Set of capabilities this module provides
    static var capabilities: Set<CapabilityType> { get }

    /// Default priority for service registration (higher = preferred)
    static var defaultPriority: Int { get }

    /// Register all services provided by this module with the ServiceRegistry
    /// - Parameter priority: Registration priority (higher values are preferred)
    @MainActor
    static func register(priority: Int)
}

// MARK: - Default Implementations

public extension RunAnywhereModule {
    /// Default priority is 100
    static var defaultPriority: Int { 100 }

    /// Convenience registration with default priority
    @MainActor
    static func register() {
        register(priority: defaultPriority)
    }
}

// MARK: - Module Metadata

/// Metadata about a registered module
public struct ModuleMetadata: Sendable {
    /// Module identifier
    public let moduleId: String

    /// Display name
    public let moduleName: String

    /// Capabilities provided
    public let capabilities: Set<CapabilityType>

    /// Registration priority used
    public let priority: Int

    /// When the module was registered
    public let registeredAt: Date

    public init(
        moduleId: String,
        moduleName: String,
        capabilities: Set<CapabilityType>,
        priority: Int,
        registeredAt: Date = Date()
    ) {
        self.moduleId = moduleId
        self.moduleName = moduleName
        self.capabilities = capabilities
        self.priority = priority
        self.registeredAt = registeredAt
    }
}
