//
//  CppBridge+RAG.swift
//  RunAnywhere SDK
//
//  RAG component bridge - manages C++ RAG pipeline lifecycle
//

import CRACommons

// MARK: - RAG Pipeline Bridge

extension CppBridge {

    /// RAG pipeline manager
    /// Provides thread-safe access to the C++ RAG pipeline
    public actor RAG {

        /// Shared RAG pipeline instance
        public static let shared = RAG()

        private var protoSession: rac_handle_t?
        private let logger = SDKLogger(category: "CppBridge.RAG")

        private init() {}

        // MARK: - Pipeline Lifecycle

        /// Check if pipeline is created
        public var isCreated: Bool { protoSession != nil }

        /// Destroy the pipeline
        public func destroy() {
            if let protoSession {
                destroyRAGProtoSessionIfAvailable(protoSession)
                self.protoSession = nil
                logger.debug("RAG proto session destroyed")
            }
        }

        func setProtoSession(_ session: rac_handle_t) {
            if let existing = protoSession {
                destroyRAGProtoSessionIfAvailable(existing)
            }
            protoSession = session
            logger.debug("RAG proto session created")
        }

        func requireProtoSession() throws -> rac_handle_t {
            guard let protoSession else {
                throw SDKException(code: .notInitialized, message: "RAG proto session not created", category: .component)
            }
            return protoSession
        }
    }
}
