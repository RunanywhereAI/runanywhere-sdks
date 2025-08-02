//
//  BenchmarkSuite.swift
//  RunAnywhere SDK
//
//  Compatibility wrapper for BenchmarkService
//

import Foundation

/// Compatibility wrapper maintaining original BenchmarkSuite API
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public class BenchmarkSuite {
    public static let shared = BenchmarkSuite()

    // MARK: - Properties

    private let benchmarkService: BenchmarkService
    private let exporterFactory: ExporterFactory

    public var isRunning: Bool {
        get async { await benchmarkService.isRunning }
    }

    public var currentProgress: Double {
        get async { await benchmarkService.currentProgress }
    }

    public var currentBenchmark: String {
        get async { await benchmarkService.currentBenchmark }
    }

    public private(set) var results: [BenchmarkResult] = []

    // MARK: - Initialization

    private init() {
        self.benchmarkService = BenchmarkService()
        self.exporterFactory = ExporterFactory()
    }

    // MARK: - Public Methods

    public func runFullBenchmark(
        services: [String: LLMService],
        options: BenchmarkOptions = .default,
        prompts: [BenchmarkPrompt]? = nil
    ) async throws -> BenchmarkReport {
        let report = try await benchmarkService.runFullBenchmark(
            services: services,
            options: options,
            prompts: prompts
        )
        results = report.results
        return report
    }

    public func runQuickBenchmark(
        service: LLMService,
        serviceName: String
    ) async throws -> QuickBenchmarkResult {
        try await benchmarkService.runQuickBenchmark(
            service: service,
            serviceName: serviceName
        )
    }

    public func compareServices(
        _ service1: LLMService,
        service1Name: String,
        _ service2: LLMService,
        service2Name: String,
        prompt: String? = nil
    ) async throws -> ComparisonResult {
        try await benchmarkService.compareServices(
            service1,
            service1Name: service1Name,
            service2,
            service2Name: service2Name,
            prompt: prompt
        )
    }

    public func exportResults(format: BenchmarkExportFormat) throws -> Data {
        try exporterFactory.export(results: results, format: format)
    }
}
