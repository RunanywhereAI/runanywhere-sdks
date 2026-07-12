// RunAnywhere+LoRA.swift
// RunAnywhere SDK
//
// Public API for LoRA adapter management - namespaced under
// `RunAnywhere.lora.*` per the canonical cross-SDK spec
// (CANONICAL_API §3 - LoRA).
//
// Runtime operations delegate to the generated LoRA proto ABI through
// CppBridge.LLM; catalog operations delegate to CppBridge.LoraRegistry.

import Foundation

// MARK: - LoRA Capability Namespace

public extension RunAnywhere {

    /// Capability accessor for LoRA adapter management.
    ///
    /// Mirrors the namespaced `lora.*` shape used by the other SDKs
    /// (Kotlin/Flutter/RN/Web). All eight canonical methods live on
    /// the returned `LoRA` value.
    static var lora: LoRA { LoRA() }

    /// Stateless namespace exposing the generated LoRA surface.
    /// Backed by the C ABI via `CppBridge.LLM` (runtime ops) and
    /// `CppBridge.LoraRegistry` (catalog ops).
    struct LoRA: Sendable {

        // MARK: Runtime Operations

        /// Apply one or more LoRA adapters to the currently loaded model.
        ///
        /// - Parameter request: Generated apply request carrying adapter configs.
        /// - Returns: Generated apply result from commons.
        @discardableResult
        public func apply(_ request: RALoRAApplyRequest) async throws -> RALoRAApplyResult {
            return try await CppBridge.LLM.shared.applyLoraAdapters(request)
        }

        /// Apply a registered catalog adapter to the currently loaded model.
        ///
        /// This preserves the catalog adapter id in the generated apply request,
        /// allowing commons to validate the adapter against the loaded base model.
        @discardableResult
        public func apply(
            _ entry: RALoraAdapterCatalogEntry,
            localPath: String? = nil,
            scale: Float? = nil,
            replaceExisting: Bool = false
        ) async throws -> RALoRAApplyResult {
            let adapterPath = localPath ?? entry.localPath
            guard !adapterPath.isEmpty else {
                throw SDKException(
                    code: .invalidArgument,
                    message: "LoRA catalog adapter '\(entry.id)' has no local path",
                    category: .internal
                )
            }

            var config = RALoRAAdapterConfig()
            config.adapterPath = adapterPath
            config.scale = scale ?? (entry.defaultScale > 0 ? entry.defaultScale : 1.0)
            if !entry.id.isEmpty {
                config.adapterID = entry.id
            }

            var request = RALoRAApplyRequest()
            request.adapters = [config]
            request.replaceExisting = replaceExisting
            return try await apply(request)
        }

        /// Same as `apply(_:localPath:scale:replaceExisting:)`, with a name
        /// that is easy to mirror in SDKs without overloads.
        @discardableResult
        public func applyCatalogAdapter(
            _ entry: RALoraAdapterCatalogEntry,
            localPath: String? = nil,
            scale: Float? = nil,
            replaceExisting: Bool = false
        ) async throws -> RALoRAApplyResult {
            try await apply(entry, localPath: localPath, scale: scale, replaceExisting: replaceExisting)
        }

        /// Remove one or more LoRA adapters, or clear all adapters.
        ///
        /// - Parameter request: Generated proto remove request carrying adapter ids,
        ///   adapter paths, or `clearAll_p`.
        /// - Returns: Generated LoRA state after removal.
        @discardableResult
        public func remove(_ request: RALoRARemoveRequest) async throws -> RALoRAState {
            return try await CppBridge.LLM.shared.removeLoraAdapters(request)
        }

        /// Get info about all currently loaded LoRA adapters.
        public func list() async throws -> RALoRAState {
            return try await CppBridge.LLM.shared.listLoraAdapters(RALoRAState())
        }

        /// Get the LoRA service state reported by commons.
        public func state() async throws -> RALoRAState {
            return try await CppBridge.LLM.shared.getLoraState(RALoRAState())
        }

