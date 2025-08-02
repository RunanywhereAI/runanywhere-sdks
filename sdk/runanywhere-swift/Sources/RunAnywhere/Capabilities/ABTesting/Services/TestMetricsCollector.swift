//
//  TestMetricsCollector.swift
//  RunAnywhere SDK
//
//  Collects and manages A/B test metrics
//

import Foundation

/// Metrics storage structure
public struct TestMetrics {
    public var variantMetrics: [UUID: [ABTestMetric]] = [:]
    public var totalSamples: Int = 0

    public init() {}
}

/// Collects metrics for A/B tests
public class TestMetricsCollector {
    // MARK: - Properties

    private var testMetrics: [UUID: TestMetrics] = [:]
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.metrics-collector")
    private let logger = SDKLogger(category: "MetricsCollector")

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Record a metric
    public func record(testId: UUID, variantId: UUID, metric: ABTestMetric) {
        queue.async {
            if self.testMetrics[testId] == nil {
                self.testMetrics[testId] = TestMetrics()
            }

            if self.testMetrics[testId]!.variantMetrics[variantId] == nil {
                self.testMetrics[testId]!.variantMetrics[variantId] = []
            }

            self.testMetrics[testId]!.variantMetrics[variantId]!.append(metric)
            self.testMetrics[testId]!.totalSamples += 1

            self.logger.debug("Recorded metric for test \(testId), variant \(variantId)")
        }
    }

    /// Get all metrics for a test
    public func getMetrics(for testId: UUID) -> TestMetrics {
        queue.sync {
            testMetrics[testId] ?? TestMetrics()
        }
    }

    /// Get metrics for a specific variant
    public func getVariantMetrics(testId: UUID, variantId: UUID) -> [ABTestMetric] {
        queue.sync {
            testMetrics[testId]?.variantMetrics[variantId] ?? []
        }
    }

    /// Get total samples for a test
    public func getTotalSamples(for testId: UUID) -> Int {
        queue.sync {
            testMetrics[testId]?.totalSamples ?? 0
        }
    }

    /// Clear metrics for a test
    public func clearMetrics(for testId: UUID) {
        queue.async {
            self.testMetrics.removeValue(forKey: testId)
        }
    }

    /// Extract metrics by type
    public func extractMetricsByType(_ metrics: [ABTestMetric], type: MetricType) -> [Double] {
        metrics.compactMap { metric in
            guard metric.metricType == type else { return nil }
            return metric.value
        }
    }
}
