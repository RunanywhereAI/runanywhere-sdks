//
//  RunAnywhere+Diffusion.swift
//  RunAnywhere SDK
//
//  Public API for diffusion image generation operations.
//  All loading flows through the canonical lifecycle (RAModelLoadRequest);
//  generation/streaming/cancel forward to the proto C++ ABI.
//

import Foundation

public extension RunAnywhere {

    /// Generate an image through the generated-proto C++ diffusion ABI.
    static func generateImage(options: RADiffusionGenerationOptions) async throws -> RADiffusionResult {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        guard await CppBridge.Diffusion.shared.isLoaded else {
            throw SDKException.diffusion(.notInitialized, "No diffusion model loaded")
        }

        return try await CppBridge.Diffusion.shared.generate(options: options)
    }

    /// Generate an image with proto progress through the generated C++ diffusion ABI.
    static func generateImage(
        options: RADiffusionGenerationOptions,
        onProgress: @escaping (RADiffusionProgress) -> Bool
    ) async throws -> RADiffusionResult {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }
        try await ensureServicesReady()

        guard await CppBridge.Diffusion.shared.isLoaded else {
            throw SDKException.diffusion(.notInitialized, "No diffusion model loaded")
        }

        return try await CppBridge.Diffusion.shared.generateWithProgress(options: options, onProgress: onProgress)
    }

    /// Cancel ongoing image generation.
    static func cancelImageGeneration() async throws {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        do {
            try await CppBridge.Diffusion.shared.cancelProto()
        } catch {
            await CppBridge.Diffusion.shared.cancel()
        }
    }

    /// Get diffusion service capabilities.
    static func getDiffusionCapabilities() async throws -> RADiffusionCapabilities {
        guard isInitialized else {
            throw SDKException.general(.notInitialized, "SDK not initialized")
        }

        return await CppBridge.Diffusion.shared.getCapabilities()
    }
}
