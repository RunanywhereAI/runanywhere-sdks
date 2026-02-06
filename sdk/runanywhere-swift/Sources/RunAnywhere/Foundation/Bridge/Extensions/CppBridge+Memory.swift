//
//  CppBridge+Memory.swift
//  RunAnywhere SDK
//
//  Memory component bridge - manages C++ vector search component lifecycle.
//

import CRACommons
import Foundation

// MARK: - Memory Component Bridge

extension CppBridge {

    /// Memory component manager
    /// Provides thread-safe access to C++ vector search operations.
    public actor Memory {

        /// Shared memory component instance
        public static let shared = Memory()

        private var handle: rac_handle_t?
        private var currentDimension: UInt32 = 0
        private let logger = SDKLogger(category: "CppBridge.Memory")

        private init() {}

        // MARK: - Index Lifecycle

        /// Create a new memory index
        public func create(config: MemoryConfiguration) throws {
            // Destroy existing index if any
            destroyIndex()

            var cConfig = rac_memory_config_t()
            cConfig.dimension = config.dimension
            cConfig.metric = rac_distance_metric_t(rawValue: UInt32(config.metric.rawValue))
            cConfig.index_type = rac_index_type_t(rawValue: UInt32(config.indexType.rawValue))
            cConfig.hnsw_m = config.hnswM
            cConfig.hnsw_ef_construction = config.hnswEfConstruction
            cConfig.hnsw_ef_search = config.hnswEfSearch
            cConfig.max_elements = config.maxElements

            var newHandle: rac_handle_t?
            let result = rac_memory_create(&cConfig, &newHandle)
            guard result == RAC_SUCCESS, let h = newHandle else {
                throw SDKError.memory(.initializationFailed,
                                       "Failed to create memory index: \(result)")
            }

            self.handle = h
            self.currentDimension = config.dimension
            logger.info("Memory index created: dim=\(config.dimension), type=\(config.indexType)")
        }

        /// Check if an index is active
        public var isActive: Bool {
            handle != nil
        }

        /// Get the current index dimension
        public var dimension: UInt32 {
            currentDimension
        }

        // MARK: - Vector Operations

        /// Add vectors with IDs and optional metadata
        public func add(vectors: [[Float]], ids: [UInt64], metadata: [String?]? = nil) throws {
            let handle = try getHandle()
            let count = UInt32(vectors.count)
            guard count > 0 else { return }

            // Flatten vectors into contiguous array
            let flat = vectors.flatMap { $0 }

            // Prepare metadata C strings
            var metadataPointers: [UnsafePointer<CChar>?]?
            var metadataBuffers: [Data] = []

            if let metadata = metadata {
                var ptrs = [UnsafePointer<CChar>?]()
                for meta in metadata {
                    if let m = meta {
                        let data = Data(m.utf8 + [0])
                        metadataBuffers.append(data)
                        ptrs.append(nil) // Will set in withUnsafeBytes
                    } else {
                        ptrs.append(nil)
                    }
                }
                metadataPointers = ptrs
            }

            let result: rac_result_t
            if let metadata = metadata {
                // Use a simpler approach - create C string arrays
                var cStrings = metadata.map { $0?.withCString { strdup($0) } ?? nil }
                defer { cStrings.forEach { free($0) } }

                result = flat.withUnsafeBufferPointer { vecBuf in
                    ids.withUnsafeBufferPointer { idBuf in
                        cStrings.withUnsafeMutableBufferPointer { metaBuf in
                            let metaPtr = UnsafeMutableRawPointer(metaBuf.baseAddress!)
                                .assumingMemoryBound(to: UnsafePointer<CChar>?.self)
                            return rac_memory_add(handle, vecBuf.baseAddress, idBuf.baseAddress,
                                                  metaPtr, count)
                        }
                    }
                }
            } else {
                result = flat.withUnsafeBufferPointer { vecBuf in
                    ids.withUnsafeBufferPointer { idBuf in
                        rac_memory_add(handle, vecBuf.baseAddress, idBuf.baseAddress, nil, count)
                    }
                }
            }

            guard result == RAC_SUCCESS else {
                throw SDKError.memory(.processingFailed,
                                       "Failed to add vectors: \(result)")
            }
        }

        /// Search for k nearest neighbors
        public func search(query: [Float], k: Int) throws -> [MemorySearchResult] {
            let handle = try getHandle()

            var cResults = rac_memory_search_results_t()

            let result = query.withUnsafeBufferPointer { buf in
                rac_memory_search(handle, buf.baseAddress, UInt32(k), &cResults)
            }

            guard result == RAC_SUCCESS else {
                throw SDKError.memory(.processingFailed,
                                       "Search failed: \(result)")
            }

            defer { rac_memory_search_results_free(&cResults) }

            var results: [MemorySearchResult] = []
            for i in 0..<Int(cResults.count) {
                let r = cResults.results[i]
                var metadata: [String: Any]?
                if let metaStr = r.metadata {
                    let str = String(cString: metaStr)
                    if let data = str.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        metadata = json
                    }
                }
                results.append(MemorySearchResult(id: r.id, score: r.score, metadata: metadata))
            }

            return results
        }

