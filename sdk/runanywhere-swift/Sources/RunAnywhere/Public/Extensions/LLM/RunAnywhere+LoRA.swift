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
        public func apply(_ request: RALoraApplyRequest) async throws -> RALoraApplyResult {
            return try await CppBridge.LLM.shared.applyLoraAdapters(request)
        }

        /// Apply a registered catalog adapter to the currently loaded model.
        ///
        /// This preserves the catalog adapter id in the generated apply request,
        /// allowing commons to validate the adapter against the loaded base model.
        ///
        /// `replaceExisting` keeps its historical name and `false` default for
        /// public API stability. Internally it inverts onto the wire field
        /// `keepExisting` (idl/lora_options.proto polarity flip: zero-value
        /// `keepExisting=false` now means SET-semantics replacement, matching
        /// Diffusers `set_adapters`/llama.cpp `llama_set_adapters_lora`, while
        /// the old zero-value `replaceExisting=false` meant "stack"). So the
        /// default `replaceExisting: false` (stack, unchanged behavior) maps
        /// to `keepExisting: true`.
        @discardableResult
        public func apply(
            _ entry: RALoraAdapterCatalogEntry,
            localPath: String? = nil,
            scale: Float? = nil,
            replaceExisting: Bool = false
        ) async throws -> RALoraApplyResult {
            let adapterPath = localPath ?? entry.localPath
            guard !adapterPath.isEmpty else {
                throw SDKException(
                    code: .invalidArgument,
                    message: "LoRA catalog adapter '\(entry.id)' has no local path",
                    category: .internal
                )
            }

            var config = RALoraAdapterConfig()
            config.adapterPath = adapterPath
            // Leave scale unset when the caller omits it so commons
            // resolve_effective_lora_scale owns catalog/1.0 fallback
            // (including honoring explicit catalog 0.0).
            if let scale {
                config.scale = scale
            }
            if !entry.id.isEmpty {
                config.adapterID = entry.id
            }

            var request = RALoraApplyRequest()
            request.adapters = [config]
            request.keepExisting = !replaceExisting
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
        ) async throws -> RALoraApplyResult {
            try await apply(entry, localPath: localPath, scale: scale, replaceExisting: replaceExisting)
        }

        /// Remove one or more LoRA adapters, or clear all adapters.
        ///
        /// - Parameter request: Generated proto remove request carrying adapter ids,
        ///   adapter paths, or `clearAll_p`.
        /// - Returns: Generated LoRA state after removal.
        @discardableResult
        public func remove(_ request: RALoraRemoveRequest) async throws -> RALoraState {
            return try await CppBridge.LLM.shared.removeLoraAdapters(request)
        }

        /// List the adapters currently applied to the loaded model.
        ///
        /// - Throws: `SDKException` when the adapter list cannot be read.
        public func list() async throws -> LoraState {
            LoraState(proto: try await CppBridge.LLM.shared.listLoraAdapters(RALoraState()))
        }

        /// Get the LoRA service state reported by commons.
        public func state() async throws -> RALoraState {
            return try await CppBridge.LLM.shared.getLoraState(RALoraState())
        }

        /// Check whether a LoRA adapter is compatible with a model.
        ///
        /// The lifecycle-aware C ABI resolves the active LLM component
        /// internally; callers no longer need to thread a handle.
        public func checkCompatibility(_ config: RALoraAdapterConfig) async -> RALoraCompatibilityResult {
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
            guard RunAnywhere.isReady else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            return try await CppBridge.LoraRegistry.shared.register(entry)
        }

        /// List LoRA catalog entries using the generated catalog request/result ABI.
        public func listCatalog(
            _ request: RALoraAdapterCatalogListRequest = RALoraAdapterCatalogListRequest()
        ) async throws -> RALoraAdapterCatalogListResult {
            guard RunAnywhere.isReady else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            return try await CppBridge.LoraRegistry.shared.listCatalog(request)
        }

        /// Query LoRA catalog entries using the generated catalog query/result ABI.
        public func queryCatalog(
            _ query: RALoraAdapterCatalogQuery
        ) async throws -> RALoraAdapterCatalogListResult {
            guard RunAnywhere.isReady else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            return try await CppBridge.LoraRegistry.shared.queryCatalog(query)
        }

        /// Fetch one LoRA catalog entry by generated request.
        public func getCatalogEntry(
            _ request: RALoraAdapterCatalogGetRequest
        ) async throws -> RALoraAdapterCatalogGetResult {
            guard RunAnywhere.isReady else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            return try await CppBridge.LoraRegistry.shared.getCatalogEntry(request)
        }

        // markDownloadCompleted(_:) / markImportCompleted(_:) were deleted:
        // LoraAdapterDownloadCompletedRequest/Result was removed outright
        // from idl/lora_options.proto (lora-delete-download-import-bookkeeping)
        // with no replacement message. Adapter files are now acquired
        // exclusively through the models domain's download/import verbs
        // (see RunAnywhere+LoRADownload.swift's `download`/`importAdapter`);
        // a non-empty `RALoraAdapterCatalogEntry.localPath` is the only
        // "downloaded" signal that survives. Any caller of the old verbs
        // needs to migrate to the models-domain download/import path.

        /// Get all LoRA adapters compatible with a specific model (CANONICAL_API §3).
        ///
        /// - Parameter modelId: Model identifier to filter by.
        /// - Returns: Generated catalog entries for compatible adapters.
        public func adaptersForModel(_ modelId: String) async throws -> [RALoraAdapterCatalogEntry] {
            var query = RALoraAdapterCatalogQuery()
            query.modelID = modelId
            let result = try await queryCatalog(query)
            guard !result.hasError else {
                throw SDKException(proto: result.error)
            }
            return result.entries
        }

        /// Get all registered LoRA adapters (CANONICAL_API §3).
        ///
        /// - Returns: Generated catalog entries for all registered adapters.
        public func allRegistered() async throws -> [RALoraAdapterCatalogEntry] {
            let result = try await listCatalog()
            guard !result.hasError else {
                throw SDKException(proto: result.error)
            }
            return result.entries
        }

        private func incompatibleResult(_ message: String) -> RALoraCompatibilityResult {
            var result = RALoraCompatibilityResult()
            result.isCompatible = false
            result.error = RASDKError.make(
                code: .processingFailed,
                message: message,
                category: .component
            )
            return result
        }
    }
}
