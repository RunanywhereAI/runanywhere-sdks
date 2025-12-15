//
//  FluidAudioModule.swift
//  FluidAudioDiarization Module
//
//  FluidAudio module providing speaker diarization capabilities.
//

import Foundation
import RunAnywhere

// MARK: - FluidAudio Module

/// FluidAudio module for Speaker Diarization.
///
/// Provides speaker identification and diarization capabilities
/// using FluidAudio's audio analysis technology.
///
/// ## Registration
///
/// ```swift
/// import FluidAudioDiarization
///
/// // Option 1: Direct registration (uses default priority)
/// FluidAudio.register()
///
/// // Option 1b: With custom priority
/// FluidAudio.register(priority: 50)
///
/// // Option 2: Via ModuleRegistry
/// ModuleRegistry.shared.register(FluidAudio.self)
///
/// // Option 3: Via RunAnywhere
/// RunAnywhere.register(FluidAudio.self)
/// ```
///
/// ## Usage
///
/// ```swift
/// let capability = SpeakerDiarizationCapability()
/// try await capability.initialize()
/// let speaker = try await capability.processAudio(samples)
/// ```
public enum FluidAudio: RunAnywhereModule {
    private static let logger = SDKLogger(category: "FluidAudio")

    // MARK: - RunAnywhereModule Conformance

    public static let moduleId = "fluidaudio"
    public static let moduleName = "FluidAudio"
    public static let inferenceFramework: InferenceFramework = .fluidAudio
    public static let capabilities: Set<CapabilityType> = [.speakerDiarization]
    public static let defaultPriority: Int = 100

    /// Register FluidAudio Speaker Diarization service with the SDK
    /// - Parameter priority: Registration priority (default: `defaultPriority`)
    @MainActor
    public static func register(priority: Int = defaultPriority) {
        ServiceRegistry.shared.registerSpeakerDiarization(
            name: moduleName,
            priority: priority,
            canHandle: { _ in true }, // FluidAudio can handle all diarization requests
            factory: { config in
                try await createService(config: config)
            }
        )
        logger.info("FluidAudio Speaker Diarization registered")
    }

    // MARK: - Private Helpers

    private static func createService(config: SpeakerDiarizationConfiguration) async throws -> SpeakerDiarizationService {
        logger.info("Creating FluidAudio diarization service")

        let threshold: Float = config.speakerChangeThreshold ?? 0.65
        let service = try await FluidAudioDiarization(threshold: threshold)

        logger.info("FluidAudio service created successfully")
        return service
    }
}

// MARK: - Auto-Discovery Registration

extension FluidAudio {
    /// Enable auto-discovery for this module.
    /// Access this property to trigger registration.
    public static let autoRegister: Void = {
        ModuleDiscovery.register(FluidAudio.self)
    }()
}
