//
//  ABTestingFramework.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/27/25.
//

import Foundation
import Combine
import os.log

/// A/B testing framework for comparing LLM frameworks
class ABTestingFramework: ObservableObject {
    static let shared = ABTestingFramework()
    
    // MARK: - Published Properties
    @Published var activeTests: [ABTest] = []
    @Published var completedTests: [ABTest] = []
    @Published var currentTestResults: ABTestResults?
    
    // MARK: - Private Properties
    private let logger = os.Logger(subsystem: "com.runanywhere.ai", category: "ABTesting")
    private let queue = DispatchQueue(label: "com.runanywhere.abtesting", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()
    private let persistenceManager = ABTestPersistenceManager()
    
    // MARK: - Initialization
    init() {
        loadSavedTests()
    }
    
    // MARK: - Public Methods
    
    /// Create a new A/B test
    func createTest(
        name: String,
        description: String,
        variantA: TestVariant,
        variantB: TestVariant,
        config: ABTestConfiguration = .default
    ) -> ABTest {
        
        let test = ABTest(
            id: UUID(),
            name: name,
            description: description,
            variantA: variantA,
            variantB: variantB,
            configuration: config,
            status: .created,
            createdAt: Date()
        )
        
        activeTests.append(test)
        logger.info("Created A/B test: \(name)")
        
        return test
    }
    
    /// Start an A/B test
    func startTest(_ testId: UUID) async throws {
        guard let index = activeTests.firstIndex(where: { $0.id == testId }) else {
            throw ABTestError.testNotFound
        }
        
        var test = activeTests[index]
        test.status = .running
        test.startedAt = Date()
        activeTests[index] = test
        
        logger.info("Started A/B test: \(test.name)")
        
        // Begin collecting data
        Task {
            await collectTestData(for: test)
        }
    }
    
    /// Stop an A/B test
    func stopTest(_ testId: UUID) {
        guard let index = activeTests.firstIndex(where: { $0.id == testId }) else { return }
        
        var test = activeTests[index]
        test.status = .completed
        test.completedAt = Date()
        
        // Move to completed
        activeTests.remove(at: index)
        completedTests.append(test)
        
        // Generate results
        if let results = generateResults(for: test) {
            currentTestResults = results
        }
        
        logger.info("Stopped A/B test: \(test.name)")
        saveTests()
    }
    
    /// Get participant variant
    func getVariant(for testId: UUID, userId: String) -> TestVariant? {
        guard let test = activeTests.first(where: { $0.id == testId }),
              test.status == .running else {
            return nil
        }
        
        // Deterministic assignment based on user ID
        let hash = userId.hashValue
        let assignment = abs(hash) % 100
        
        return assignment < test.configuration.trafficSplit ? test.variantA : test.variantB
    }
    
    /// Record metric for a test
    func recordMetric(
        testId: UUID,
        variant: TestVariant,
        metric: ABTestMetric
    ) {
        guard let index = activeTests.firstIndex(where: { $0.id == testId }) else { return }
        
        var test = activeTests[index]
        
        switch variant.id {
        case test.variantA.id:
            test.variantAMetrics.append(metric)
        case test.variantB.id:
            test.variantBMetrics.append(metric)
        default:
            logger.warning("Unknown variant ID: \(variant.id)")
        }
        
        activeTests[index] = test
        
        // Check if test should auto-complete
        if shouldAutoComplete(test) {
            stopTest(testId)
        }
    }
    
    /// Analyze test results
    func analyzeResults(for testId: UUID) -> ABTestResults? {
        let test = completedTests.first(where: { $0.id == testId }) ??
                   activeTests.first(where: { $0.id == testId })
        
        guard let test = test else { return nil }
        
        return generateResults(for: test)
    }
    
    /// Get confidence interval
    func getConfidenceInterval(
        for metrics: [ABTestMetric],
        confidence: Double = 0.95
    ) -> ConfidenceInterval {
        
        let values = metrics.compactMap { metric -> Double? in
            switch metric.type {
            case .tokensPerSecond(let value):
                return value
            case .timeToFirstToken(let value):
                return value
            case .memoryUsage(let value):
                return Double(value)
            case .userSatisfaction(let value):
                return Double(value)
            case .errorRate(let value):
                return value
            }
        }
        
        guard !values.isEmpty else {
            return ConfidenceInterval(lower: 0, upper: 0, mean: 0, confidence: confidence)
        }
        
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count - 1)
        let standardError = sqrt(variance / Double(values.count))
        
        // Z-score for confidence level
        let zScore = confidence == 0.95 ? 1.96 : 2.58
        let margin = zScore * standardError
        
        return ConfidenceInterval(
            lower: mean - margin,
            upper: mean + margin,
            mean: mean,
            confidence: confidence
        )
    }
    