        /// Check whether a LoRA adapter is compatible with a model.
        ///
        /// The lifecycle-aware C ABI resolves the active LLM component
        /// internally; callers no longer need to thread a handle.
        public func checkCompatibility(_ config: RALoRAAdapterConfig) async -> RALoraCompatibilityResult {
            do {
                return try await CppBridge.LLM.shared.checkLoraCompatibility(config)
            } catch {
                return incompatibleResult(error.localizedDescription)
            }
        }

        // MARK: Catalog Operations

        /// Register a LoRA adapter from a full catalog entry.
        @discardableResult
        public func register(_ entry: RALoraAdapterCatalogEntry) async throws -> RALoraAdapterCatalogEntry {
            guard RunAnywhere.isInitialized else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            return try await CppBridge.LoraRegistry.shared.register(entry)
        }

        /// List LoRA catalog entries using the generated catalog request/result ABI.
        public func listCatalog(
            _ request: RALoraAdapterCatalogListRequest = RALoraAdapterCatalogListRequest()
        ) async throws -> RALoraAdapterCatalogListResult {
            guard RunAnywhere.isInitialized else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            return try await CppBridge.LoraRegistry.shared.listCatalog(request)
        }

        /// Query LoRA catalog entries using the generated catalog query/result ABI.
        public func queryCatalog(
            _ query: RALoraAdapterCatalogQuery
        ) async throws -> RALoraAdapterCatalogListResult {
            guard RunAnywhere.isInitialized else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            return try await CppBridge.LoraRegistry.shared.queryCatalog(query)
        }

        /// Fetch one LoRA catalog entry by generated request.
        public func getCatalogEntry(
            _ request: RALoraAdapterCatalogGetRequest
        ) async throws -> RALoraAdapterCatalogGetResult {
            guard RunAnywhere.isInitialized else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            return try await CppBridge.LoraRegistry.shared.getCatalogEntry(request)
        }

        /// Persist native-reported LoRA adapter download completion in commons.
        ///
        /// Swift owns the URLSession/file work. Commons owns the generated catalog
        /// state update once the stable local path is known.
        @discardableResult
        public func markDownloadCompleted(
            _ request: RALoraAdapterDownloadCompletedRequest
        ) async throws -> RALoraAdapterDownloadCompletedResult {
            guard RunAnywhere.isInitialized else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            return try await CppBridge.LoraRegistry.shared.markDownloadCompleted(request)
        }

        /// Persist native-reported LoRA adapter import completion in commons.
        ///
        /// This uses the generated download-completed message with `imported`
        /// asserted, matching the IDL contract for platform file-picker/import
        /// completion.
        @discardableResult
        public func markImportCompleted(
            _ request: RALoraAdapterDownloadCompletedRequest
        ) async throws -> RALoraAdapterDownloadCompletedResult {
            var importRequest = request
            importRequest.imported = true
            if importRequest.statusMessage.isEmpty {
                importRequest.statusMessage = "import completed"
            }
            return try await markDownloadCompleted(importRequest)
        }

        /// Get all LoRA adapters compatible with a specific model (CANONICAL_API §3).
        ///
        /// - Parameter modelId: Model identifier to filter by.
        /// - Returns: Generated catalog entries for compatible adapters.
        public func adaptersForModel(_ modelId: String) async throws -> [RALoraAdapterCatalogEntry] {
            var query = RALoraAdapterCatalogQuery()
            query.modelID = modelId
            let result = try await queryCatalog(query)
            guard result.success else {
                throw SDKException(
                    code: .processingFailed,
                    message: result.errorMessage.isEmpty ? "LoRA catalog query failed" : result.errorMessage,
                    category: .internal
                )
            }
            return result.entries
        }

        /// Get all registered LoRA adapters (CANONICAL_API §3).
        ///
        /// - Returns: Generated catalog entries for all registered adapters.
        public func allRegistered() async throws -> [RALoraAdapterCatalogEntry] {
            let result = try await listCatalog()
            guard result.success else {
                throw SDKException(
                    code: .processingFailed,
                    message: result.errorMessage.isEmpty ? "LoRA catalog list failed" : result.errorMessage,
                    category: .internal
                )
            }
            return result.entries
        }

        private func incompatibleResult(_ message: String) -> RALoraCompatibilityResult {
            var result = RALoraCompatibilityResult()
            result.isCompatible = false
            result.errorMessage = message
            return result
        }
    }
}
