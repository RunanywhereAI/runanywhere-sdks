//
//  TestLifecycleManager.swift
//  RunAnywhere SDK
//
//  Manages A/B test lifecycle
//

import Foundation

/// Manages test lifecycle and auto-completion
public class TestLifecycleManager {
    // MARK: - Properties

    private var testStartTimes: [UUID: Date] = [:]
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.lifecycle-manager")

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Start tracking a test
    public func startTracking(test: ABTest) {
        queue.async {
            self.testStartTimes[test.id] = test.startedAt ?? Date()
        }
    }

    /// Stop tracking a test
    public func stopTracking(testId: UUID) {
        queue.async {
            self.testStartTimes.removeValue(forKey: testId)
        }
    }

    /// Check if test should auto-complete
    public func shouldAutoComplete(test: ABTest, totalSamples: Int) -> Bool {
        queue.sync {
            // Check sample size
            if totalSamples >= test.configuration.sampleSize {
                return true
            }

            // Check duration
            if let startTime = testStartTimes[test.id] {
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed >= test.configuration.maxDuration {
                    return true
                }
            }

            return false
        }
    }

    /// Get test duration
    public func getDuration(for testId: UUID) -> TimeInterval? {
        queue.sync {
            guard let startTime = testStartTimes[testId] else { return nil }
            return Date().timeIntervalSince(startTime)
        }
    }
}