    /// Run automated A/B test
    func runAutomatedTest(
        frameworks: [LLMFramework],
        testPrompts: [String],
        duration: TimeInterval
    ) async throws -> AutomatedTestResults {
        
        guard frameworks.count >= 2 else {
            throw ABTestError.insufficientVariants
        }
        
        let variantA = TestVariant(
            id: UUID(),
            name: frameworks[0].displayName,
            framework: frameworks[0],
            configuration: [:] // Default config
        )
        
        let variantB = TestVariant(
            id: UUID(),
            name: frameworks[1].displayName,
            framework: frameworks[1],
            configuration: [:]
        )
        
        let config = ABTestConfiguration(
            minSampleSize: testPrompts.count,
            maxDuration: duration,
            trafficSplit: 50,
            metricsToTrack: [.tokensPerSecond, .timeToFirstToken, .memoryUsage]
        )
        
        let test = createTest(
            name: "Automated Framework Comparison",
            description: "Comparing \(variantA.name) vs \(variantB.name)",
            variantA: variantA,
            variantB: variantB,
            config: config
        )
        
        try await startTest(test.id)
        
        // Run test prompts
        for (index, prompt) in testPrompts.enumerated() {
            let variant = index % 2 == 0 ? variantA : variantB
            
            do {
                let metrics = try await runTestIteration(
                    variant: variant,
                    prompt: prompt
                )
                
                recordMetric(testId: test.id, variant: variant, metric: metrics)
            } catch {
                logger.error("Test iteration failed: \(error)")
            }
        }
        
        // Wait for completion or timeout
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        
        stopTest(test.id)
        
        guard let results = currentTestResults else {
            throw ABTestError.noResults
        }
        
        return AutomatedTestResults(
            test: test,
            results: results,
            completedPrompts: testPrompts.count
        )
    }
    
    // MARK: - Private Methods
    
