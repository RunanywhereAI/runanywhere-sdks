// RunAnywhere+LoRA.swift
// RunAnywhere SDK
//
// Public API for LoRA adapter management.
// Runtime operations delegate to CppBridge.LLM; catalog operations delegate to CppBridge.LoraRegistry.

import Foundation

// MARK: - LoRA Adapter Management

public extension RunAnywhere {

    // MARK: Runtime Operations

    /// Load and apply a LoRA adapter to the currently loaded model.
    /// Multiple adapters can be stacked. Context is recreated internally.
    static func loadLoraAdapter(_ config: LoRAAdapterConfig) async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }
        try await CppBridge.LLM.shared.loadLoraAdapter(config)
    }

    /// Remove a specific LoRA adapter by path.
    static func removeLoraAdapter(_ path: String) async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }
        try await CppBridge.LLM.shared.removeLoraAdapter(path)
    }

    /// Remove all loaded LoRA adapters.
    static func clearLoraAdapters() async throws {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }
        try await CppBridge.LLM.shared.clearLoraAdapters()
    }

    /// Get info about all currently loaded LoRA adapters.
    static func getLoadedLoraAdapters() async throws -> [LoRAAdapterInfo] {
        guard isInitialized else {
            throw SDKError.general(.notInitialized, "SDK not initialized")
        }
        return try await CppBridge.LLM.shared.getLoadedLoraAdapters()
    }

    /// Check if a LoRA adapter file is compatible with the currently loaded model.
    /// This is a lightweight pre-check; the definitive check happens on load.
    static func checkLoraCompatibility(loraPath: String) async -> LoraCompatibilityResult {
        guard isInitialized else {
            return LoraCompatibilityResult(isCompatible: false, error: "SDK not initialized")
        }
        return await CppBridge.LLM.shared.checkLoraCompatibility(loraPath: loraPath)
    }

    // MARK: Catalog Operations

    /// Register a LoRA adapter in the SDK catalog at app startup.
    /// Call this before loading any adapters so the SDK knows what's available.
    static func registerLoraAdapter(_ entry: LoraAdapterCatalogEntry) async throws {
        try await CppBridge.LoraRegistry.shared.register(entry)
    }

    /// Get all LoRA adapters compatible with a specific model.
    static func loraAdaptersForModel(_ modelId: String) async -> [LoraAdapterCatalogEntry] {
        return await CppBridge.LoraRegistry.shared.getForModel(modelId)
    }

    /// Get all registered LoRA adapters.
    static func allRegisteredLoraAdapters() async -> [LoraAdapterCatalogEntry] {
        return await CppBridge.LoraRegistry.shared.getAll()
    }
}
