//
//  EventLogger.swift
//  RunAnywhere SDK
//
//  Logs A/B test events
//

import Foundation

/// Logs events for A/B tests
public class EventLogger {
    // MARK: - Properties

    private let logger = SDKLogger(category: "ABTestEvents")
    private var eventHandlers: [(ABTestEvent) -> Void] = []
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.event-logger")

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Log test created event
    public func logTestCreated(_ test: ABTest) {
        let event = ABTestEvent.testCreated(test: test)
        logger.info("A/B test created: \(test.name)")
        notifyHandlers(event)
    }

    /// Log test started event
    public func logTestStarted(_ test: ABTest) {
        let event = ABTestEvent.testStarted(test: test)
        logger.info("A/B test started: \(test.name)")
        notifyHandlers(event)
    }

    /// Log test completed event
    public func logTestCompleted(_ test: ABTest, results: ABTestResults) {
        let event = ABTestEvent.testCompleted(test: test, results: results)
        logger.info("A/B test completed: \(test.name)")
        notifyHandlers(event)
    }

    /// Log variant assignment
    public func logVariantAssignment(testId: UUID, userId: String, variant: TestVariant) {
        let event = ABTestEvent.variantAssigned(
            testId: testId,
            userId: userId,
            variant: variant
        )
        logger.debug("Variant \(variant.name) assigned to user \(userId)")
        notifyHandlers(event)
    }

    /// Add event handler
    public func addEventHandler(_ handler: @escaping (ABTestEvent) -> Void) {
        queue.async {
            self.eventHandlers.append(handler)
        }
    }

    // MARK: - Private Methods

    private func notifyHandlers(_ event: ABTestEvent) {
        queue.async {
            for handler in self.eventHandlers {
                handler(event)
            }
        }
    }
}

/// A/B test events
public enum ABTestEvent {
    case testCreated(test: ABTest)
    case testStarted(test: ABTest)
    case testCompleted(test: ABTest, results: ABTestResults)
    case variantAssigned(testId: UUID, userId: String, variant: TestVariant)
    case metricRecorded(testId: UUID, variantId: UUID, metric: ABTestMetric)
}