    private func collectTestData(for test: ABTest) async {
        logger.debug("Starting data collection for test: \(test.name)")
        
        // Monitor for test duration
        let endTime = Date().addingTimeInterval(test.configuration.maxDuration)
        
        while test.status == .running && Date() < endTime {
            // Check sample size
            let totalSamples = test.variantAMetrics.count + test.variantBMetrics.count
            if totalSamples >= test.configuration.minSampleSize * 2 {
                logger.info("Test reached minimum sample size")
                break
            }
            
            // Wait before next check
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
        
        // Auto-complete if still running
        if let index = activeTests.firstIndex(where: { $0.id == test.id }) {
            stopTest(test.id)
        }
    }
    
    private func runTestIteration(
        variant: TestVariant,
        prompt: String
    ) async throws -> ABTestMetric {
        
        // Initialize framework
        let service = try await initializeFramework(variant.framework)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let startMemory = getMemoryUsage()
        var firstTokenTime: CFAbsoluteTime?
        var tokenCount = 0
        
        // Run generation
        try await service.streamGenerate(
            prompt: prompt,
            options: GenerationOptions(maxTokens: 100, temperature: 0.7, topP: 0.95, topK: 40, repetitionPenalty: 1.1, stopSequences: []),
            onToken: { _ in
                if firstTokenTime == nil {
                    firstTokenTime = CFAbsoluteTimeGetCurrent()
                }
                tokenCount += 1
            }
        )
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let endMemory = getMemoryUsage()
        
        // Calculate metrics
        let totalTime = endTime - startTime
        let timeToFirstToken = firstTokenTime.map { $0 - startTime } ?? 0
        let tokensPerSecond = Double(tokenCount) / totalTime
        let memoryUsed = endMemory - startMemory
        
        // Return primary metric based on configuration
        if variant.configuration["primaryMetric"] == "speed" {
            return ABTestMetric(id: UUID(), timestamp: Date(), type: .tokensPerSecond(tokensPerSecond))
        } else if variant.configuration["primaryMetric"] == "latency" {
            return ABTestMetric(id: UUID(), timestamp: Date(), type: .timeToFirstToken(timeToFirstToken))
        } else {
            return ABTestMetric(id: UUID(), timestamp: Date(), type: .memoryUsage(memoryUsed))
        }
    }
    
    private func initializeFramework(_ framework: LLMFramework) async throws -> LLMService {
        let unifiedService = await UnifiedLLMService.shared
        await unifiedService.selectService(named: framework.displayName)
        
        guard let service = await unifiedService.currentService else {
            throw ABTestError.frameworkInitializationFailed
        }
        
        return service
    }
    
    private func generateResults(for test: ABTest) -> ABTestResults? {
        let variantAStats = calculateStatistics(for: test.variantAMetrics)
        let variantBStats = calculateStatistics(for: test.variantBMetrics)
        
        guard let statsA = variantAStats, let statsB = variantBStats else {
            return nil
        }
        
        // Calculate statistical significance
        let significance = calculateStatisticalSignificance(
            groupA: test.variantAMetrics,
            groupB: test.variantBMetrics
        )
        
        // Determine winner
        let winner: TestVariant?
        if significance.pValue < 0.05 {
            winner = statsA.mean > statsB.mean ? test.variantA : test.variantB
        } else {
            winner = nil // No significant difference
        }
        
        return ABTestResults(
            testId: test.id,
            testName: test.name,
            variantAStats: statsA,
            variantBStats: statsB,
            statisticalSignificance: significance,
            winner: winner,
            confidence: significance.pValue < 0.05 ? 0.95 : 0.0,
            sampleSizeA: test.variantAMetrics.count,
            sampleSizeB: test.variantBMetrics.count
        )
    }
    
    private func calculateStatistics(for metrics: [ABTestMetric]) -> VariantStatistics? {
        guard !metrics.isEmpty else { return nil }
        
        let values = metrics.compactMap { metric -> Double? in
            switch metric.type {
            case .tokensPerSecond(let value):
                return value
            case .timeToFirstToken(let value):
                return value
            case .memoryUsage(let value):
                return Double(value)
            case .userSatisfaction(let value):
                return Double(value)
            case .errorRate(let value):
                return value
            }
        }
        
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count - 1)
        let stdDev = sqrt(variance)
        
        return VariantStatistics(
            mean: mean,
            median: calculateMedian(values),
            standardDeviation: stdDev,
            min: values.min() ?? 0,
            max: values.max() ?? 0,
            percentile95: calculatePercentile(values, percentile: 0.95)
        )
    }
    
    private func calculateMedian(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let count = sorted.count
        
        if count % 2 == 0 {
            return (sorted[count/2 - 1] + sorted[count/2]) / 2
        } else {
            return sorted[count/2]
        }
    }
    
    private func calculatePercentile(_ values: [Double], percentile: Double) -> Double {
        let sorted = values.sorted()
        let index = Int(Double(sorted.count - 1) * percentile)
        return sorted[index]
    }
    
    private func calculateStatisticalSignificance(
        groupA: [ABTestMetric],
        groupB: [ABTestMetric]
    ) -> StatisticalSignificance {
        
        // Simplified t-test implementation
        let valuesA = extractValues(from: groupA)
        let valuesB = extractValues(from: groupB)
        
        guard valuesA.count > 1 && valuesB.count > 1 else {
            return StatisticalSignificance(pValue: 1.0, tStatistic: 0, degreesOfFreedom: 0)
        }
        
        let meanA = valuesA.reduce(0, +) / Double(valuesA.count)
        let meanB = valuesB.reduce(0, +) / Double(valuesB.count)
        
        let varA = valuesA.map { pow($0 - meanA, 2) }.reduce(0, +) / Double(valuesA.count - 1)
        let varB = valuesB.map { pow($0 - meanB, 2) }.reduce(0, +) / Double(valuesB.count - 1)
        
        let pooledStdError = sqrt((varA / Double(valuesA.count)) + (varB / Double(valuesB.count)))
        let tStatistic = (meanA - meanB) / pooledStdError
        let degreesOfFreedom = valuesA.count + valuesB.count - 2
        
        // Simplified p-value calculation
        let pValue = 2 * (1 - normalCDF(abs(tStatistic)))
        
        return StatisticalSignificance(
            pValue: pValue,
            tStatistic: tStatistic,
            degreesOfFreedom: degreesOfFreedom
        )
    }
    
