//
//  VariantManager.swift
//  RunAnywhere SDK
//
//  Manages variant assignment for A/B tests
//

import Foundation

/// Manages variant assignment and traffic splitting
public class VariantManager {
    // MARK: - Properties

    private var userAssignments: [UUID: [String: UUID]] = [:] // testId -> userId -> variantId
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.variant-manager")

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Assign a variant to a user
    public func assignVariant(for test: ABTest, userId: String) -> TestVariant? {
        queue.sync {
            // Check if user already has assignment
            if let existingVariantId = userAssignments[test.id]?[userId] {
                if existingVariantId == test.variantA.id {
                    return test.variantA
                } else if existingVariantId == test.variantB.id {
                    return test.variantB
                }
            }

            // Deterministic assignment based on user ID hash
            let variant = determineVariant(for: test, userId: userId)

            // Store assignment
            if userAssignments[test.id] == nil {
                userAssignments[test.id] = [:]
            }
            userAssignments[test.id]?[userId] = variant.id

            return variant
        }
    }

    /// Clear assignments for a test
    public func clearAssignments(for testId: UUID) {
        queue.async {
            self.userAssignments.removeValue(forKey: testId)
        }
    }

    /// Get all users assigned to a variant
    public func getUsersForVariant(testId: UUID, variantId: UUID) -> [String] {
        queue.sync {
            guard let assignments = userAssignments[testId] else { return [] }

            return assignments.compactMap { userId, assignedVariantId in
                assignedVariantId == variantId ? userId : nil
            }
        }
    }

    // MARK: - Private Methods

    private func determineVariant(for test: ABTest, userId: String) -> TestVariant {
        // Use hash for deterministic assignment
        let hash = abs(userId.hash)
        let assignment = hash % 100

        // Assign based on traffic split
        return assignment < test.configuration.trafficSplit ? test.variantA : test.variantB
    }
}
