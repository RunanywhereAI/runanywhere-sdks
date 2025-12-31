//
//  RunAnywhereModule.swift
//  RunAnywhere SDK
//
//  Protocol for SDK modules that provide AI capabilities.
//  Modules are the primary extension point for adding new backends.
//

import Foundation

/// Protocol for SDK modules that provide AI capabilities.
///
/// Modules encapsulate backend-specific functionality and register
/// service providers with the C++ commons layer. Each module typically
/// provides one or more capabilities (LLM, STT, TTS, VAD).
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
///     @MainActor
///     public static func register(priority: Int) {
///         // Register with C++ backend
///         let result = rac_backend_mymodule_register()
///         guard result == RAC_SUCCESS else { return }
///     }
/// }
/// ```
///
/// ## Auto-Registration
///
/// Modules can support auto-registration by adding:
///
/// ```swift
/// extension MyModule {
///     public static let autoRegister: Void = {
///         Task { @MainActor in
///             MyModule.register()
///         }
///     }()
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

    /// Register this module's services with the SDK.
    ///
    /// - Parameter priority: The priority for service registration.
    ///                       Higher values are preferred when multiple
    ///                       providers can handle a request.
    @MainActor
    static func register(priority: Int)
}

// MARK: - Default Implementations

public extension RunAnywhereModule {
    /// Register with default priority
    @MainActor
    static func register() {
        register(priority: defaultPriority)
    }
}
