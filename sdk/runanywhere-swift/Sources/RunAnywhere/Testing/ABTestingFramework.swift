//
//  ABTestingFramework.swift
//  RunAnywhere SDK
//
//  A/B testing infrastructure for comparing model performance
//

import Foundation

/// A/B testing framework for comparing LLM models and configurations
public class ABTestingFramework {
    public static let shared = ABTestingFramework()

    // MARK: - Properties

    /// Active A/B tests
    public private(set) var activeTests: [ABTest] = []

    /// Completed A/B tests
    public private(set) var completedTests: [ABTest] = []

    /// Current test results
    public private(set) var currentTestResults: ABTestResults?

    // MARK: - Private Properties

    private let logger = SDKLogger(category: "ABTesting")
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.abtesting", qos: .userInitiated)
    private let performanceMonitor = RealtimePerformanceMonitor.shared

    // Test data storage
    private var testMetrics: [UUID: TestMetrics] = [:]

    // Callbacks
    private var metricCallbacks: [(ABTestMetric) -> Void] = []
    private var completionCallbacks: [(ABTestResults) -> Void] = []

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Create a new A/B test
    public func createTest(
        name: String,
        description: String,
        variantA: TestVariant,
        variantB: TestVariant,
        configuration: ABTestConfiguration = .default
    ) -> ABTest {
        let test = ABTest(
            id: UUID(),
            name: name,
            description: description,
            variantA: variantA,
            variantB: variantB,
            configuration: configuration,
            status: .created,
            createdAt: Date()
        )

        queue.sync {
            activeTests.append(test)
            testMetrics[test.id] = TestMetrics()
        }

        if #available(iOS 14.0, *) {
            logger.info("Created A/B test: \(name)")
        }

