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
}

// MARK: - Module Protocol

/// Protocol for RunAnywhere modules that provide AI services.
///
/// External modules (ONNX, LlamaCPP, etc.) conform to this protocol
/// to register their services with the SDK in a standardized way.
///
/// ## Implementing a Module
///
/// ```swift
/// public enum MyModule: RunAnywhereModule {
///     public static let moduleId = "my-module"
///     public static let moduleName = "My Custom Module"
///     public static let inferenceFramework: InferenceFramework = .onnx
///     public static let capabilities: Set<CapabilityType> = [.stt, .tts]
///
///     @MainActor
///     public static func register(priority: Int) { ... }
/// }
/// ```
///
/// ## Registration with Models
///
/// ```swift
/// LlamaCPP.register()
/// LlamaCPP.addModel(name: "Llama 2 7B", url: "...", memoryRequirement: 4_000_000_000)
/// ```
public protocol RunAnywhereModule {
    /// Unique identifier for this module (e.g., "onnx", "llamacpp")
    static var moduleId: String { get }

    /// Human-readable display name (e.g., "ONNX Runtime", "LlamaCPP")
    static var moduleName: String { get }

    /// The inference framework this module provides (required)
    static var inferenceFramework: InferenceFramework { get }

    /// Set of capabilities this module provides
    static var capabilities: Set<CapabilityType> { get }

    /// Default priority for service registration (higher = preferred)
    static var defaultPriority: Int { get }

    /// Optional storage strategy for detecting downloaded models
    /// Modules with directory-based models (like ONNX) should provide this
    static var storageStrategy: ModelStorageStrategy? { get }

    /// Optional download strategy for custom download handling
    /// Modules with special download requirements should provide this
    static var downloadStrategy: DownloadStrategy? { get }

    /// Register all services provided by this module with the ServiceRegistry
    /// - Parameter priority: Registration priority (higher values are preferred)
    @MainActor
    static func register(priority: Int)
}

// MARK: - Default Implementations

public extension RunAnywhereModule {
    /// Default priority is 100
    static var defaultPriority: Int { 100 }

    /// Default storage strategy is nil (uses generic file detection)
    static var storageStrategy: ModelStorageStrategy? { nil }

    /// Default download strategy is nil (uses standard download flow)
    static var downloadStrategy: DownloadStrategy? { nil }

    /// Convenience registration with default priority
    @MainActor
    static func register() {
        register(priority: defaultPriority)
    }

    /// Add a model to this module (uses the module's inferenceFramework automatically)
    /// - Parameters:
    ///   - id: Explicit model ID. If nil, a stable ID is generated from the URL filename.
    ///   - name: Display name for the model
    ///   - url: Download URL string for the model
    ///   - modality: Model category (inferred from module capabilities if not specified)
    ///   - artifactType: How the model is packaged (inferred from URL if not specified)
    ///   - memoryRequirement: Estimated memory usage in bytes
    ///   - supportsThinking: Whether the model supports reasoning/thinking
    /// - Returns: The created ModelInfo, or nil if URL is invalid
    @MainActor
    @discardableResult
    static func addModel(
        id: String? = nil,
        name: String,
        url: String,
        modality: ModelCategory? = nil,
        artifactType: ModelArtifactType? = nil,
        memoryRequirement: Int64? = nil,
        supportsThinking: Bool = false
    ) -> ModelInfo? {
        guard let downloadURL = URL(string: url) else {
            SDKLogger(category: "Module.\(moduleId)").error("Invalid URL for model '\(name)': \(url)")
            return nil
        }

        // Determine modality from parameter or infer from module capabilities
        let category = modality ?? inferModalityFromCapabilities()

        // Register the model with this module's framework
        let modelInfo = ServiceContainer.shared.modelRegistry.addModelFromURL(
            id: id,
            name: name,
            url: downloadURL,
            framework: inferenceFramework,
            category: category,
            artifactType: artifactType,
            estimatedSize: memoryRequirement,
            supportsThinking: supportsThinking
        )

        return modelInfo
    }

    /// Infer the primary modality from module capabilities
    private static func inferModalityFromCapabilities() -> ModelCategory {
        if capabilities.contains(.llm) {
            return .language
        } else if capabilities.contains(.stt) {
            return .speechRecognition
        } else if capabilities.contains(.tts) {
            return .speechSynthesis
        } else if capabilities.contains(.vad) {
            return .audio
        }
        return .language // Default
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
