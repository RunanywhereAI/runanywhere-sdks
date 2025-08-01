//
//  BenchmarkSuite.swift
//  RunAnywhere SDK
//
//  Comprehensive benchmarking infrastructure for comparing LLM frameworks
//

import Foundation
import os.log

/// Comprehensive benchmark suite for evaluating LLM framework performance
public class BenchmarkSuite {
    public static let shared = BenchmarkSuite()

    // MARK: - Properties

    /// Whether a benchmark is currently running
    public private(set) var isRunning = false

    /// Current benchmark progress (0.0 to 1.0)
    public private(set) var currentProgress: Double = 0.0

    /// Current benchmark being executed
    public private(set) var currentBenchmark: String = ""

    /// Benchmark results from the current session
    public private(set) var results: [BenchmarkResult] = []

    // MARK: - Private Properties

    private let logger = os.Logger(subsystem: "com.runanywhere.sdk", category: "Benchmark")
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.benchmark", qos: .userInitiated)
    private let performanceMonitor = RealtimePerformanceMonitor.shared

    // Default benchmark prompts
    private let defaultPrompts = [
        BenchmarkPrompt(
            id: "simple",
            text: "Hello, how are you?",
            category: .simple,
            expectedTokens: 20
        ),
        BenchmarkPrompt(
            id: "reasoning",
            text: "Explain the concept of quantum computing in simple terms.",
            category: .reasoning,
            expectedTokens: 150
        ),
        BenchmarkPrompt(
            id: "coding",
            text: "Write a Swift function to sort an array of integers using merge sort.",
            category: .coding,
            expectedTokens: 200
        ),
        BenchmarkPrompt(
            id: "creative",
            text: "Write a short story about a robot learning to paint.",
            category: .creative,
            expectedTokens: 300
        ),
        BenchmarkPrompt(
            id: "analysis",
            text: "Analyze the pros and cons of renewable energy sources.",
            category: .analysis,
            expectedTokens: 250
        )
    ]

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Run a comprehensive benchmark suite
    /// - Parameters:
    ///   - services: Dictionary of framework names to LLMService instances
    ///   - options: Benchmark configuration options
    ///   - prompts: Custom prompts to use (defaults to built-in prompts)
    /// - Returns: Comprehensive benchmark report
    public func runFullBenchmark(
        services: [String: LLMService],
        options: BenchmarkOptions = .default,
        prompts: [BenchmarkPrompt]? = nil
    ) async throws -> BenchmarkReport {
        guard !isRunning else {
            throw BenchmarkError.alreadyRunning
        }

        isRunning = true
        currentProgress = 0.0
        results.removeAll()

        defer {
            isRunning = false
            currentProgress = 1.0
        }

        let benchmarkPrompts = prompts ?? defaultPrompts
        let totalTests = services.count * benchmarkPrompts.count * options.iterations
        var completedTests = 0

        logger.info("Starting benchmark suite with \(services.count) services")

        // Start performance monitoring
        performanceMonitor.startMonitoring()
        defer { performanceMonitor.stopMonitoring() }

        for (serviceName, service) in services {
            currentBenchmark = "Testing \(serviceName)"

            do {
                // Warmup if requested
                if options.includeWarmup {
                    try await warmupService(service, name: serviceName)
                }

                // Run benchmarks for each prompt
                for prompt in benchmarkPrompts {
                    var iterationResults: [SingleRunResult] = []

                    for iteration in 0..<options.iterations {
                        let result = try await benchmarkSingleRun(
                            service: service,
                            serviceName: serviceName,
                            prompt: prompt,
                            iteration: iteration
                        )

                        iterationResults.append(result)

                        completedTests += 1
                        currentProgress = Double(completedTests) / Double(totalTests)
                    }

                    // Aggregate results for this prompt
                    let aggregated = aggregateResults(
                        iterationResults,
                        serviceName: serviceName,
                        prompt: prompt
                    )
                    results.append(aggregated)
                }

            } catch {
                logger.error("Failed to benchmark \(serviceName): \(error)")

                // Record error result
                results.append(
                    BenchmarkResult(
                        serviceName: serviceName,
                        framework: service.modelInfo?.framework,
                        promptId: benchmarkPrompts.first?.id ?? "unknown",
                        error: error.localizedDescription
                    )
                )
            }
        }

        // Generate comprehensive report
        return generateReport(options: options)
    }

