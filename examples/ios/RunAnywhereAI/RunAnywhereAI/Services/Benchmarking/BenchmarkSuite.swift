//
//  BenchmarkSuite.swift
//  RunAnywhereAI
//
//  Created by Assistant on 7/27/25.
//

import Foundation
import Combine
import os.log

/// Comprehensive benchmark suite for LLM frameworks
class BenchmarkSuite: ObservableObject {
    static let shared = BenchmarkSuite()
    
    // MARK: - Published Properties
    @Published var isRunning = false
    @Published var currentProgress: Double = 0.0
    @Published var currentBenchmark: String = ""
    @Published var results: [BenchmarkResult] = []
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.runanywhere.ai", category: "Benchmark")
    private let queue = DispatchQueue(label: "com.runanywhere.benchmark", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()
    
    // Benchmark configurations
    private let benchmarkPrompts = [
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
    
    // MARK: - Public Methods
    
    /// Run full benchmark suite
    func runFullBenchmark(
        frameworks: [LLMFramework] = LLMFramework.allCases,
        options: BenchmarkOptions = .default
    ) async throws {
        
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
        
        let totalTests = frameworks.count * benchmarkPrompts.count * options.iterations
        var completedTests = 0
        
        logger.info("Starting benchmark suite with \(frameworks.count) frameworks")
        
        for framework in frameworks {
            currentBenchmark = "Testing \(framework.displayName)"
            
            do {
                // Initialize framework
                let service = try await initializeFramework(framework)
                
                // Warmup
                if options.includeWarmup {
                    _ = try await warmupFramework(service: service)
                }
                
                // Run benchmarks
                for prompt in benchmarkPrompts {
                    var promptResults: [SingleBenchmarkResult] = []
                    
                    for iteration in 0..<options.iterations {
                        let result = try await benchmarkSingle(
                            service: service,
                            prompt: prompt,
                            framework: framework
                        )
                        
                        promptResults.append(result)
                        
                        completedTests += 1
                        currentProgress = Double(completedTests) / Double(totalTests)
                    }
                    
                    // Aggregate results
                    let aggregated = aggregateResults(promptResults, prompt: prompt, framework: framework)
                    results.append(aggregated)
                }
                
                // Cleanup
                await cleanupFramework(service)
                
            } catch {
                logger.error("Failed to benchmark \(framework.displayName): \(error)")
                // Record error result
                results.append(
                    BenchmarkResult(
                        framework: framework,
                        prompt: benchmarkPrompts.first!,
                        error: error.localizedDescription
                    )
                )
            }
        }
        
        // Generate report
        generateReport()
    }
    
    /// Run quick benchmark for specific framework
    func runQuickBenchmark(framework: LLMFramework) async throws -> QuickBenchmarkResult {
        let service = try await initializeFramework(framework)
        
        defer {
            Task {
                await cleanupFramework(service)
            }
        }
        
        // Use simple prompt for quick test
        let prompt = benchmarkPrompts.first { $0.category == .simple }!
        
        let startTime = CFAbsoluteTimeGetCurrent()
        var firstTokenTime: CFAbsoluteTime?
        var tokenCount = 0
        
        // Measure generation
        try await service.streamGenerate(
            prompt: prompt.text,
            options: GenerationOptions(maxTokens: 50, temperature: 0.7),
            onToken: { _ in
                if firstTokenTime == nil {
                    firstTokenTime = CFAbsoluteTimeGetCurrent()
                }
                tokenCount += 1
            }
        )
        
        let endTime = CFAbsoluteTimeGetCurrent()
        
        return QuickBenchmarkResult(
            framework: framework,
            totalTime: endTime - startTime,
            timeToFirstToken: firstTokenTime.map { $0 - startTime } ?? 0,
            tokensGenerated: tokenCount,
            tokensPerSecond: Double(tokenCount) / (endTime - startTime)
        )
    }
    
    /// Compare two frameworks head-to-head
    func compareFrameworks(
        _ framework1: LLMFramework,
        _ framework2: LLMFramework,
        prompt: String? = nil
    ) async throws -> ComparisonResult {
        
        let testPrompt = prompt ?? benchmarkPrompts.first { $0.category == .reasoning }!.text
        
        // Initialize both frameworks
        let service1 = try await initializeFramework(framework1)
        let service2 = try await initializeFramework(framework2)
        
        defer {
            Task {
                await cleanupFramework(service1)
                await cleanupFramework(service2)
            }
        }
        
        // Run benchmarks in parallel
        async let result1 = benchmarkSingle(
            service: service1,
            prompt: BenchmarkPrompt(id: "custom", text: testPrompt, category: .custom, expectedTokens: 100),
            framework: framework1
        )
        
        async let result2 = benchmarkSingle(
            service: service2,
            prompt: BenchmarkPrompt(id: "custom", text: testPrompt, category: .custom, expectedTokens: 100),
            framework: framework2
        )
        
        let (r1, r2) = try await (result1, result2)
        
        return ComparisonResult(
            framework1: framework1,
            framework2: framework2,
            result1: r1,
            result2: r2,
            winner: determineWinner(r1, r2)
        )
    }
    
    /// Get benchmark history
    func getBenchmarkHistory() -> [BenchmarkSession] {
        // Load from persistent storage
        return loadBenchmarkHistory()
    }
    
    /// Export benchmark results
    func exportResults(format: ExportFormat) throws -> Data {
        switch format {
        case .json:
            return try JSONEncoder().encode(results)
        case .csv:
            return generateCSV()
        case .markdown:
            return generateMarkdown().data(using: .utf8)!
        }
    }
    
    // MARK: - Private Methods
    
    private func initializeFramework(_ framework: LLMFramework) async throws -> LLMProtocol {
        let unifiedService = UnifiedLLMService.shared
        try await unifiedService.selectFramework(framework)
        
        guard let service = unifiedService.currentService else {
            throw BenchmarkError.frameworkInitializationFailed
        }
        
        return service
    }
    
    private func warmupFramework(service: LLMProtocol) async throws {
        logger.debug("Warming up \(service.name)")
        
        _ = try await service.generate(
            prompt: "Hello",
            options: GenerationOptions(maxTokens: 5, temperature: 0.1)
        )
    }
    
    private func benchmarkSingle(
        service: LLMProtocol,
        prompt: BenchmarkPrompt,
        framework: LLMFramework
    ) async throws -> SingleBenchmarkResult {
        
        let memoryBefore = getMemoryUsage()
        let startTime = CFAbsoluteTimeGetCurrent()
        var firstTokenTime: CFAbsoluteTime?
        var tokens: [String] = []
        
        // Measure generation
        try await service.streamGenerate(
            prompt: prompt.text,
            options: GenerationOptions(
                maxTokens: prompt.expectedTokens,
                temperature: 0.7
            ),
            onToken: { token in
                if firstTokenTime == nil {
                    firstTokenTime = CFAbsoluteTimeGetCurrent()
                }
                tokens.append(token)
            }
        )
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let memoryAfter = getMemoryUsage()
        
        return SingleBenchmarkResult(
            framework: framework,
            promptId: prompt.id,
            totalTime: endTime - startTime,
            timeToFirstToken: firstTokenTime.map { $0 - startTime } ?? 0,
            tokensGenerated: tokens.count,
            tokensPerSecond: Double(tokens.count) / (endTime - startTime),
            memoryUsed: memoryAfter - memoryBefore,
            cpuUsage: getCPUUsage(),
            generatedText: tokens.joined()
        )
    }
    
    private func aggregateResults(
        _ results: [SingleBenchmarkResult],
        prompt: BenchmarkPrompt,
        framework: LLMFramework
    ) -> BenchmarkResult {
        
        let totalTimes = results.map { $0.totalTime }
        let ttftTimes = results.map { $0.timeToFirstToken }
        let tpsSpeeds = results.map { $0.tokensPerSecond }
        let memoryUsages = results.map { $0.memoryUsed }
        
        return BenchmarkResult(
            framework: framework,
            prompt: prompt,
            avgTotalTime: totalTimes.reduce(0, +) / Double(totalTimes.count),
            avgTimeToFirstToken: ttftTimes.reduce(0, +) / Double(ttftTimes.count),
            avgTokensPerSecond: tpsSpeeds.reduce(0, +) / Double(tpsSpeeds.count),
            minTokensPerSecond: tpsSpeeds.min() ?? 0,
            maxTokensPerSecond: tpsSpeeds.max() ?? 0,
            avgMemoryUsed: memoryUsages.reduce(0, +) / Double(memoryUsages.count),
            sampleCount: results.count
        )
    }
    
    private func cleanupFramework(_ service: LLMProtocol) async {
        // Framework cleanup if needed
        logger.debug("Cleaning up \(service.name)")
    }
    
    private func determineWinner(_ r1: SingleBenchmarkResult, _ r2: SingleBenchmarkResult) -> LLMFramework {
        // Simple scoring: higher tokens/second wins
        return r1.tokensPerSecond > r2.tokensPerSecond ? r1.framework : r2.framework
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
    
    private func getCPUUsage() -> Double {
        var cpuInfo: processor_info_array_t!
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0
        
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCpus,
            &cpuInfo,
            &numCpuInfo
        )
        
        guard result == KERN_SUCCESS else { return 0 }
        
        return 0 // Simplified for demo
    }
    
    private func generateReport() {
        let report = BenchmarkReport(
            date: Date(),
            results: results,
            summary: generateSummary()
        )
        
        // Save report
        saveBenchmarkReport(report)
    }
    
    private func generateSummary() -> BenchmarkSummary {
        let groupedByFramework = Dictionary(grouping: results) { $0.framework }
        
        var frameworkSummaries: [FrameworkSummary] = []
        
        for (framework, results) in groupedByFramework {
            let avgSpeed = results.map { $0.avgTokensPerSecond }.reduce(0, +) / Double(results.count)
            let avgMemory = results.map { $0.avgMemoryUsed }.reduce(0, +) / Double(results.count)
            
            frameworkSummaries.append(
                FrameworkSummary(
                    framework: framework,
                    averageSpeed: avgSpeed,
                    averageMemory: avgMemory,
                    successRate: Double(results.filter { $0.error == nil }.count) / Double(results.count)
                )
            )
        }
        
        return BenchmarkSummary(
            frameworkSummaries: frameworkSummaries.sorted { $0.averageSpeed > $1.averageSpeed },
            fastestFramework: frameworkSummaries.max { $0.averageSpeed < $1.averageSpeed }?.framework,
            mostEfficientFramework: frameworkSummaries.min { $0.averageMemory < $1.averageMemory }?.framework
        )
    }
    
    private func generateCSV() -> Data {
        var csv = "Framework,Prompt,Avg Time,Avg TTFT,Avg TPS,Min TPS,Max TPS,Avg Memory\n"
        
        for result in results {
            csv += "\(result.framework.rawValue),"
            csv += "\(result.prompt.id),"
            csv += "\(result.avgTotalTime),"
            csv += "\(result.avgTimeToFirstToken),"
            csv += "\(result.avgTokensPerSecond),"
            csv += "\(result.minTokensPerSecond),"
            csv += "\(result.maxTokensPerSecond),"
            csv += "\(result.avgMemoryUsed)\n"
        }
        
        return csv.data(using: .utf8)!
    }
    
    private func generateMarkdown() -> String {
        var markdown = "# Benchmark Results\n\n"
        markdown += "Date: \(Date().formatted())\n\n"
        
        markdown += "## Summary\n\n"
        
        let summary = generateSummary()
        if let fastest = summary.fastestFramework {
            markdown += "- **Fastest Framework**: \(fastest.displayName)\n"
        }
        if let efficient = summary.mostEfficientFramework {
            markdown += "- **Most Memory Efficient**: \(efficient.displayName)\n"
        }
        
        markdown += "\n## Detailed Results\n\n"
        markdown += "| Framework | Prompt | Avg TPS | Avg TTFT | Avg Memory |\n"
        markdown += "|-----------|--------|---------|----------|------------|\n"
        
        for result in results {
            markdown += "| \(result.framework.displayName) "
            markdown += "| \(result.prompt.id) "
            markdown += "| \(String(format: "%.1f", result.avgTokensPerSecond)) "
            markdown += "| \(String(format: "%.2f", result.avgTimeToFirstToken))s "
            markdown += "| \(ByteCountFormatter.string(fromByteCount: result.avgMemoryUsed, countStyle: .memory)) |\n"
        }
        
        return markdown
    }
    
    private func loadBenchmarkHistory() -> [BenchmarkSession] {
        // Load from UserDefaults or file system
        return []
    }
    
    private func saveBenchmarkReport(_ report: BenchmarkReport) {
        // Save to persistent storage
    }
}

// MARK: - Supporting Types

struct BenchmarkPrompt {
    let id: String
    let text: String
    let category: PromptCategory
    let expectedTokens: Int
}

enum PromptCategory {
    case simple
    case reasoning
    case coding
    case creative
    case analysis
    case custom
}

struct BenchmarkOptions {
    let iterations: Int
    let includeWarmup: Bool
    let measureMemory: Bool
    let measureCPU: Bool
    
    static let `default` = BenchmarkOptions(
        iterations: 3,
        includeWarmup: true,
        measureMemory: true,
        measureCPU: true
    )
}

struct SingleBenchmarkResult {
    let framework: LLMFramework
    let promptId: String
    let totalTime: TimeInterval
    let timeToFirstToken: TimeInterval
    let tokensGenerated: Int
    let tokensPerSecond: Double
    let memoryUsed: Int64
    let cpuUsage: Double
    let generatedText: String
}

struct BenchmarkResult: Codable {
    let framework: LLMFramework
    let prompt: BenchmarkPrompt
    let avgTotalTime: TimeInterval
    let avgTimeToFirstToken: TimeInterval
    let avgTokensPerSecond: Double
    let minTokensPerSecond: Double
    let maxTokensPerSecond: Double
    let avgMemoryUsed: Int64
    let sampleCount: Int
    let error: String?
    
    init(framework: LLMFramework, prompt: BenchmarkPrompt, error: String) {
        self.framework = framework
        self.prompt = prompt
        self.avgTotalTime = 0
        self.avgTimeToFirstToken = 0
        self.avgTokensPerSecond = 0
        self.minTokensPerSecond = 0
        self.maxTokensPerSecond = 0
        self.avgMemoryUsed = 0
        self.sampleCount = 0
        self.error = error
    }
    
    init(framework: LLMFramework, prompt: BenchmarkPrompt, avgTotalTime: TimeInterval, avgTimeToFirstToken: TimeInterval, avgTokensPerSecond: Double, minTokensPerSecond: Double, maxTokensPerSecond: Double, avgMemoryUsed: Int64, sampleCount: Int) {
        self.framework = framework
        self.prompt = prompt
        self.avgTotalTime = avgTotalTime
        self.avgTimeToFirstToken = avgTimeToFirstToken
        self.avgTokensPerSecond = avgTokensPerSecond
        self.minTokensPerSecond = minTokensPerSecond
        self.maxTokensPerSecond = maxTokensPerSecond
        self.avgMemoryUsed = avgMemoryUsed
        self.sampleCount = sampleCount
        self.error = nil
    }
}

struct QuickBenchmarkResult {
    let framework: LLMFramework
    let totalTime: TimeInterval
    let timeToFirstToken: TimeInterval
    let tokensGenerated: Int
    let tokensPerSecond: Double
}

struct ComparisonResult {
    let framework1: LLMFramework
    let framework2: LLMFramework
    let result1: SingleBenchmarkResult
    let result2: SingleBenchmarkResult
    let winner: LLMFramework
}

struct BenchmarkReport {
    let date: Date
    let results: [BenchmarkResult]
    let summary: BenchmarkSummary
}

struct BenchmarkSummary {
    let frameworkSummaries: [FrameworkSummary]
    let fastestFramework: LLMFramework?
    let mostEfficientFramework: LLMFramework?
}

struct FrameworkSummary {
    let framework: LLMFramework
    let averageSpeed: Double
    let averageMemory: Int64
    let successRate: Double
}

struct BenchmarkSession: Codable {
    let id: UUID
    let date: Date
    let results: [BenchmarkResult]
}

enum ExportFormat {
    case json
    case csv
    case markdown
}

enum BenchmarkError: LocalizedError {
    case alreadyRunning
    case frameworkInitializationFailed
    case benchmarkFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Benchmark is already running"
        case .frameworkInitializationFailed:
            return "Failed to initialize framework"
        case .benchmarkFailed(let reason):
            return "Benchmark failed: \(reason)"
        }
    }
}

// Make BenchmarkPrompt Codable
extension BenchmarkPrompt: Codable {
    enum CodingKeys: String, CodingKey {
        case id, text, category, expectedTokens
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        let categoryString = try container.decode(String.self, forKey: .category)
        category = PromptCategory(rawValue: categoryString) ?? .custom
        expectedTokens = try container.decode(Int.self, forKey: .expectedTokens)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(category.rawValue, forKey: .category)
        try container.encode(expectedTokens, forKey: .expectedTokens)
    }
}

extension PromptCategory: RawRepresentable {
    typealias RawValue = String
    
    init?(rawValue: String) {
        switch rawValue {
        case "simple": self = .simple
        case "reasoning": self = .reasoning
        case "coding": self = .coding
        case "creative": self = .creative
        case "analysis": self = .analysis
        case "custom": self = .custom
        default: return nil
        }
    }
    
    var rawValue: String {
        switch self {
        case .simple: return "simple"
        case .reasoning: return "reasoning"
        case .coding: return "coding"
        case .creative: return "creative"
        case .analysis: return "analysis"
        case .custom: return "custom"
        }
    }
}