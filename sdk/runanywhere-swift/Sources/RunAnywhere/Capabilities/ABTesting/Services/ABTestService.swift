//
//  ABTestService.swift
//  RunAnywhere SDK
//
//  Main A/B test orchestration service
//

import Foundation

/// Main A/B test service implementation
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public actor ABTestService: @preconcurrency ABTestRunner {
    // MARK: - Properties

    public private(set) var activeTests: [ABTest] = []
    public private(set) var completedTests: [ABTest] = []

    private let variantManager: VariantManager
    private let metricsCollector: TestMetricsCollector
    private let resultAnalyzer: ResultAnalyzer
    private let lifecycleManager: TestLifecycleManager
    private let logger = SDKLogger(category: "ABTestService")

    // MARK: - Initialization

    public init(
        variantManager: VariantManager? = nil,
        metricsCollector: TestMetricsCollector? = nil,
        resultAnalyzer: ResultAnalyzer? = nil,
        lifecycleManager: TestLifecycleManager? = nil
    ) {
        self.variantManager = variantManager ?? VariantManager()
        self.metricsCollector = metricsCollector ?? TestMetricsCollector()
        self.resultAnalyzer = resultAnalyzer ?? ResultAnalyzer()
        self.lifecycleManager = lifecycleManager ?? TestLifecycleManager()
    }

    // MARK: - ABTestRunner Implementation

    public func createTest(
        name: String,
        description: String,
        variantA: TestVariant,
        variantB: TestVariant,
        configuration: ABTestConfiguration = .default
    ) -> ABTest {
        let test = ABTest(
            name: name,
            description: description,
            variantA: variantA,
            variantB: variantB,
            configuration: configuration
        )

        activeTests.append(test)
        logger.info("Created A/B test: \(name)")

        return test
    }

    public func startTest(_ testId: UUID) throws {
        guard let index = activeTests.firstIndex(where: { $0.id == testId }) else {
            throw ABTestError.testNotFound
        }

        activeTests[index].status = .running
        activeTests[index].startedAt = Date()

        lifecycleManager.startTracking(test: activeTests[index])
        logger.info("Started A/B test with ID: \(testId)")
    }

    public func stopTest(_ testId: UUID) -> ABTestResults? {
        guard let index = activeTests.firstIndex(where: { $0.id == testId }) else {
            return nil
        }

        var test = activeTests[index]
        test.status = .completed
        test.completedAt = Date()

        // Move to completed
        completedTests.append(test)
        activeTests.remove(at: index)

        // Generate results
        let metrics = metricsCollector.getMetrics(for: testId)
        let results = resultAnalyzer.generateResults(
            test: test,
            metrics: metrics
        )

        lifecycleManager.stopTracking(testId: testId)
        logger.info("Stopped A/B test: \(test.name)")

        return results
    }

    public func getVariant(for testId: UUID, userId: String) -> TestVariant? {
        guard let test = activeTests.first(where: { $0.id == testId && $0.status == .running }) else {
            return nil
        }

        return variantManager.assignVariant(for: test, userId: userId)
    }

    public func recordMetric(testId: UUID, variantId: UUID, metric: ABTestMetric) {
        guard activeTests.contains(where: { $0.id == testId && $0.status == .running }) else {
            return
        }

        metricsCollector.record(
            testId: testId,
            variantId: variantId,
            metric: metric
        )

        // Check if test should auto-complete
        if let test = activeTests.first(where: { $0.id == testId }),
           lifecycleManager.shouldAutoComplete(test: test, totalSamples: metricsCollector.getTotalSamples(for: testId)) {
            _ = stopTest(testId)
        }
    }

    public func analyzeResults(for testId: UUID) -> ABTestResults? {
        if let test = completedTests.first(where: { $0.id == testId }) {
            let metrics = metricsCollector.getMetrics(for: testId)
            return resultAnalyzer.generateResults(test: test, metrics: metrics)
        }

        if let test = activeTests.first(where: { $0.id == testId }) {
            let metrics = metricsCollector.getMetrics(for: testId)
            return resultAnalyzer.generateResults(test: test, metrics: metrics)
        }

        return nil
    }
}
