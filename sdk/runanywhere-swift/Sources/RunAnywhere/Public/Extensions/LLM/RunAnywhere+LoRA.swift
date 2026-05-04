// RunAnywhere+LoRA.swift
// RunAnywhere SDK
//
// Public API for LoRA adapter management — namespaced under
// `RunAnywhere.lora.*` per the canonical cross-SDK spec
// (CANONICAL_API §3 — LoRA).
//
// Runtime operations delegate to CppBridge.LLM; catalog operations
// delegate to CppBridge.LoraRegistry.

import Foundation

// MARK: - LoRA Capability Namespace

public extension RunAnywhere {

    /// Capability accessor for LoRA adapter management.
    ///
    /// Mirrors the namespaced `lora.*` shape used by the other SDKs
    /// (Kotlin/Flutter/RN/Web). All eight canonical methods live on
    /// the returned `LoRA` value.
    static var lora: LoRA { LoRA() }

    /// Stateless namespace exposing the canonical 8-method LoRA surface.
    /// Backed by the C ABI via `CppBridge.LLM` (runtime ops) and
    /// `CppBridge.LoraRegistry` (catalog ops).
    struct LoRA: Sendable {

        fileprivate init() {}

        // MARK: Runtime Operations

        /// Load and apply a LoRA adapter to the currently loaded model.
        /// Multiple adapters can be stacked. Context is recreated internally.
        ///
        /// - Parameter config: `LoRAAdapterConfig` with path and scale.
        /// - Returns: `LoRAAdapterInfo` describing the loaded adapter.
        @discardableResult
        public func load(_ config: LoRAAdapterConfig) async throws -> LoRAAdapterInfo {
            let info = try await load(config.toRALoRAAdapterConfig())
            return LoRAAdapterInfo(from: info)
        }

        /// Load and apply a generated-proto LoRA adapter config.
        @discardableResult
        public func load(_ config: RALoRAAdapterConfig) async throws -> RALoRAAdapterInfo {
            guard RunAnywhere.isInitialized else {
                throw SDKException.general(.notInitialized, "SDK not initialized")
            }
            return try await CppBridge.LLM.shared.loadLoraAdapter(config)
        }

        /// Remove a specific LoRA adapter by adapter id (file path).
        public func remove(_ adapterId: String) async throws {
            guard RunAnywhere.isInitialized else {
                throw SDKException.general(.notInitialized, "SDK not initialized")
            }
            var config = RALoRAAdapterConfig()
            config.adapterPath = adapterId
            config.adapterID = adapterId
            _ = try await CppBridge.LLM.shared.removeLoraAdapter(config)
        }

        /// Remove all loaded LoRA adapters.
        public func clear() async throws {
            guard RunAnywhere.isInitialized else {
                throw SDKException.general(.notInitialized, "SDK not initialized")
            }
            _ = try await CppBridge.LLM.shared.clearLoraAdaptersProto()
        }

        /// Get info about all currently loaded LoRA adapters.
        public func getLoaded() async throws -> [LoRAAdapterInfo] {
            guard RunAnywhere.isInitialized else {
                throw SDKException.general(.notInitialized, "SDK not initialized")
            }
            return try await CppBridge.LLM.shared.getLoadedLoraAdapters()
        }

        /// Check whether a LoRA adapter is compatible with a model.
        ///
        /// `adapterId` is the path to the adapter GGUF (matching the C ABI
        /// `rac_llm_check_lora_compatibility`). `modelId` is reserved for
        /// future use by the canonical API; the current C ABI checks
        /// against the active model loaded via `loadLLMModel`.
        public func checkCompatibility(
            adapterId: String,
            modelId _: String
        ) async -> LoraCompatibilityResult {
            guard RunAnywhere.isInitialized else {
                return LoraCompatibilityResult(isCompatible: false, error: "SDK not initialized")
            }
            var config = RALoRAAdapterConfig()
            config.adapterPath = adapterId
            do {
                let proto = try await CppBridge.LLM.shared.checkLoraCompatibility(config)
                return LoraCompatibilityResult(from: proto)
            } catch {
                return LoraCompatibilityResult(isCompatible: false, error: error.localizedDescription)
            }
        }

        // MARK: Catalog Operations

        /// Register a LoRA adapter config in the SDK catalog at app startup (CANONICAL_API §3).
        ///
        /// Call this before loading any adapters so the SDK knows what's available.
        /// The `config` carries the adapter path and scale; catalog metadata
        /// (name, description, etc.) is stored internally.
        ///
        /// - Parameter config: `LoRAAdapterConfig` with path and scale.
        public func register(_ config: LoRAAdapterConfig) async throws {
            // Wrap the config into a catalog entry using the path as the id/name.
            let entry = LoraAdapterCatalogEntry(
                id: config.path,
                name: config.path,
                description: "Registered via lora.register(config:)",
                downloadURL: URL(fileURLWithPath: config.path),
                filename: (config.path as NSString).lastPathComponent,
                compatibleModelIds: [],
                fileSize: 0,
                defaultScale: config.scale
            )
            try await register(entry)
        }

        /// Register a LoRA adapter from a full catalog entry.
        ///
        /// This overload accepts `LoraAdapterCatalogEntry` directly, which carries
        /// richer metadata (name, description, download URL, compatible model IDs).
        ///
        /// - Parameter entry: A complete `LoraAdapterCatalogEntry` to register.
        public func register(_ entry: LoraAdapterCatalogEntry) async throws {
            try await register(entry.toRALoraAdapterCatalogEntry())
        }

        /// Register a generated-proto LoRA catalog entry.
        public func register(_ entry: RALoraAdapterCatalogEntry) async throws {
            guard RunAnywhere.isInitialized else {
                throw SDKException.general(.notInitialized, "SDK not initialized")
            }
            _ = try await CppBridge.LoraRegistry.shared.register(entry)
        }

        /// Get all LoRA adapters compatible with a specific model (CANONICAL_API §3).
        ///
        /// - Parameter modelId: Model identifier to filter by.
        /// - Returns: `[LoRAAdapterInfo]` for compatible adapters.
        public func adaptersForModel(_ modelId: String) async -> [LoRAAdapterInfo] {
            let entries = await CppBridge.LoraRegistry.shared.getForModel(modelId)
            return entries.map { entry in
                LoRAAdapterInfo(path: entry.id, scale: entry.defaultScale, applied: false)
            }
        }

        /// Get all registered LoRA adapters (CANONICAL_API §3).
        ///
        /// - Returns: `[LoRAAdapterInfo]` for all registered adapters.
        public func allRegistered() async -> [LoRAAdapterInfo] {
            let entries = await CppBridge.LoraRegistry.shared.getAll()
            return entries.map { entry in
                LoRAAdapterInfo(path: entry.id, scale: entry.defaultScale, applied: false)
            }
        }
    }
}