        /// Remove vectors by IDs
        public func remove(ids: [UInt64]) throws {
            let handle = try getHandle()
            let count = UInt32(ids.count)
            guard count > 0 else { return }

            let result = ids.withUnsafeBufferPointer { buf in
                rac_memory_remove(handle, buf.baseAddress, count)
            }

            guard result == RAC_SUCCESS else {
                throw SDKError.memory(.processingFailed,
                                       "Failed to remove vectors: \(result)")
            }
        }

        /// Save index to disk
        public func save(to path: String) throws {
            let handle = try getHandle()
            let result = path.withCString { rac_memory_save(handle, $0) }
            guard result == RAC_SUCCESS else {
                throw SDKError.memory(.fileWriteFailed,
                                       "Failed to save index: \(result)")
            }
            logger.info("Memory index saved to: \(path)")
        }

        /// Load index from disk
        public func load(from path: String) throws {
            destroyIndex()

            var newHandle: rac_handle_t?
            let result = path.withCString { rac_memory_load($0, &newHandle) }
            guard result == RAC_SUCCESS, let h = newHandle else {
                throw SDKError.memory(.fileReadFailed,
                                       "Failed to load index: \(result)")
            }

            self.handle = h

            // Get dimension from stats
            var stats = rac_memory_stats_t()
            if rac_memory_get_stats(h, &stats) == RAC_SUCCESS {
                self.currentDimension = stats.dimension
            }

            logger.info("Memory index loaded from: \(path)")
        }

        /// Get index statistics
        public func getStats() throws -> MemoryStats {
            let handle = try getHandle()
            var cStats = rac_memory_stats_t()
            let result = rac_memory_get_stats(handle, &cStats)
            guard result == RAC_SUCCESS else {
                throw SDKError.memory(.processingFailed,
                                       "Failed to get stats: \(result)")
            }

            return MemoryStats(
                numVectors: cStats.num_vectors,
                dimension: cStats.dimension,
                metric: DistanceMetric(rawValue: Int32(cStats.metric.rawValue)) ?? .cosine,
                indexType: MemoryIndexType(rawValue: Int32(cStats.index_type.rawValue)) ?? .hnsw,
                memoryUsageBytes: cStats.memory_usage_bytes
            )
        }

        // MARK: - Handle Management

        private func getHandle() throws -> rac_handle_t {
            guard let handle = handle else {
                throw SDKError.memory(.notInitialized,
                                       "Memory index not created. Call create() first.")
            }
            return handle
        }

        /// Destroy the current index
        public func destroy() {
            destroyIndex()
        }

        private func destroyIndex() {
            if let handle = handle {
                rac_memory_destroy(handle)
                self.handle = nil
                self.currentDimension = 0
                logger.debug("Memory index destroyed")
            }
        }
    }
}