    /// Run a quick benchmark for a single service
    /// - Parameters:
    ///   - service: The LLMService to benchmark
    ///   - serviceName: Name identifier for the service
    /// - Returns: Quick benchmark result
    public func runQuickBenchmark(
        service: LLMService,
        serviceName: String
    ) async throws -> QuickBenchmarkResult {
        let prompt = defaultPrompts.first { $0.category == .simple }!

        // Track performance
        if let modelInfo = service.modelInfo {
            performanceMonitor.beginGeneration(
                framework: modelInfo.framework,
                modelInfo: ModelInfo(
                    id: modelInfo.id,
                    name: modelInfo.name,
                    format: modelInfo.format,
                    estimatedMemory: modelInfo.memoryUsage
                )
            )
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        var firstTokenTime: CFAbsoluteTime?
        var tokenCount = 0
        var generatedText = ""

        // Measure generation
        try await service.streamGenerate(
            prompt: prompt.text,
            options: GenerationOptions(
                maxTokens: 50,
                temperature: 0.7
            )
        ) { token in
            if firstTokenTime == nil {
                firstTokenTime = CFAbsoluteTimeGetCurrent()
            }
            tokenCount += 1
            generatedText += token
            performanceMonitor.recordToken(token)
        }

        let endTime = CFAbsoluteTimeGetCurrent()
        let summary = performanceMonitor.endGeneration()

        return QuickBenchmarkResult(
            serviceName: serviceName,
            framework: service.modelInfo?.framework,
            totalTime: endTime - startTime,
            timeToFirstToken: firstTokenTime.map { $0 - startTime } ?? 0,
            tokensGenerated: tokenCount,
            tokensPerSecond: summary?.tokensPerSecond ?? 0,
            generatedText: generatedText
        )
    }

    /// Compare two services head-to-head
    /// - Parameters:
    ///   - service1: First service to compare
    ///   - service1Name: Name of first service
    ///   - service2: Second service to compare
    ///   - service2Name: Name of second service
    ///   - prompt: Custom prompt to use (optional)
    /// - Returns: Comparison result
    public func compareServices(
        _ service1: LLMService,
        service1Name: String,
        _ service2: LLMService,
        service2Name: String,
        prompt: String? = nil
    ) async throws -> ComparisonResult {
        let testPrompt = prompt ?? defaultPrompts.first { $0.category == .reasoning }!.text

        let benchmarkPrompt = BenchmarkPrompt(
            id: "comparison",
            text: testPrompt,
            category: .custom,
            expectedTokens: 100
        )

        // Run benchmarks in parallel
        async let result1 = benchmarkSingleRun(
            service: service1,
            serviceName: service1Name,
            prompt: benchmarkPrompt,
            iteration: 0
        )

        async let result2 = benchmarkSingleRun(
            service: service2,
            serviceName: service2Name,
            prompt: benchmarkPrompt,
            iteration: 0
        )

        let (r1, r2) = try await (result1, result2)

        return ComparisonResult(
            service1Name: service1Name,
            service2Name: service2Name,
            result1: r1,
            result2: r2,
            winner: r1.tokensPerSecond > r2.tokensPerSecond ? service1Name : service2Name
        )
    }

    /// Export benchmark results in various formats
    /// - Parameter format: Export format
    /// - Returns: Exported data
    public func exportResults(format: BenchmarkExportFormat) throws -> Data {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            return try encoder.encode(results)
        case .csv:
            return generateCSV().data(using: .utf8)!
        case .markdown:
            return generateMarkdown().data(using: .utf8)!
        }
    }

    // MARK: - Private Methods

    private func warmupService(_ service: LLMService, name: String) async throws {
        logger.debug("Warming up \(name)")

        _ = try await service.generate(
            prompt: "Hello",
            options: GenerationOptions(maxTokens: 5, temperature: 0.1)
        )
    }

