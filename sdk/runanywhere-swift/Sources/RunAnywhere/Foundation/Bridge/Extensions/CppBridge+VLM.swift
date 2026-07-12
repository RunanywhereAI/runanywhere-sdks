//
//  CppBridge+VLM.swift
//  RunAnywhere SDK
//
//  VLM bridge over the handle-free C++ lifecycle proto API.
//
//  VLM-specific surfaces kept here:
//   - `cancel()` — calls `rac_vlm_cancel_lifecycle_proto`.
//     No handle is threaded; the cancel acquires the lifecycle service
//     internally, mirroring the LLM cancel-proto path.
//

import CRACommons
import Foundation

// MARK: - VLM Component Bridge

extension CppBridge {

    /// VLM component manager
    /// Provides thread-safe access to the C++ VLM component
    public actor VLM {

        /// Shared VLM component instance
        public static let shared = VLM()

        private let logger = SDKLogger(category: "CppBridge.VLM")

        private init() {}

        // MARK: - Model Lifecycle

        /// Cancel ongoing generation via the lifecycle cancel proto.
        ///
        /// The lifecycle ABI acquires the lifecycle-owned
        /// VLM service internally, dispatches `cancel` on its vtable, and
        /// emits canonical `CANCELLATION_EVENT_KIND_*` SDKEvents — keeping
        /// the cancel path consistent with LLM cancellation semantics.
        public func cancel() async {
            do {
                _ = try cancelLifecycle()
            } catch let error as SDKException {
                // No lifecycle VLM loaded is a no-op; surface anything else
                // at warning level (parity with LLM cancel — failures here
                // are not fatal to the caller).
                logger.warning("VLM cancel skipped: \(error.message)")
            } catch {
                logger.warning("VLM cancel skipped: \(error.localizedDescription)")
            }
        }

    }
}
