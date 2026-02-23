//
//  RunAnywhere+LoRA.swift
//  RunAnywhere SDK
//
//  Public API for LoRA adapter management.
//  Delegates to C++ via CppBridge.LLM for all operations.
//

import Foundation

// MARK: - LoRA Adapter Management

public extension RunAnywhere {

    /// Load and apply a LoRA adapter to the currently loaded model.
    ///
    /// The adapter is loaded from a GGUF file and applied with the given scale.
    /// Multiple adapters can be stacked. Context is recreated internally.
    ///
    /// - Parameter config: LoRA adapter configuration (path and scale)
    /// - Throws: `SDKError` if no model is loaded or loading fails
    static func loadLoraAdapter(_ config: LoRAAdapterConfig) async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }
        try await CppBridge.LLM.shared.loadLoraAdapter(config)
    }

    /// Remove a specific LoRA adapter by path.
    ///
    /// - Parameter path: Path that was used when loading the adapter
    /// - Throws: `SDKError` if adapter not found or removal fails
    static func removeLoraAdapter(_ path: String) async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }
        try await CppBridge.LLM.shared.removeLoraAdapter(path)
    }

    /// Remove all loaded LoRA adapters.
    ///
    /// - Throws: `SDKError` if clearing fails
    static func clearLoraAdapters() async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }
        try await CppBridge.LLM.shared.clearLoraAdapters()
    }

    /// Get info about all currently loaded LoRA adapters.
    ///
    /// - Returns: List of loaded adapter info (path, scale, applied status)
    static func getLoadedLoraAdapters() async throws -> [LoRAAdapterInfo] {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }
        return try await CppBridge.LLM.shared.getLoadedLoraAdapters()
    }
}