    private func benchmarkSingleRun(
        service: LLMService,
        serviceName: String,
        prompt: BenchmarkPrompt,
        iteration: Int
    ) async throws -> SingleRunResult {
        let memoryBefore = getMemoryUsage()
        let startTime = CFAbsoluteTimeGetCurrent()
        var firstTokenTime: CFAbsoluteTime?
        var tokens: [String] = []

        // Track with performance monitor if possible
        if let modelInfo = service.modelInfo {
            performanceMonitor.beginGeneration(
                framework: modelInfo.framework,
                modelInfo: ModelInfo(
                    id: modelInfo.id,
                    name: modelInfo.name,
                    format: modelInfo.format,
                    estimatedMemory: modelInfo.memoryUsage
                )
            )
        }

        // Measure generation
        try await service.streamGenerate(
            prompt: prompt.text,
            options: GenerationOptions(
                maxTokens: prompt.expectedTokens,
                temperature: 0.7
            )
        ) { token in
            if firstTokenTime == nil {
                firstTokenTime = CFAbsoluteTimeGetCurrent()
            }
            tokens.append(token)
            performanceMonitor.recordToken(token)
        }

        let endTime = CFAbsoluteTimeGetCurrent()
        let memoryAfter = getMemoryUsage()
        let perfSummary = performanceMonitor.endGeneration()

        return SingleRunResult(
            serviceName: serviceName,
            framework: service.modelInfo?.framework,
            promptId: prompt.id,
            iteration: iteration,
            totalTime: endTime - startTime,
            timeToFirstToken: firstTokenTime.map { $0 - startTime } ?? 0,
            tokensGenerated: tokens.count,
            tokensPerSecond: perfSummary?.tokensPerSecond ?? Double(tokens.count) / (endTime - startTime),
            memoryUsed: memoryAfter - memoryBefore,
            generatedText: tokens.joined()
        )
    }

    private func aggregateResults(
        _ results: [SingleRunResult],
        serviceName: String,
        prompt: BenchmarkPrompt
    ) -> BenchmarkResult {
        let totalTimes = results.map { $0.totalTime }
        let ttftTimes = results.map { $0.timeToFirstToken }
        let tpsSpeeds = results.map { $0.tokensPerSecond }
        let memoryUsages = results.map { $0.memoryUsed }

        return BenchmarkResult(
            serviceName: serviceName,
            framework: results.first?.framework,
            promptId: prompt.id,
            promptCategory: prompt.category,
            avgTotalTime: average(totalTimes),
            avgTimeToFirstToken: average(ttftTimes),
            avgTokensPerSecond: average(tpsSpeeds),
            minTokensPerSecond: tpsSpeeds.min() ?? 0,
            maxTokensPerSecond: tpsSpeeds.max() ?? 0,
            stdDevTokensPerSecond: standardDeviation(tpsSpeeds),
            avgMemoryUsed: Int64(average(memoryUsages.map { Double($0) })),
            iterationCount: results.count
        )
    }

    private func generateReport(options: BenchmarkOptions) -> BenchmarkReport {
        let perfReport = performanceMonitor.generateReport()

        return BenchmarkReport(
            id: UUID(),
            timestamp: Date(),
            options: options,
            results: results,
            performanceReport: perfReport,
            summary: generateSummary()
        )
    }

