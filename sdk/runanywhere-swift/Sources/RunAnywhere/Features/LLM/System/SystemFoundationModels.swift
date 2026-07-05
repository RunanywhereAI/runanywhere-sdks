//
//  SystemFoundationModels.swift
//  RunAnywhere SDK
//
//  Built-in Apple Foundation Models (Apple Intelligence) module.
//  Platform-specific LLM provider available on iOS 26+ / macOS 26+.
//
//  Registration is now handled by the C++ platform backend. This module
//  provides the Swift service implementation that the C++ backend calls.
//

#if canImport(FoundationModels)
import FoundationModels
#endif

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
/// // Platform backend is registered automatically during SDK init.
/// // Load the built-in model via the canonical proto request.
/// var load = RAModelLoadRequest()
/// load.modelID = "foundation-models-default"
/// load.category = .language
/// load.framework = .foundationModels
/// _ = await RunAnywhere.loadModel(load)
///
/// // Generate text via canonical proto API
/// var req = RALLMGenerateRequest()
/// req.prompt = "Hello!"
/// let result = try await RunAnywhere.generate(req)
/// print(result.text)
/// ```
public enum SystemFoundationModels {
    // MARK: - Public API

    /// Check if Foundation Models is available on this device
    public static var isAvailable: Bool {
        unavailableReason == nil
    }

    /// Human-readable reason Foundation Models cannot be used on this runtime.
    public static var unavailableReason: String? {
        #if targetEnvironment(simulator)
        return "Apple Foundation Models are not available in iOS Simulator. Use a downloaded llama.cpp model instead."
        #else
        guard #available(iOS 26.0, macOS 26.0, *) else {
            return "Apple Foundation Models require iOS 26.0 or macOS 26.0."
        }
        #if canImport(FoundationModels)
        return foundationModelsRuntimeUnavailableReason()
        #else
        return "FoundationModels framework is not available in this build."
        #endif
        #endif
    }

    #if canImport(FoundationModels)
    // Called from inside `#if canImport(FoundationModels)`; swiftlint-analyze
    // does not evaluate conditional compilation so it reports this as unused.
    // swiftlint:disable unused_declaration
    @available(iOS 26.0, macOS 26.0, *)
    private static func foundationModelsRuntimeUnavailableReason() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device is not eligible for Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is not enabled in Settings."
        case .unavailable(.modelNotReady):
            return "Apple Foundation Models are not ready on this device."
        case .unavailable(let other):
            return "Apple Foundation Models are unavailable: \(String(describing: other))."
        @unknown default:
            return "Apple Foundation Models availability is unknown on this OS version."
        }
    }
    // swiftlint:enable unused_declaration
    #endif
}