        return test
    }

    /// Start an A/B test
    public func startTest(_ testId: UUID) throws {
        try queue.sync {
            guard let index = activeTests.firstIndex(where: { $0.id == testId }) else {
                throw ABTestError.testNotFound
            }

            activeTests[index].status = .running
            activeTests[index].startedAt = Date()
        }

        if #available(iOS 14.0, *) {
            logger.info("Started A/B test with ID: \(testId)")
        }
    }

    /// Stop an A/B test and generate results
    public func stopTest(_ testId: UUID) -> ABTestResults? {
        var test: ABTest?
        var results: ABTestResults?

        queue.sync {
            guard let index = activeTests.firstIndex(where: { $0.id == testId }) else { return }

            test = activeTests[index]
            activeTests[index].status = .completed
            activeTests[index].completedAt = Date()

            // Move to completed
            completedTests.append(activeTests[index])
            activeTests.remove(at: index)

            // Generate results
            if let test = test,
               let metrics = testMetrics[testId] {
                results = generateResults(for: test, metrics: metrics)
                currentTestResults = results
            }
        }

        if let test = test {
            if #available(iOS 14.0, *) {
                logger.info("Stopped A/B test: \(test.name)")
            }
        }

        // Notify callbacks
        if let results = results {
            for callback in completionCallbacks {
                callback(results)
            }
        }

        return results
    }

    /// Get variant assignment for a user
    public func getVariant(for testId: UUID, userId: String) -> TestVariant? {
        queue.sync {
            guard let test = activeTests.first(where: { $0.id == testId }),
                  test.status == .running else {
                return nil
            }

            // Deterministic assignment based on user ID hash
            let hash = userId.hash
            let assignment = abs(hash) % 100

            return assignment < test.configuration.trafficSplit ? test.variantA : test.variantB
        }
    }

    /// Record a metric for a test variant
    public func recordMetric(
        testId: UUID,
        variantId: UUID,
        metric: ABTestMetric
    ) {
        queue.sync {
            guard activeTests.contains(where: { $0.id == testId && $0.status == .running }) else { return }

            if testMetrics[testId] == nil {
                testMetrics[testId] = TestMetrics()
            }

            if testMetrics[testId]!.variantMetrics[variantId] == nil {
                testMetrics[testId]!.variantMetrics[variantId] = []
            }

            testMetrics[testId]!.variantMetrics[variantId]!.append(metric)
            testMetrics[testId]!.totalSamples += 1

            // Check if test should auto-complete
            if let test = activeTests.first(where: { $0.id == testId }),
               shouldAutoComplete(test: test, metrics: testMetrics[testId]!) {
                _ = stopTest(testId)
            }
        }

        // Notify callbacks
        for callback in metricCallbacks {
            callback(metric)
        }
    }

    /// Track generation performance for A/B testing
    public func trackGeneration(
        testId: UUID,
        variantId: UUID,
        framework: LLMFramework,
        modelInfo: ModelInfo,
        prompt: String,
        completion: @escaping (GenerationTracking) -> Void
    ) -> GenerationTracking {
        // Start performance monitoring
        performanceMonitor.beginGeneration(framework: framework, modelInfo: modelInfo)

        let tracking = GenerationTracking(
            testId: testId,
            variantId: variantId,
            startTime: Date()
        )

        // Set up completion handler
        tracking.completionHandler = { [weak self] tracking in
            guard let self = self else { return }

            // End performance monitoring
            if let summary = self.performanceMonitor.endGeneration() {
                // Record metrics
                self.recordMetric(
                    testId: testId,
                    variantId: variantId,
                    metric: .tokensPerSecond(summary.tokensPerSecond)
                )

                self.recordMetric(
                    testId: testId,
                    variantId: variantId,
                    metric: .timeToFirstToken(summary.timeToFirstToken)
                )

                self.recordMetric(
                    testId: testId,
                    variantId: variantId,
                    metric: .memoryUsage(summary.memoryUsed)
                )
            }

            completion(tracking)
        }

        return tracking
    }

    /// Analyze results for a test
    public func analyzeResults(for testId: UUID) -> ABTestResults? {
        queue.sync {
            if let test = completedTests.first(where: { $0.id == testId }),
               let metrics = testMetrics[testId] {
                return generateResults(for: test, metrics: metrics)
            }

            if let test = activeTests.first(where: { $0.id == testId }),
               let metrics = testMetrics[testId] {
                return generateResults(for: test, metrics: metrics)
            }

            return nil
        }
    }

    /// Calculate statistical significance
    public func calculateSignificance(
        variantAMetrics: [Double],
        variantBMetrics: [Double],
        confidenceLevel: Double = 0.95
    ) -> StatisticalSignificance {
        guard !variantAMetrics.isEmpty && !variantBMetrics.isEmpty else {
            return StatisticalSignificance(
                pValue: 1.0,
                isSignificant: false,
                confidenceLevel: confidenceLevel,
                effect: 0
            )
        }

        // Calculate means
        let meanA = variantAMetrics.reduce(0, +) / Double(variantAMetrics.count)
        let meanB = variantBMetrics.reduce(0, +) / Double(variantBMetrics.count)

        // Calculate variances
        let varianceA = variantAMetrics.map { pow($0 - meanA, 2) }.reduce(0, +) / Double(variantAMetrics.count - 1)
        let varianceB = variantBMetrics.map { pow($0 - meanB, 2) }.reduce(0, +) / Double(variantBMetrics.count - 1)

        // Calculate t-statistic
        let standardError = sqrt(varianceA / Double(variantAMetrics.count) + varianceB / Double(variantBMetrics.count))
        let tStatistic = abs(meanA - meanB) / standardError

        // Simplified p-value calculation (would use proper distribution in production)
        let pValue = 2 * (1 - min(0.99, 0.5 + 0.5 * erf(tStatistic / sqrt(2))))

        // Calculate effect size (Cohen's d)
        let pooledStdDev = sqrt((varianceA + varianceB) / 2)
        let effectSize = abs(meanA - meanB) / pooledStdDev

        return StatisticalSignificance(
            pValue: pValue,
            isSignificant: pValue < (1 - confidenceLevel),
            confidenceLevel: confidenceLevel,
            effect: effectSize
        )
    }

    /// Add metric callback
    public func addMetricCallback(_ callback: @escaping (ABTestMetric) -> Void) {
        queue.async { [weak self] in
            self?.metricCallbacks.append(callback)
        }
    }

    /// Add completion callback
    public func addCompletionCallback(_ callback: @escaping (ABTestResults) -> Void) {
        queue.async { [weak self] in
            self?.completionCallbacks.append(callback)
        }
    }

    // MARK: - Private Methods

    private func generateResults(for test: ABTest, metrics: TestMetrics) -> ABTestResults {
        let variantAMetrics = metrics.variantMetrics[test.variantA.id] ?? []
        let variantBMetrics = metrics.variantMetrics[test.variantB.id] ?? []

        // Calculate statistics for each metric type
        let performanceComparison = comparePerformance(
            variantA: variantAMetrics,
            variantB: variantBMetrics
        )

        // Determine winner
        let winner = determineWinner(
            comparison: performanceComparison,
            configuration: test.configuration
        )

        return ABTestResults(
            test: test,
            variantAMetrics: variantAMetrics,
            variantBMetrics: variantBMetrics,
            performanceComparison: performanceComparison,
            winner: winner,
            completedAt: test.completedAt ?? Date(),
            totalSamples: metrics.totalSamples
        )
    }

    private func comparePerformance(
        variantA: [ABTestMetric],
        variantB: [ABTestMetric]
    ) -> PerformanceComparison {
        // Extract metrics by type
        let tpsA = variantA.compactMap { metric in
            if case .tokensPerSecond(let value) = metric { return value }
            return nil
        }
        let tpsB = variantB.compactMap { metric in
            if case .tokensPerSecond(let value) = metric { return value }
            return nil
        }

        let ttftA = variantA.compactMap { metric in
            if case .timeToFirstToken(let value) = metric { return value }
            return nil
        }
        let ttftB = variantB.compactMap { metric in
            if case .timeToFirstToken(let value) = metric { return value }
            return nil
        }

        // Calculate statistics
        let tpsSignificance = calculateSignificance(variantAMetrics: tpsA, variantBMetrics: tpsB)
        let ttftSignificance = calculateSignificance(variantAMetrics: ttftA, variantBMetrics: ttftB)

        return PerformanceComparison(
            tokensPerSecond: MetricComparison(
                variantAMean: average(tpsA),
                variantBMean: average(tpsB),
                improvement: calculateImprovement(baseline: average(tpsA), variant: average(tpsB)),
                significance: tpsSignificance
            ),
            timeToFirstToken: MetricComparison(
                variantAMean: average(ttftA),
                variantBMean: average(ttftB),
                improvement: calculateImprovement(baseline: average(ttftA), variant: average(ttftB), lowerIsBetter: true),
                significance: ttftSignificance
            )
        )
    }

    private func determineWinner(
        comparison: PerformanceComparison,
        configuration: ABTestConfiguration
    ) -> TestVariant? {
        var scoreA = 0.0
        var scoreB = 0.0

        // Score based on tokens per second (higher is better)
        if comparison.tokensPerSecond.variantAMean > comparison.tokensPerSecond.variantBMean {
            scoreA += comparison.tokensPerSecond.significance.isSignificant ? 2 : 1
        } else {
            scoreB += comparison.tokensPerSecond.significance.isSignificant ? 2 : 1
        }

        // Score based on time to first token (lower is better)
        if comparison.timeToFirstToken.variantAMean < comparison.timeToFirstToken.variantBMean {
            scoreA += comparison.timeToFirstToken.significance.isSignificant ? 2 : 1
        } else {
            scoreB += comparison.timeToFirstToken.significance.isSignificant ? 2 : 1
        }

        // Require minimum improvement threshold
        let improvement = abs(comparison.tokensPerSecond.improvement)
        if improvement < configuration.minimumDetectableEffect {
            return nil // No clear winner
        }

        return scoreA > scoreB ? nil : nil // Return actual variant in implementation
    }

    private func shouldAutoComplete(test: ABTest, metrics: TestMetrics) -> Bool {
        // Check sample size
        if metrics.totalSamples >= test.configuration.sampleSize {
            return true
        }

        // Check duration
        if let startedAt = test.startedAt,
           Date().timeIntervalSince(startedAt) >= test.configuration.maxDuration {
            return true
        }

        return false
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func calculateImprovement(baseline: Double, variant: Double, lowerIsBetter: Bool = false) -> Double {
        guard baseline != 0 else { return 0 }
        let improvement = ((variant - baseline) / baseline) * 100
        return lowerIsBetter ? -improvement : improvement
    }
}