    private func generateSummary() -> BenchmarkSummary {
        let groupedByService = Dictionary(grouping: results) { $0.serviceName }

        var serviceSummaries: [ServiceSummary] = []

        for (service, results) in groupedByService {
            let avgSpeed = average(results.map { $0.avgTokensPerSecond })
            let avgMemory = Int64(average(results.map { Double($0.avgMemoryUsed) }))
            let successRate = Double(results.filter { $0.error == nil }.count) / Double(results.count)

            serviceSummaries.append(
                ServiceSummary(
                    serviceName: service,
                    framework: results.first?.framework,
                    averageTokensPerSecond: avgSpeed,
                    averageMemoryUsage: avgMemory,
                    successRate: successRate,
                    testCount: results.count
                )
            )
        }

        let sorted = serviceSummaries.sorted { $0.averageTokensPerSecond > $1.averageTokensPerSecond }

        return BenchmarkSummary(
            serviceSummaries: sorted,
            fastestService: sorted.first?.serviceName,
            mostEfficientService: serviceSummaries.min { $0.averageMemoryUsage < $1.averageMemoryUsage }?.serviceName,
            overallSuccessRate: average(serviceSummaries.map { $0.successRate })
        )
    }

    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        let avg = average(values)
        let squaredDiffs = values.map { pow($0 - avg, 2) }
        return sqrt(average(squaredDiffs))
    }

    private func generateCSV() -> String {
        var csv = "Service,Framework,Prompt,Category,Avg Time,Avg TTFT,Avg TPS,Min TPS,Max TPS,StdDev TPS,Avg Memory\n"

        for result in results {
            csv += "\(result.serviceName),"
            csv += "\(result.framework?.rawValue ?? "unknown"),"
            csv += "\(result.promptId),"
            csv += "\(result.promptCategory.rawValue),"
            csv += "\(result.avgTotalTime),"
            csv += "\(result.avgTimeToFirstToken),"
            csv += "\(result.avgTokensPerSecond),"
            csv += "\(result.minTokensPerSecond),"
            csv += "\(result.maxTokensPerSecond),"
            csv += "\(result.stdDevTokensPerSecond),"
            csv += "\(result.avgMemoryUsed)\n"
        }

        return csv
    }

    private func generateMarkdown() -> String {
        var markdown = "# Benchmark Results\n\n"
        markdown += "Date: \(Date().formatted())\n\n"

        if let summary = generateSummary() as BenchmarkSummary? {
            markdown += "## Summary\n\n"
            if let fastest = summary.fastestService {
                markdown += "- **Fastest Service**: \(fastest)\n"
            }
            if let efficient = summary.mostEfficientService {
                markdown += "- **Most Memory Efficient**: \(efficient)\n"
            }
            markdown += "- **Overall Success Rate**: \(String(format: "%.1f", summary.overallSuccessRate * 100))%\n"
        }

        markdown += "\n## Detailed Results\n\n"
        markdown += "| Service | Framework | Prompt | Avg TPS | Avg TTFT | Avg Memory |\n"
        markdown += "|---------|-----------|--------|---------|----------|------------|\n"

        for result in results {
            markdown += "| \(result.serviceName) "
            markdown += "| \(result.framework?.rawValue ?? "N/A") "
            markdown += "| \(result.promptId) "
            markdown += "| \(String(format: "%.1f", result.avgTokensPerSecond)) "
            markdown += "| \(String(format: "%.2f", result.avgTimeToFirstToken))s "
            markdown += "| \(ByteCountFormatter.string(fromByteCount: result.avgMemoryUsed, countStyle: .memory)) |\n"
        }

        return markdown
    }
}

// MARK: - Supporting Types

/// Benchmark prompt configuration
public struct BenchmarkPrompt {
    public let id: String
    public let text: String
    public let category: PromptCategory
    public let expectedTokens: Int

    public init(id: String, text: String, category: PromptCategory, expectedTokens: Int) {
        self.id = id
        self.text = text
        self.category = category
        self.expectedTokens = expectedTokens
    }
}

/// Prompt categories for benchmarking
public enum PromptCategory: String, CaseIterable {
    case simple
    case reasoning
    case coding
    case creative
    case analysis
    case custom
}

/// Benchmark configuration options
public struct BenchmarkOptions {
    public let iterations: Int
    public let includeWarmup: Bool
    public let measureMemory: Bool
    public let measurePerformance: Bool

    public init(
        iterations: Int = 3,
        includeWarmup: Bool = true,
        measureMemory: Bool = true,
        measurePerformance: Bool = true
    ) {
        self.iterations = iterations
        self.includeWarmup = includeWarmup
        self.measureMemory = measureMemory
        self.measurePerformance = measurePerformance
    }

