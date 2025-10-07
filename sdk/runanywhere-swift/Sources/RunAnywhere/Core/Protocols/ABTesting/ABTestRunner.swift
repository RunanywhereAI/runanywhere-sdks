//
//  ABTestRunner.swift
//  RunAnywhere SDK
//
//  Protocol for A/B test execution
//

import Foundation

/// Protocol for running A/B tests
public protocol ABTestRunner {
    /// Active A/B tests
    var activeTests: [ABTest] { get }

    /// Completed A/B tests
    var completedTests: [ABTest] { get }

    /// Create a new A/B test
    func createTest(
        name: String,
        description: String,
        variantA: TestVariant,
        variantB: TestVariant,
        configuration: ABTestConfiguration
    ) -> ABTest

    /// Start an A/B test
    func startTest(_ testId: UUID) throws

    /// Stop an A/B test and generate results
    func stopTest(_ testId: UUID) -> ABTestResults?

    /// Get variant assignment for a user
    func getVariant(for testId: UUID, userId: String) -> TestVariant?

    /// Record a metric for a test variant
    func recordMetric(testId: UUID, variantId: UUID, metric: ABTestMetric)

    /// Analyze results for a test
    func analyzeResults(for testId: UUID) -> ABTestResults?
}
