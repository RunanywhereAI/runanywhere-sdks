//
//  BenchmarkStore.swift
//  RunAnywhereAI
//
//  JSON persistence for benchmark runs in Documents directory.
//

import Foundation

final class BenchmarkStore: Sendable {
    private static let fileName = "benchmarks.json"
    private static let maxRuns = 50

    private static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    func loadRuns() -> [BenchmarkRun] {
        guard FileManager.default.fileExists(atPath: Self.fileURL.path) else { return [] }
        guard let data = try? Data(contentsOf: Self.fileURL) else { return [] }
        return (try? Self.decoder.decode([BenchmarkRun].self, from: data)) ?? []
    }

    func save(run: BenchmarkRun) {
        var runs = loadRuns()
        runs.append(run)
        // Keep only most recent
        if runs.count > Self.maxRuns {
            runs = Array(runs.suffix(Self.maxRuns))
        }
        if let data = try? Self.encoder.encode(runs) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: Self.fileURL)
    }
}
