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

        // Catalog operations are implemented in
        // `Generated/ModalityProtoABI+Generated.swift` (proto-first APIs that
        // take the registry handle explicitly). Callers fetch the handle via
        // `requireHandle()` before invoking those methods.

        /// Resolves the registry handle, lazily reacquiring it from the
        /// commons global singleton if the initial fetch failed.
        public func requireHandle() throws -> rac_lora_registry_handle_t {
            if handle == nil {
                handle = rac_get_lora_registry()
            }
            guard let handle else {
                throw SDKException(code: .initializationFailed, message: "LoRA registry not initialized", category: .internal)
            }
            return handle
        }
    }
}
