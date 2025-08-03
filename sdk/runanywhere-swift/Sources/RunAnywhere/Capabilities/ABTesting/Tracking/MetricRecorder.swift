//
//  MetricRecorder.swift
//  RunAnywhere SDK
//
//  Records metrics for A/B tests
//

import Foundation

/// Records and manages A/B test metrics
public class MetricRecorder {
    // MARK: - Properties

    private let metricsCollector: TestMetricsCollector
    private var callbacks: [(ABTestMetric) -> Void] = []
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.metric-recorder")

    // MARK: - Initialization

    public init(metricsCollector: TestMetricsCollector) {
        self.metricsCollector = metricsCollector
    }

    // MARK: - Public Methods

    /// Record a metric
    public func record(
        testId: UUID,
        variantId: UUID,
        metric: ABTestMetric
    ) {
        metricsCollector.record(
            testId: testId,
            variantId: variantId,
            metric: metric
        )

        // Notify callbacks
        notifyCallbacks(metric)
    }

    /// Record multiple metrics
    public func recordBatch(
        testId: UUID,
        variantId: UUID,
        metrics: [ABTestMetric]
    ) {
        for metric in metrics {
            record(testId: testId, variantId: variantId, metric: metric)
        }
    }

    /// Add callback for metric recording
    public func addCallback(_ callback: @escaping (ABTestMetric) -> Void) {
        queue.async {
            self.callbacks.append(callback)
        }
    }

    /// Remove all callbacks
    public func clearCallbacks() {
        queue.async {
            self.callbacks.removeAll()
        }
    }

    // MARK: - Private Methods

    private func notifyCallbacks(_ metric: ABTestMetric) {
        queue.async {
            for callback in self.callbacks {
                callback(metric)
            }
        }
    }
}
