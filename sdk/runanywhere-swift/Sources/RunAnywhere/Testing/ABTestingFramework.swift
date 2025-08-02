//
//  ABTestingFramework.swift
//  RunAnywhere SDK
//
//  Compatibility wrapper for ABTestService
//

import Foundation

/// Compatibility wrapper maintaining original ABTestingFramework API
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public class ABTestingFramework {
    public static let shared = ABTestingFramework()

    // MARK: - Properties

    private let abTestService: ABTestService
    private let generationTracker: GenerationTracker
    private let metricRecorder: MetricRecorder
    private let eventLogger: EventLogger

    public var activeTests: [ABTest] {
        get async { await abTestService.activeTests }
    }

    public var completedTests: [ABTest] {
        get async { await abTestService.completedTests }
    }

    public private(set) var currentTestResults: ABTestResults?

    private var metricCallbacks: [(ABTestMetric) -> Void] = []
    private var completionCallbacks: [(ABTestResults) -> Void] = []

    // MARK: - Initialization

    private init() {
        self.abTestService = ABTestService()
        self.generationTracker = GenerationTracker(abTestService: abTestService)
        let metricsCollector = TestMetricsCollector()
        self.metricRecorder = MetricRecorder(metricsCollector: metricsCollector)
        self.eventLogger = EventLogger()

        // Set up metric recorder callback
        metricRecorder.addCallback { [weak self] metric in
            self?.metricCallbacks.forEach { $0(metric) }
        }
    }

    // MARK: - Public Methods

    public func createTest(
        name: String,
        description: String,
        variantA: TestVariant,
        variantB: TestVariant,
        configuration: ABTestConfiguration = .default
    ) -> ABTest {
        Task {
            return await abTestService.createTest(
                name: name,
                description: description,
                variantA: variantA,
                variantB: variantB,
                configuration: configuration
            )
        }
        .waitForResult() ?? ABTest(
            name: name,
            description: description,
            variantA: variantA,
            variantB: variantB,
            configuration: configuration
        )
    }

    public func startTest(_ testId: UUID) throws {
        Task {
            try await abTestService.startTest(testId)
        }.waitForResult()
    }

    public func stopTest(_ testId: UUID) -> ABTestResults? {
        Task {
            let results = await abTestService.stopTest(testId)
            currentTestResults = results
            results.map { self.notifyCompletionCallbacks($0) }
            return results
        }.waitForResult() ?? nil
    }

    public func getVariant(for testId: UUID, userId: String) -> TestVariant? {
        Task {
            await abTestService.getVariant(for: testId, userId: userId)
        }.waitForResult() ?? nil
    }

    public func recordMetric(
        testId: UUID,
        variantId: UUID,
        metric: ABTestMetric
    ) {
        Task {
            await abTestService.recordMetric(
                testId: testId,
                variantId: variantId,
                metric: metric
            )
        }
    }

    public func trackGeneration(
        testId: UUID,
        variantId: UUID,
        framework: LLMFramework,
        modelInfo: ModelInfo,
        prompt: String,
        completion: @escaping (GenerationTracking) -> Void
    ) -> GenerationTracking {
        generationTracker.trackGeneration(
            testId: testId,
            variantId: variantId,
            framework: framework,
            modelInfo: modelInfo,
            prompt: prompt,
            completion: completion
        )
    }

    public func analyzeResults(for testId: UUID) -> ABTestResults? {
        Task {
            await abTestService.analyzeResults(for: testId)
        }.waitForResult() ?? nil
    }

    public func calculateSignificance(
        variantAMetrics: [Double],
        variantBMetrics: [Double],
        confidenceLevel: Double = 0.95
    ) -> StatisticalSignificance {
        let engine = StatisticalEngine()
        return engine.calculateSignificance(
            variantAMetrics: variantAMetrics,
            variantBMetrics: variantBMetrics,
            confidenceLevel: confidenceLevel
        )
    }

    public func addMetricCallback(_ callback: @escaping (ABTestMetric) -> Void) {
        metricCallbacks.append(callback)
    }

    public func addCompletionCallback(_ callback: @escaping (ABTestResults) -> Void) {
        completionCallbacks.append(callback)
    }

    // MARK: - Private Methods

    private func notifyCompletionCallbacks(_ results: ABTestResults) {
        completionCallbacks.forEach { $0(results) }
    }
}

// MARK: - Task Extension for Synchronous Waiting

extension Task where Success == Sendable, Failure == Error {
    func waitForResult() -> Success? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Success?

        Task {
            do {
                result = try await self.value
            } catch {
                // Handle error if needed
            }
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }
}

extension Task where Success == Void, Failure == Error {
    func waitForResult() {
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                _ = try await self.value
            } catch {
                // Handle error if needed
            }
            semaphore.signal()
        }

        semaphore.wait()
    }
}
