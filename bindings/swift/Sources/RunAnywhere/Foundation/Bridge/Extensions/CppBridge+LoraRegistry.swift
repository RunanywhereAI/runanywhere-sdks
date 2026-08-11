// CppBridge+LoraRegistry.swift
// RunAnywhere SDK
//
// LoRA registry bridge - owns the global registry handle used by the generated
// LoRA catalog proto-byte ABI.

import CRACommons

extension CppBridge {

    // MARK: - LoRA Registry Bridge

    /// Actor wrapping the C++ LoRA adapter registry.
    /// Holds an in-memory catalog of adapters registered at startup.
    public actor LoraRegistry {

        /// Shared registry instance
        public static let shared = LoraRegistry()

        private var handle: rac_lora_registry_handle_t?
        private let logger = SDKLogger(category: "CppBridge.LoraRegistry")

        private init() {
            handle = rac_get_lora_registry()
            if handle != nil {
                logger.debug("LoRA registry acquired (global singleton)")
            } else {
                logger.error("Failed to acquire global LoRA registry")
            }
        }

        // Low-level catalog operations are implemented in
        // `Generated/ModalityProtoABI+Generated.swift`. The public actor methods
        // below keep the non-Sendable registry pointer inside this actor.

        /// Resolves the registry handle, lazily reacquiring it from the
        /// commons global singleton if the initial fetch failed.
        private func requireHandle() throws -> rac_lora_registry_handle_t {
            if handle == nil {
                handle = rac_get_lora_registry()
            }
            guard let handle else {
                throw SDKException(code: .initializationFailed, message: "LoRA registry not initialized", category: .internal)
            }
            return handle
        }

        public func register(
            _ request: RALoraAdapterCatalogEntry
        ) throws -> RALoraAdapterCatalogEntry {
            try register(handle: requireHandle(), request)
        }

        public func listCatalog(
            _ request: RALoraAdapterCatalogListRequest
        ) throws -> RALoraAdapterCatalogListResult {
            try listCatalog(handle: requireHandle(), request)
        }

        public func queryCatalog(
            _ request: RALoraAdapterCatalogQuery
        ) throws -> RALoraAdapterCatalogListResult {
            try queryCatalog(handle: requireHandle(), request)
        }

        public func getCatalogEntry(
            _ request: RALoraAdapterCatalogGetRequest
        ) throws -> RALoraAdapterCatalogGetResult {
            try getCatalogEntry(handle: requireHandle(), request)
        }

        // markDownloadCompleted(_:) / importAdapter(_:) were deleted:
        // LoraAdapterDownloadCompletedRequest/Result and
        // LoraAdapterImportRequest/Result were removed outright from
        // idl/lora_options.proto (lora-delete-download-import-bookkeeping).
        // Adapter files are now acquired exclusively through the models
        // domain's download/import verbs; this LoRA domain carries no
        // download/import state of its own — a non-empty
        // RALoraAdapterCatalogEntry.localPath is the only "downloaded"
        // signal that survives. The corresponding C ABI entry points
        // (rac_lora_catalog_mark_download_completed_proto /
        // rac_lora_adapter_import_proto) are retired stubs that always
        // report RAC_ERROR_NOT_IMPLEMENTED.
    }
}
