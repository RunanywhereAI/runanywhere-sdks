//
//  CppBridge+VAD.swift
//  RunAnywhere SDK
//
//  VAD component bridge - manages C++ VAD component lifecycle
//

import CRACommons
import Foundation

// MARK: - VAD Component Bridge

extension CppBridge {

    /// VAD component manager
    /// Provides thread-safe access to the C++ VAD component
    public actor VAD {

        /// Shared VAD component instance
        public static let shared = VAD()

        private var handle: rac_handle_t?
        private let logger = SDKLogger(category: "CppBridge.VAD")

        private init() {}

        // MARK: - Handle Management

        /// Get or create the VAD component handle
        public func getHandle() throws -> rac_handle_t {
            if let handle = handle {
                return handle
            }

            var newHandle: rac_handle_t?
            let result = rac_vad_component_create(&newHandle)
            guard result == RAC_SUCCESS, let handle = newHandle else {
                throw SDKError.vad(.notInitialized, "Failed to create VAD component: \(result)")
            }

            self.handle = handle
            logger.debug("VAD component created")
            return handle
        }

        // MARK: - State

        /// Check if VAD is initialized
        public var isInitialized: Bool {
            guard let handle = handle else { return false }
            return rac_vad_component_is_initialized(handle) == RAC_TRUE
        }

        // MARK: - Lifecycle

        /// Initialize VAD
        public func initialize() throws {
            let handle = try getHandle()
            let result = rac_vad_component_initialize(handle)
            guard result == RAC_SUCCESS else {
                throw SDKError.vad(.initializationFailed, "Failed to initialize VAD: \(result)")
            }
            logger.info("VAD initialized")
        }

        /// Start VAD processing
        public func start() throws {
            let handle = try getHandle()
            let result = rac_vad_component_start(handle)
            guard result == RAC_SUCCESS else {
                throw SDKError.vad(.processingFailed, "Failed to start VAD: \(result)")
            }
        }

        /// Stop VAD processing
        public func stop() throws {
            let handle = try getHandle()
            let result = rac_vad_component_stop(handle)
            guard result == RAC_SUCCESS else {
                throw SDKError.vad(.processingFailed, "Failed to stop VAD: \(result)")
            }
        }

        /// Cleanup VAD
        public func cleanup() {
            guard let handle = handle else { return }
            rac_vad_component_cleanup(handle)
            logger.info("VAD cleaned up")
        }

        // MARK: - Cleanup

        /// Destroy the component
        public func destroy() {
            if let handle = handle {
                rac_vad_component_destroy(handle)
                self.handle = nil
                logger.debug("VAD component destroyed")
            }
        }
    }
}
