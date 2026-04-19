//
//  RunAnywhereModule.swift
//  RunAnywhere SDK
//
//  Protocol for SDK modules that provide AI capabilities.
//  Modules are the primary extension point for adding new backends.
//
//  Note: Registration is now handled by the C++ platform backend.
//  Modules only need to provide metadata and service creation.
//

import Foundation

/// Protocol for SDK modules that provide AI capabilities.
///
/// Modules encapsulate backend-specific functionality for the SDK.
/// Each module typically provides one or more capabilities (LLM, STT, TTS, VAD).
///
/// Registration with the C++ service registry is handled automatically by the
/// platform backend during SDK initialization. Modules only need to provide
/// metadata and service creation methods.
///
/// ## Implementing a Module
///
/// ```swift
/// public enum MyModule: RunAnywhereModule {
///     public static let moduleId = "my-module"
///     public static let moduleName = "My Module"
///     public static let capabilities: Set<SDKComponent> = [.llm]
///     public static let defaultPriority: Int = 100
///     public static let inferenceFramework: InferenceFramework = .onnx
///
///     public static func createService() async throws -> MyService {
///         let service = MyService()
///         try await service.initialize()
///         return service
///     }
/// }
/// ```
public protocol RunAnywhereModule {
    /// Unique identifier for this module (e.g., "llamacpp", "onnx")
    static var moduleId: String { get }

    /// Human-readable name for the module
    static var moduleName: String { get }

    /// Set of capabilities this module provides
    static var capabilities: Set<SDKComponent> { get }

    /// Default priority for service registration (higher = preferred)
    static var defaultPriority: Int { get }

    /// The inference framework this module uses
    static var inferenceFramework: InferenceFramework { get }
}