// MARK: - Supporting Types

/// A/B test definition
public struct ABTest {
    public let id: UUID
    public let name: String
    public let description: String
    public let variantA: TestVariant
    public let variantB: TestVariant
    public let configuration: ABTestConfiguration
    public var status: ABTestStatus
    public let createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
}

/// Test variant
public struct TestVariant {
    public let id: UUID
    public let name: String
    public let configuration: [String: Any] // Framework-specific config

    public init(id: UUID = UUID(), name: String, configuration: [String: Any] = [:]) {
        self.id = id
        self.name = name
        self.configuration = configuration
    }
}

/// Test configuration
public struct ABTestConfiguration {
    public let trafficSplit: Int // Percentage for variant A (0-100)
    public let sampleSize: Int
    public let maxDuration: TimeInterval
    public let minimumDetectableEffect: Double // Minimum % improvement
    public let confidenceLevel: Double

    public init(
        trafficSplit: Int = 50,
        sampleSize: Int = 1000,
        maxDuration: TimeInterval = 7 * 24 * 60 * 60, // 7 days
        minimumDetectableEffect: Double = 5.0,
        confidenceLevel: Double = 0.95
    ) {
        self.trafficSplit = trafficSplit
        self.sampleSize = sampleSize
        self.maxDuration = maxDuration
        self.minimumDetectableEffect = minimumDetectableEffect
        self.confidenceLevel = confidenceLevel
    }

