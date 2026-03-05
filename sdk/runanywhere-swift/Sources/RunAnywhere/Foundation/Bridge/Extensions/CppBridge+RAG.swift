//
//  CppBridge+RAG.swift
//  RunAnywhere SDK
//
//  RAG component bridge - manages C++ RAG pipeline lifecycle
//

import CRACommons
import Foundation

// MARK: - RAG Pipeline Bridge

extension CppBridge {

    /// RAG pipeline manager
    /// Provides thread-safe access to the C++ RAG pipeline
    public actor RAG {

        /// Shared RAG pipeline instance
        public static let shared = RAG()

        private var pipeline: OpaquePointer?  // rac_rag_pipeline_t*
        private let logger = SDKLogger(category: "CppBridge.RAG")

        private init() {}

        // MARK: - Pipeline Lifecycle

        /// Create the RAG pipeline with configuration (low-level C overload)
        public func createPipeline(config: rac_rag_config_t) throws {
            // Register RAG module + ONNX embeddings provider if not already registered
            let regResult = rac_backend_rag_register()
            if regResult != RAC_SUCCESS && regResult != RAC_ERROR_MODULE_ALREADY_REGISTERED {
                logger.warning("RAG module registration returned \(regResult)")
            }

            var mutableConfig = config
            var newPipeline: OpaquePointer?
            let result = rac_rag_pipeline_create_standalone(&mutableConfig, &newPipeline)
            guard result == RAC_SUCCESS, let newPipeline else {
                throw SDKError.rag(.notInitialized, "Failed to create RAG pipeline: \(result)")
            }
            self.pipeline = newPipeline
            logger.debug("RAG pipeline created")
        }

        /// Create the RAG pipeline with a Swift-typed configuration.
        ///
        /// Builds the C struct internally so that C string pointer lifetimes are
        /// contained within this synchronous actor method.
        public func createPipeline(swiftConfig: RAGConfiguration) throws {
            try swiftConfig.withCConfig { cConfig in
                try createPipeline(config: cConfig)
            }
        }

        /// Check if pipeline is created
        public var isCreated: Bool { pipeline != nil }

        /// Destroy the pipeline
        public func destroy() {
            guard let pipeline else { return }
            rac_rag_pipeline_destroy(pipeline)
            self.pipeline = nil
            logger.debug("RAG pipeline destroyed")
        }

        // MARK: - Document Management

        /// Add a document to the pipeline
        ///
        /// The document will be split into chunks, embedded, and indexed.
        public func addDocument(text: String, metadataJSON: String?) throws {
            guard let pipeline else {
                throw SDKError.rag(.notInitialized, "RAG pipeline not created")
            }
            let result: rac_result_t
            if let metadataJSON {
                result = text.withCString { textPtr in
                    metadataJSON.withCString { metaPtr in
                        rac_rag_add_document(pipeline, textPtr, metaPtr)
                    }
                }
            } else {
                result = text.withCString { textPtr in
                    rac_rag_add_document(pipeline, textPtr, nil)
                }
            }
            guard result == RAC_SUCCESS else {
                throw SDKError.rag(.invalidInput, "Failed to add document to RAG pipeline: \(result)")
            }
        }

        /// Clear all documents from the pipeline
        public func clearDocuments() throws {
            guard let pipeline else {
                throw SDKError.rag(.notInitialized, "RAG pipeline not created")
            }
            let result = rac_rag_clear_documents(pipeline)
            guard result == RAC_SUCCESS else {
                throw SDKError.rag(.invalidState, "Failed to clear RAG documents: \(result)")
            }
        }

        /// Get document count
        public var documentCount: Int {
            guard let pipeline else { return 0 }
            return Int(rac_rag_get_document_count(pipeline))
        }

        // MARK: - Query

        /// Query the RAG pipeline (low-level C overload).
        ///
        /// Retrieves relevant chunks and generates an answer.
        /// Caller is responsible for calling rac_rag_result_free on the returned result.
        public func query(_ ragQuery: rac_rag_query_t) throws -> rac_rag_result_t {
            guard let pipeline else {
                throw SDKError.rag(.notInitialized, "RAG pipeline not created")
            }
            var mutableQuery = ragQuery
            var result = rac_rag_result_t()
            let status = rac_rag_query(pipeline, &mutableQuery, &result)
            guard status == RAC_SUCCESS else {
                throw SDKError.rag(.generationFailed, "RAG query failed: \(status)")
            }
            return result
        }

        /// Query the RAG pipeline with a Swift-typed options struct.
        ///
        /// Builds the C query struct internally and converts the result to a Swift `RAGResult`.
        /// C memory is freed before returning.
        public func query(swiftOptions: RAGQueryOptions) throws -> RAGResult {
            let swiftResult: RAGResult = try swiftOptions.withCQuery { cQuery in
                var cResult = try query(cQuery)
                defer { rac_rag_result_free(&cResult) }
                return RAGResult(from: cResult)
            }
            return swiftResult
        }
    }
}
