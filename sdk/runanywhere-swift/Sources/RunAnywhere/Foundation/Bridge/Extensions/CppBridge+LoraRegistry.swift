// CppBridge+LoraRegistry.swift
// RunAnywhere SDK
//
// LoRA registry bridge - wraps C++ rac_lora_registry_* for adapter catalog management.

import CRACommons
import Foundation

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
            var h: rac_lora_registry_handle_t?
            let result = rac_lora_registry_create(&h)
            if result == RAC_SUCCESS {
                handle = h
                logger.debug("LoRA registry created")
            } else {
                logger.error("Failed to create LoRA registry: \(result)")
            }
        }

        deinit {
            if let h = handle {
                rac_lora_registry_destroy(h)
            }
        }

        // MARK: - Registration

        /// Register a LoRA adapter in the catalog
        public func register(_ entry: LoraAdapterCatalogEntry) throws {
            guard let handle = handle else {
                throw SDKError.general(.initializationFailed, "LoRA registry not initialized")
            }

            // Allocate C strings via strdup so lifetime is independent of Swift strings
            let cId = strdup(entry.id)
            let cName = strdup(entry.name)
            let cDesc = strdup(entry.adapterDescription)
            let cUrl = strdup(entry.downloadURL.absoluteString)
            let cFile = strdup(entry.filename)
            let cCompatIds = entry.compatibleModelIds.map { strdup($0) }
            defer {
                [cId, cName, cDesc, cUrl, cFile].forEach { if let p = $0 { free(p) } }
                cCompatIds.forEach { if let p = $0 { free(p) } }
            }

            var mutableCompatIds = cCompatIds
            let result: rac_result_t = mutableCompatIds.withUnsafeMutableBufferPointer { compatBuf in
                var cEntry = rac_lora_entry_t()
                cEntry.id = cId
                cEntry.name = cName
                cEntry.description = cDesc
                cEntry.download_url = cUrl
                cEntry.filename = cFile
                cEntry.compatible_model_ids = compatBuf.baseAddress
                cEntry.compatible_model_count = entry.compatibleModelIds.count
                cEntry.file_size = entry.fileSize
                cEntry.default_scale = entry.defaultScale
                return rac_lora_registry_register(handle, &cEntry)
            }

            guard result == RAC_SUCCESS else {
                throw SDKError.general(.processingFailed, "Failed to register LoRA adapter '\(entry.id)': \(result)")
            }
            logger.info("LoRA adapter registered: \(entry.id)")
        }

        // MARK: - Queries

        /// Get all registered LoRA adapters
        public func getAll() -> [LoraAdapterCatalogEntry] {
            guard let handle = handle else { return [] }

            var entriesPtr: UnsafeMutablePointer<UnsafeMutablePointer<rac_lora_entry_t>?>?
            var count: Int = 0
            let result = rac_lora_registry_get_all(handle, &entriesPtr, &count)
            guard result == RAC_SUCCESS, let entries = entriesPtr else { return [] }
            defer { rac_lora_entry_array_free(entries, count) }

            return (0..<count).compactMap { i in
                guard let entry = entries[i] else { return nil }
                return LoraAdapterCatalogEntry(from: entry.pointee)
            }
        }

        /// Get LoRA adapters compatible with a specific model
        public func getForModel(_ modelId: String) -> [LoraAdapterCatalogEntry] {
            guard let handle = handle else { return [] }

            var entriesPtr: UnsafeMutablePointer<UnsafeMutablePointer<rac_lora_entry_t>?>?
            var count: Int = 0
            let result = modelId.withCString { mid in
                rac_lora_registry_get_for_model(handle, mid, &entriesPtr, &count)
            }
            guard result == RAC_SUCCESS, let entries = entriesPtr else { return [] }
            defer { rac_lora_entry_array_free(entries, count) }

            return (0..<count).compactMap { i in
                guard let entry = entries[i] else { return nil }
                return LoraAdapterCatalogEntry(from: entry.pointee)
            }
        }
    }
}
