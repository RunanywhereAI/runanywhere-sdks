//
//  BenchmarkService.swift
//  RunAnywhere SDK
//
//  Main benchmark orchestration service
//

import Foundation

/// Main benchmark service implementation
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public actor BenchmarkService: @preconcurrency BenchmarkRunner {
    // MARK: - Properties

    public private(set) var isRunning = false
    public private(set) var currentProgress: Double = 0.0
    public private(set) var currentBenchmark: String = ""

    private let executor: BenchmarkExecutor
    private let promptManager: PromptManager
    private let metricsAggregator: MetricsAggregator
    private let comparisonEngine: ComparisonEngine
    private let reportGenerator: BenchmarkReportGenerator
    private let logger = SDKLogger(category: "BenchmarkService")

    // MARK: - Initialization

    /// Public convenience initializer
    public init() {
        let performanceMonitor = MonitoringService.shared
        self.executor = BenchmarkExecutor(performanceMonitor: performanceMonitor)
        self.promptManager = PromptManager()
        self.metricsAggregator = MetricsAggregator()
        self.comparisonEngine = ComparisonEngine()
        self.reportGenerator = BenchmarkReportGenerator(performanceMonitor: performanceMonitor)
    }

    /// Internal initializer for dependency injection
    internal init(
        executor: BenchmarkExecutor? = nil,
        promptManager: PromptManager? = nil,
        metricsAggregator: MetricsAggregator? = nil,
        comparisonEngine: ComparisonEngine? = nil,
        reportGenerator: BenchmarkReportGenerator? = nil
    ) {
        let performanceMonitor = MonitoringService.shared
        self.executor = executor ?? BenchmarkExecutor(performanceMonitor: performanceMonitor)
        self.promptManager = promptManager ?? PromptManager()
        self.metricsAggregator = metricsAggregator ?? MetricsAggregator()
        self.comparisonEngine = comparisonEngine ?? ComparisonEngine()
        self.reportGenerator = reportGenerator ?? BenchmarkReportGenerator(performanceMonitor: performanceMonitor)
    }

    // MARK: - BenchmarkRunner Implementation

    public func runFullBenchmark(
        services: [String: LLMService],
        options: BenchmarkOptions = .default,
        prompts: [BenchmarkPrompt]? = nil
    ) async throws -> BenchmarkReport {
        guard !isRunning else {
            throw BenchmarkError.alreadyRunning
        }

        guard !services.isEmpty else {
            throw BenchmarkError.noServicesProvided
        }

        isRunning = true
        currentProgress = 0.0
        defer {
            isRunning = false
            currentProgress = 1.0
        }

        logger.info("Starting full benchmark with \(services.count) services")

        let benchmarkPrompts = prompts ?? promptManager.defaultPrompts
        let totalTests = services.count * benchmarkPrompts.count * options.iterations
        var completedTests = 0
        var allSingleResults: [SingleRunResult] = []
        var errorResults: [BenchmarkResult] = []

        // Execute benchmarks for each service
        for (serviceName, service) in services {
            currentBenchmark = "Testing \(serviceName)"

            do {
                // Warmup if requested
                if options.includeWarmup {
                    try await executor.warmupService(service, name: serviceName)
                }

                // Run benchmarks for each prompt
                for prompt in benchmarkPrompts {
                    let results = try await executor.benchmarkPrompt(
                        service: service,
                        serviceName: serviceName,
                        prompt: prompt,
                        iterations: options.iterations
                    )

                    // Collect single results for aggregation
                    for result in results {
                        allSingleResults.append(result)
                    }

                    completedTests += options.iterations
                    currentProgress = Double(completedTests) / Double(totalTests)
                }
            } catch {
                logger.error("Failed to benchmark \(serviceName): \(error)")
                errorResults.append(createErrorResult(
                    serviceName: serviceName,
                    framework: service.modelInfo?.framework,
                    error: error
                ))
            }
        }

        // Aggregate single results into benchmark results
        var aggregatedResults: [BenchmarkResult] = []

        // Group results by service and prompt
        let groupedResults = Dictionary(grouping: allSingleResults) { result in
            "\(result.serviceName)-\(result.promptId)"
        }

        for (_, results) in groupedResults {
            if let firstResult = results.first {
                // Create a basic prompt for aggregation
                let prompt = BenchmarkPrompt(
                    id: firstResult.promptId,
                    text: "Generated prompt",
                    category: .custom
                )
                let aggregated = metricsAggregator.aggregate(
                    results,
                    serviceName: firstResult.serviceName,
                    prompt: prompt
                )
                aggregatedResults.append(aggregated)
            }
        }

        let allResults = aggregatedResults + errorResults

        // Generate report
        return reportGenerator.generateReport(
            results: allResults,
            options: options
        )
    }

    public func runQuickBenchmark(
        service: LLMService,
        serviceName: String
    ) async throws -> QuickBenchmarkResult {
        logger.info("Running quick benchmark for \(serviceName)")

        let prompt = promptManager.simplePrompt
        let result = try await executor.benchmarkSingleRun(
            service: service,
            serviceName: serviceName,
            prompt: prompt,
            iteration: 0
        )

        return QuickBenchmarkResult(
            serviceName: serviceName,
            framework: service.modelInfo?.framework,
            totalTime: result.totalTime,
            timeToFirstToken: result.timeToFirstToken,
            tokensGenerated: result.tokensGenerated,
            tokensPerSecond: result.tokensPerSecond,
            generatedText: result.generatedText
        )
    }

    public func compareServices(
        _ service1: LLMService,
        service1Name: String,
        _ service2: LLMService,
        service2Name: String,
        prompt: String? = nil
    ) async throws -> ComparisonResult {
        logger.info("Comparing \(service1Name) vs \(service2Name)")

        let testPrompt = prompt ?? promptManager.reasoningPrompt.text
        let benchmarkPrompt = BenchmarkPrompt(
            id: "comparison",
            text: testPrompt,
            category: .custom,
            expectedTokens: 100
        )

        // Run benchmarks in parallel
        async let result1 = executor.benchmarkSingleRun(
            service: service1,
            serviceName: service1Name,
            prompt: benchmarkPrompt,
            iteration: 0
        )

        async let result2 = executor.benchmarkSingleRun(
            service: service2,
            serviceName: service2Name,
            prompt: benchmarkPrompt,
            iteration: 0
        )

        let (r1, r2) = try await (result1, result2)

        return comparisonEngine.compare(
            result1: r1,
            service1Name: service1Name,
            result2: r2,
            service2Name: service2Name
        )
    }

    // MARK: - Private Methods

    private func createErrorResult(
        serviceName: String,
        framework: LLMFramework?,
        error: Error
    ) -> BenchmarkResult {
        BenchmarkResult(
            serviceName: serviceName,
            framework: framework,
            promptId: "error",
            error: error.localizedDescription
        )
    }
}