    private func extractValues(from metrics: [ABTestMetric]) -> [Double] {
        return metrics.compactMap { metric in
            switch metric.type {
            case .tokensPerSecond(let value):
                return value
            case .timeToFirstToken(let value):
                return value
            case .memoryUsage(let value):
                return Double(value)
            case .userSatisfaction(let value):
                return Double(value)
            case .errorRate(let value):
                return value
            }
        }
    }
    
    private func normalCDF(_ x: Double) -> Double {
        // Simplified normal CDF approximation
        return 0.5 * (1 + erf(x / sqrt(2)))
    }
    
    private func shouldAutoComplete(_ test: ABTest) -> Bool {
        let totalSamples = test.variantAMetrics.count + test.variantBMetrics.count
        return totalSamples >= test.configuration.minSampleSize * 2
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
    
    private func loadSavedTests() {
        activeTests = persistenceManager.loadActiveTests()
        completedTests = persistenceManager.loadCompletedTests()
    }
    
    private func saveTests() {
        persistenceManager.save(activeTests: activeTests, completedTests: completedTests)
    }
}

// MARK: - Supporting Types

struct ABTest: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let variantA: TestVariant
    let variantB: TestVariant
    let configuration: ABTestConfiguration
    var status: TestStatus
    let createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var variantAMetrics: [ABTestMetric] = []
    var variantBMetrics: [ABTestMetric] = []
}

struct TestVariant: Identifiable, Codable {
    let id: UUID
    let name: String
    let framework: LLMFramework
    let configuration: [String: String]
}

struct ABTestConfiguration: Codable {
    let minSampleSize: Int
    let maxDuration: TimeInterval
    let trafficSplit: Int // Percentage for variant A (0-100)
    let metricsToTrack: [MetricType]
    
    static let `default` = ABTestConfiguration(
        minSampleSize: 100,
        maxDuration: 3600, // 1 hour
        trafficSplit: 50,
        metricsToTrack: [.tokensPerSecond, .timeToFirstToken]
    )
}

enum TestStatus: String, Codable {
    case created
    case running
    case completed
    case cancelled
}

enum MetricType: String, Codable {
    case tokensPerSecond
    case timeToFirstToken
    case memoryUsage
    case userSatisfaction
    case errorRate
}

struct ABTestMetric: Codable {
    let id: UUID
    let timestamp: Date
    let type: MetricValue
    
    enum MetricValue: Codable {
        case tokensPerSecond(Double)
        case timeToFirstToken(TimeInterval)
        case memoryUsage(Int64)
        case userSatisfaction(Int) // 1-5 scale
        case errorRate(Double)
    }
}

struct ABTestResults {
    let testId: UUID
    let testName: String
    let variantAStats: VariantStatistics
    let variantBStats: VariantStatistics
    let statisticalSignificance: StatisticalSignificance
    let winner: TestVariant?
    let confidence: Double
    let sampleSizeA: Int
    let sampleSizeB: Int
}

struct VariantStatistics {
    let mean: Double
    let median: Double
    let standardDeviation: Double
    let min: Double
    let max: Double
    let percentile95: Double
}

struct StatisticalSignificance {
    let pValue: Double
    let tStatistic: Double
    let degreesOfFreedom: Int
}

struct ConfidenceInterval {
    let lower: Double
    let upper: Double
    let mean: Double
    let confidence: Double
}

struct AutomatedTestResults {
    let test: ABTest
    let results: ABTestResults
    let completedPrompts: Int
}

enum ABTestError: LocalizedError {
    case testNotFound
    case insufficientVariants
    case frameworkInitializationFailed
    case noResults
    
    var errorDescription: String? {
        switch self {
        case .testNotFound:
            return "Test not found"
        case .insufficientVariants:
            return "Need at least 2 variants for A/B testing"
        case .frameworkInitializationFailed:
            return "Failed to initialize framework"
        case .noResults:
            return "No results available"
        }
    }
}

// MARK: - Persistence Manager

class ABTestPersistenceManager {
    private let documentsDirectory = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
    ).first!
    
    func save(activeTests: [ABTest], completedTests: [ABTest]) {
        // Save to UserDefaults or file system
    }
    
    func loadActiveTests() -> [ABTest] {
        return []
    }
    
    func loadCompletedTests() -> [ABTest] {
        return []
    }
}