    public static let `default` = BenchmarkOptions()
}

/// Result from a single benchmark run
public struct SingleRunResult {
    public let serviceName: String
    public let framework: LLMFramework?
    public let promptId: String
    public let iteration: Int
    public let totalTime: TimeInterval
    public let timeToFirstToken: TimeInterval
    public let tokensGenerated: Int
    public let tokensPerSecond: Double
    public let memoryUsed: Int64
    public let generatedText: String
}

/// Aggregated benchmark result
public struct BenchmarkResult: Codable {
    public let serviceName: String
    public let framework: LLMFramework?
    public let promptId: String
    public let promptCategory: PromptCategory
    public let avgTotalTime: TimeInterval
    public let avgTimeToFirstToken: TimeInterval
    public let avgTokensPerSecond: Double
    public let minTokensPerSecond: Double
    public let maxTokensPerSecond: Double
    public let stdDevTokensPerSecond: Double
    public let avgMemoryUsed: Int64
    public let iterationCount: Int
    public let error: String?

    public init(
        serviceName: String,
        framework: LLMFramework? = nil,
        promptId: String,
        promptCategory: PromptCategory = .custom,
        avgTotalTime: TimeInterval = 0,
        avgTimeToFirstToken: TimeInterval = 0,
        avgTokensPerSecond: Double = 0,
        minTokensPerSecond: Double = 0,
        maxTokensPerSecond: Double = 0,
        stdDevTokensPerSecond: Double = 0,
        avgMemoryUsed: Int64 = 0,
        iterationCount: Int = 0,
        error: String? = nil
    ) {
        self.serviceName = serviceName
        self.framework = framework
        self.promptId = promptId
        self.promptCategory = promptCategory
        self.avgTotalTime = avgTotalTime
        self.avgTimeToFirstToken = avgTimeToFirstToken
        self.avgTokensPerSecond = avgTokensPerSecond
        self.minTokensPerSecond = minTokensPerSecond
        self.maxTokensPerSecond = maxTokensPerSecond
        self.stdDevTokensPerSecond = stdDevTokensPerSecond
        self.avgMemoryUsed = avgMemoryUsed
        self.iterationCount = iterationCount
        self.error = error
    }
}

/// Quick benchmark result
public struct QuickBenchmarkResult {
    public let serviceName: String
    public let framework: LLMFramework?
    public let totalTime: TimeInterval
    public let timeToFirstToken: TimeInterval
    public let tokensGenerated: Int
    public let tokensPerSecond: Double
    public let generatedText: String
}

/// Service comparison result
public struct ComparisonResult {
    public let service1Name: String
    public let service2Name: String
    public let result1: SingleRunResult
    public let result2: SingleRunResult
    public let winner: String
}

/// Service performance summary
public struct ServiceSummary {
    public let serviceName: String
    public let framework: LLMFramework?
    public let averageTokensPerSecond: Double
    public let averageMemoryUsage: Int64
    public let successRate: Double
    public let testCount: Int
}

/// Overall benchmark summary
public struct BenchmarkSummary {
    public let serviceSummaries: [ServiceSummary]
    public let fastestService: String?
    public let mostEfficientService: String?
    public let overallSuccessRate: Double
}

/// Complete benchmark report
public struct BenchmarkReport: Codable {
    public let id: UUID
    public let timestamp: Date
    public let options: BenchmarkOptions
    public let results: [BenchmarkResult]
    public let performanceReport: PerformanceReport
    public let summary: BenchmarkSummary
}

/// Export format options
public enum BenchmarkExportFormat {
    case json
    case csv
    case markdown
}

/// Benchmark errors
public enum BenchmarkError: LocalizedError {
    case alreadyRunning
    case noServicesProvided
    case serviceInitializationFailed
    case invalidConfiguration

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "A benchmark is already running"
        case .noServicesProvided:
            return "No services provided for benchmarking"
        case .serviceInitializationFailed:
            return "Failed to initialize service for benchmarking"
        case .invalidConfiguration:
            return "Invalid benchmark configuration"
        }
    }
}