    public static let `default` = ABTestConfiguration()
}

/// Test status
public enum ABTestStatus {
    case created
    case running
    case completed
    case cancelled
}

/// Test metric types
public enum ABTestMetric {
    case tokensPerSecond(Double)
    case timeToFirstToken(TimeInterval)
    case memoryUsage(Int64)
    case userSatisfaction(Int) // 1-5 rating
    case errorRate(Double) // 0-1

    public var value: Double {
        switch self {
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

/// Test metrics storage
private struct TestMetrics {
    var variantMetrics: [UUID: [ABTestMetric]] = [:]
    var totalSamples: Int = 0
}

/// Test results
public struct ABTestResults {
    public let test: ABTest
    public let variantAMetrics: [ABTestMetric]
    public let variantBMetrics: [ABTestMetric]
    public let performanceComparison: PerformanceComparison
    public let winner: TestVariant?
    public let completedAt: Date
    public let totalSamples: Int
}

/// Performance comparison
public struct PerformanceComparison {
    public let tokensPerSecond: MetricComparison
    public let timeToFirstToken: MetricComparison
}

/// Metric comparison
public struct MetricComparison {
    public let variantAMean: Double
    public let variantBMean: Double
    public let improvement: Double // Percentage
    public let significance: StatisticalSignificance
}

/// Statistical significance
public struct StatisticalSignificance {
    public let pValue: Double
    public let isSignificant: Bool
    public let confidenceLevel: Double
    public let effect: Double // Effect size (Cohen's d)
}

/// Generation tracking for A/B tests
public class GenerationTracking {
    public let testId: UUID
    public let variantId: UUID
    public let startTime: Date
    public var endTime: Date?
    public var tokensGenerated: Int = 0
    public var completionHandler: ((GenerationTracking) -> Void)?

    init(testId: UUID, variantId: UUID, startTime: Date) {
        self.testId = testId
        self.variantId = variantId
        self.startTime = startTime
    }

    public func complete() {
        endTime = Date()
        completionHandler?(self)
    }
}

/// A/B test errors
public enum ABTestError: LocalizedError {
    case testNotFound
    case testNotRunning
    case insufficientData
    case invalidConfiguration

    public var errorDescription: String? {
        switch self {
        case .testNotFound:
            return "A/B test not found"
        case .testNotRunning:
            return "A/B test is not running"
        case .insufficientData:
            return "Insufficient data for analysis"
        case .invalidConfiguration:
            return "Invalid test configuration"
        }
    }
}
