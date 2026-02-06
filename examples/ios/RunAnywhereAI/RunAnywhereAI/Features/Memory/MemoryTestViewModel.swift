//
//  MemoryTestViewModel.swift
//  RunAnywhereAI
//
//  ViewModel for testing the Memory/Vector Search layer.
//  Exercises CppBridge.Memory directly with synthetic vectors.
//

import Foundation
import RunAnywhere
import os

/// Test result entry displayed in the UI
struct MemoryTestResult: Identifiable {
    let id = UUID()
    let name: String
    let passed: Bool
    let detail: String
    let duration: TimeInterval
}

@MainActor
class MemoryTestViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere", category: "MemoryTest")

    @Published var results: [MemoryTestResult] = []
    @Published var isRunning = false
    @Published var statusMessage = "Tap 'Run Tests' to begin"

    private let bridge = CppBridge.Memory.shared
    private let dimension: UInt32 = 8

    // MARK: - Run All Tests

    func runAllTests() {
        guard !isRunning else { return }
        isRunning = true
        results = []
        statusMessage = "Running tests..."

        Task {
            await runTest("Create Index (Flat)") { try await self.testCreateFlat() }
            await runTest("Add Vectors") { try await self.testAddVectors() }
            await runTest("Search (exact match)") { try await self.testSearchExact() }
            await runTest("Search (nearest neighbor)") { try await self.testSearchNearest() }
            await runTest("Get Stats") { try await self.testGetStats() }
            await runTest("Remove Vectors") { try await self.testRemove() }
            await runTest("Save & Load") { try await self.testSaveLoad() }
            await runTest("Destroy Index") { try await self.testDestroy() }
            await runTest("Create Index (HNSW)") { try await self.testCreateHNSW() }
            await runTest("HNSW Add + Search") { try await self.testHNSWAddSearch() }
            await runTest("HNSW Cleanup") { try await self.testDestroy() }

            let passed = results.filter(\.passed).count
            let total = results.count
            statusMessage = "\(passed)/\(total) tests passed"
            isRunning = false
        }
    }

    // MARK: - Individual Tests

    private func testCreateFlat() async throws -> String {
        let config = MemoryConfiguration(
            dimension: dimension,
            metric: .cosine,
            indexType: .flat
        )
        try await bridge.create(config: config)
        guard await bridge.isActive else {
            throw TestError("Index not active after create")
        }
        return "Flat index created (dim=\(dimension))"
    }

    private func testAddVectors() async throws -> String {
        // Add 5 vectors with metadata
        let vectors: [[Float]] = [
            [1, 0, 0, 0, 0, 0, 0, 0],  // id=1: unit vector along dim 0
            [0, 1, 0, 0, 0, 0, 0, 0],  // id=2: unit vector along dim 1
            [0, 0, 1, 0, 0, 0, 0, 0],  // id=3
            [0.7, 0.7, 0, 0, 0, 0, 0, 0],  // id=4: between dim 0 and 1
            [0, 0, 0, 0, 0, 0, 0, 1],  // id=5: unit vector along dim 7
        ]
        let ids: [UInt64] = [1, 2, 3, 4, 5]
        let metadata: [String?] = [
            "{\"label\":\"x-axis\"}", "{\"label\":\"y-axis\"}", "{\"label\":\"z-axis\"}",
            "{\"label\":\"xy-diagonal\"}", "{\"label\":\"w-axis\"}",
        ]

        try await bridge.add(vectors: vectors, ids: ids, metadata: metadata)
        return "Added 5 vectors with metadata"
    }

    private func testSearchExact() async throws -> String {
        // Search for exact match of vector id=1
        let query: [Float] = [1, 0, 0, 0, 0, 0, 0, 0]
        let results = try await bridge.search(query: query, k: 1)

        guard let first = results.first else {
            throw TestError("No results returned")
        }
        guard first.id == 1 else {
            throw TestError("Expected id=1, got id=\(first.id)")
        }
        return "Top result: id=\(first.id), score=\(String(format: "%.4f", first.score))"
    }

    private func testSearchNearest() async throws -> String {
        // Search for a vector close to id=4 (0.7, 0.7, 0, ...)
        let query: [Float] = [0.6, 0.8, 0, 0, 0, 0, 0, 0]
        let results = try await bridge.search(query: query, k: 3)

        guard results.count == 3 else {
            throw TestError("Expected 3 results, got \(results.count)")
        }

        let topIds = results.map(\.id)
        let detail = results.map { "id=\($0.id) score=\(String(format: "%.4f", $0.score))" }
            .joined(separator: ", ")

        // The nearest should be id=4 (xy-diagonal) or id=2 (y-axis)
        guard topIds.contains(4) || topIds.contains(2) else {
            throw TestError("Expected id=4 or id=2 in top 3, got \(topIds)")
        }
        return "Top 3: \(detail)"
    }

    private func testGetStats() async throws -> String {
        let stats = try await bridge.getStats()
        guard stats.numVectors == 5 else {
            throw TestError("Expected 5 vectors, got \(stats.numVectors)")
        }
        guard stats.dimension == dimension else {
            throw TestError("Expected dim=\(dimension), got \(stats.dimension)")
        }
        return "vectors=\(stats.numVectors), dim=\(stats.dimension), mem=\(stats.memoryUsageBytes)B"
    }

    private func testRemove() async throws -> String {
        try await bridge.remove(ids: [5])

        let stats = try await bridge.getStats()
        guard stats.numVectors == 4 else {
            throw TestError("Expected 4 vectors after remove, got \(stats.numVectors)")
        }
        return "Removed id=5, remaining=\(stats.numVectors)"
    }

    private func testSaveLoad() async throws -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("RunAnywhere/Memory")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("test_index.racm").path

        // Save
        try await bridge.save(to: path)

        // Destroy and recreate
        await bridge.destroy()

        // Load
        try await bridge.load(from: path)

        // Verify data survived
        let stats = try await bridge.getStats()
        guard stats.numVectors > 0 else {
            throw TestError("No vectors after load")
        }

        // Search should still work
        let query: [Float] = [1, 0, 0, 0, 0, 0, 0, 0]
        let results = try await bridge.search(query: query, k: 1)
        guard let first = results.first, first.id == 1 else {
            throw TestError("Search after load failed")
        }

        // Cleanup test file
        try? FileManager.default.removeItem(atPath: path)

        return "Save/load round-trip OK, vectors=\(stats.numVectors)"
    }

    private func testDestroy() async throws -> String {
        await bridge.destroy()
        let active = await bridge.isActive
        guard !active else {
            throw TestError("Index still active after destroy")
        }
        return "Index destroyed"
    }

    private func testCreateHNSW() async throws -> String {
        let config = MemoryConfiguration(
            dimension: dimension,
            metric: .cosine,
            indexType: .hnsw,
            hnswM: 16,
            hnswEfConstruction: 100,
            hnswEfSearch: 50
        )
        try await bridge.create(config: config)
        guard await bridge.isActive else {
            throw TestError("HNSW index not active after create")
        }
        return "HNSW index created (dim=\(dimension), M=16)"
    }

    private func testHNSWAddSearch() async throws -> String {
        // Add 100 random vectors
        var vectors: [[Float]] = []
        var ids: [UInt64] = []
        for i in 0..<100 {
            var vec = [Float](repeating: 0, count: Int(dimension))
            for j in 0..<Int(dimension) {
                vec[j] = Float.random(in: -1...1)
            }
            vectors.append(vec)
            ids.append(UInt64(i + 1))
        }

        try await bridge.add(vectors: vectors, ids: ids)

        // Search
        let query = vectors[0]  // Search for the first vector we added
        let results = try await bridge.search(query: query, k: 5)

        guard results.count == 5 else {
            throw TestError("Expected 5 results, got \(results.count)")
        }

        // The first result should be id=1 (exact match)
        guard results.first?.id == 1 else {
            throw TestError("Expected id=1 as top result, got \(String(describing: results.first?.id))")
        }

        return "100 vectors added, top-5 search OK (top id=\(results.first?.id ?? 0))"
    }

    // MARK: - Helpers

    private func runTest(_ name: String, _ test: @escaping () async throws -> String) async {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let detail = try await test()
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            results.append(MemoryTestResult(name: name, passed: true, detail: detail, duration: elapsed))
            logger.info("PASS: \(name) (\(String(format: "%.1f", elapsed * 1000))ms)")
        } catch {
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let msg = error.localizedDescription
            results.append(MemoryTestResult(name: name, passed: false, detail: msg, duration: elapsed))
            logger.error("FAIL: \(name): \(msg)")
        }
    }
}

private struct TestError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { self.errorDescription = message }
}
