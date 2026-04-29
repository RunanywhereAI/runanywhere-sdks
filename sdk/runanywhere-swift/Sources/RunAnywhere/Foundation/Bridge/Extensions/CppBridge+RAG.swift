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
                throw SDKException.rag(.notInitialized, "Failed to create RAG pipeline: \(result)")
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
                throw SDKException.rag(.notInitialized, "RAG pipeline not created")
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
                throw SDKException.rag(.invalidInput, "Failed to add document to RAG pipeline: \(result)")
            }
        }

        /// Add multiple documents to the pipeline in a single batch call.
        ///
        /// More efficient than calling `addDocument` repeatedly because it avoids
        /// per-call actor-hop overhead and may use a single C++ embedding pass.
        public func addDocumentsBatch(texts: [String], metadataJSONs: [String?]) throws {
            guard let pipeline else {
                throw SDKException.rag(.notInitialized, "RAG pipeline not created")
            }
            guard !texts.isEmpty else { return }
            let count = texts.count

            // Convert Swift strings to UTF-8 C strings via Data buffers so they
            // remain valid pointers for the entire duration of the C call.
            let textBuffers: [ContiguousArray<CChar>] = texts.map { s in
                ContiguousArray(s.utf8CString)
            }
            let metaBuffers: [ContiguousArray<CChar>?] = (0..<count).map { i -> ContiguousArray<CChar>? in
                guard metadataJSONs.indices.contains(i), let m = metadataJSONs[i] else { return nil }
                return ContiguousArray(m.utf8CString)
            }

            var textPtrs: [UnsafePointer<CChar>?] = textBuffers.map { buf in
                buf.withUnsafeBufferPointer { $0.baseAddress }
            }
            var metaPtrs: [UnsafePointer<CChar>?] = metaBuffers.map { buf in
                buf?.withUnsafeBufferPointer { $0.baseAddress }
            }

            let result = textPtrs.withUnsafeMutableBufferPointer { tBuf in
                metaPtrs.withUnsafeMutableBufferPointer { mBuf in
                    rac_rag_add_documents_batch(
                        pipeline,
                        tBuf.baseAddress,
                        mBuf.baseAddress,
                        count
                    )
                }
            }
            guard result == RAC_SUCCESS else {
                throw SDKException.rag(.invalidInput, "Failed to add document batch: \(result)")
            }
        }

        /// Get pipeline statistics as a `RARAGStatistics` proto, decoded from the JSON string
        /// returned by `rac_rag_get_statistics`.
        public func getStatistics() throws -> RARAGStatistics {
            guard let pipeline else {
                throw SDKException.rag(.notInitialized, "RAG pipeline not created")
            }
            var statsJsonPtr: UnsafeMutablePointer<CChar>?
            let result = rac_rag_get_statistics(pipeline, &statsJsonPtr)
            guard result == RAC_SUCCESS, let statsJsonPtr else {
                throw SDKException.rag(.generationFailed, "Failed to get RAG statistics: \(result)")
            }
            defer { free(statsJsonPtr) }
            let jsonString = String(cString: statsJsonPtr)

            // The C layer returns a JSON string; decode the proto fields manually.
            var stats = RARAGStatistics()
            if let data = jsonString.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                stats.indexedDocuments = obj["indexed_documents"].flatMap { $0 as? Int }.map { Int64($0) } ?? 0
                stats.indexedChunks = obj["indexed_chunks"].flatMap { $0 as? Int }.map { Int64($0) } ?? 0
                stats.totalTokensIndexed = obj["total_tokens_indexed"].flatMap { $0 as? Int }.map { Int64($0) } ?? 0
                stats.lastUpdatedMs = obj["last_updated_ms"].flatMap { $0 as? Int }.map { Int64($0) } ?? 0
                if let path = obj["index_path"] as? String { stats.indexPath = path }
            }
            return stats
        }

        /// Clear all documents from the pipeline
        public func clearDocuments() throws {
            guard let pipeline else {
                throw SDKException.rag(.notInitialized, "RAG pipeline not created")
            }
            let result = rac_rag_clear_documents(pipeline)
            guard result == RAC_SUCCESS else {
                throw SDKException.rag(.invalidState, "Failed to clear RAG documents: \(result)")
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
                throw SDKException.rag(.notInitialized, "RAG pipeline not created")
            }
            var mutableQuery = ragQuery
            var result = rac_rag_result_t()
            let status = rac_rag_query(pipeline, &mutableQuery, &result)
            guard status == RAC_SUCCESS else {
                throw SDKException.rag(.generationFailed, "RAG query failed: \(status)")
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
