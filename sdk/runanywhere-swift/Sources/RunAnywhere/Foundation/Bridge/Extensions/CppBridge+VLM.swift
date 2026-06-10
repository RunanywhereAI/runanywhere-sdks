//
//  CppBridge+VLM.swift
//  RunAnywhere SDK
//
//  VLM component bridge - manages C++ VLM component lifecycle.
//
//  Generic scaffolding (handle creation, destroy) lives in
//  `CppBridge.ComponentActor`. The VLM actor exists only to host a
//  per-process handle that `process()`/`processStream()` pass to the
//  proto ABI to satisfy the C signature — the canonical model state
//  is owned by the C++ lifecycle (`rac_model_lifecycle_load_proto`),
//  and `rac_vlm_process[_stream]_proto` route through the lifecycle
//  whenever it is loaded. All VLM-specific load helpers have been
//  removed in favour of that single source of truth.
//
//  VLM-specific surfaces kept here:
//   - `cancel()` — calls `rac_vlm_cancel_lifecycle_proto`.
//     No handle is threaded; the cancel acquires the lifecycle service
//     internally, mirroring the LLM cancel-proto path.
//   - `supportsStreaming` and `state` introspection on the legacy
//     per-handle component (still exposed for parity with sibling
//     modalities; not consulted by SDK consumers).
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

        /// Generic scaffold (handle / destroy). The level-3 handle is never
        /// loaded with a model in V2 — `rac_vlm_process_proto` falls back to
        /// the lifecycle-owned VLM service. The handle survives only to
        /// satisfy the proto ABI's `rac_handle_t` parameter.
        private let inner = ComponentActor(vtable: .vlm)

        private let logger = SDKLogger(category: "CppBridge.VLM")

        private init() {}

        // MARK: - Handle Management

        /// Get or create the VLM component handle
        public func getHandle() async throws -> rac_handle_t {
            try await inner.getHandle()
        }

        // MARK: - Model Lifecycle

        /// Cancel ongoing generation via the lifecycle cancel proto.
        ///
        /// Replaces the legacy handle-based `rac_vlm_component_cancel` path.
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

        /// Check if streaming is supported
        public var supportsStreaming: Bool {
            get async {
                guard let handle = await inner.existingHandle() else { return false }
                return rac_vlm_component_supports_streaming(handle) == RAC_TRUE
            }
        }

        /// Get lifecycle state
        public var state: rac_lifecycle_state_t {
            get async {
                guard let handle = await inner.existingHandle() else { return RAC_LIFECYCLE_STATE_IDLE }
                return rac_vlm_component_get_state(handle)
            }
        }

        // MARK: - Cleanup

        /// Destroy the component
        public func destroy() async {
            await inner.destroy()
        }
    }
}
