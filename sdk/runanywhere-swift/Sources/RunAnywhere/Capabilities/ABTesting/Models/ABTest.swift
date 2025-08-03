//
//  ABTest.swift
//  RunAnywhere SDK
//
//  A/B test definition
//

import Foundation

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

    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        variantA: TestVariant,
        variantB: TestVariant,
        configuration: ABTestConfiguration = .default,
        status: ABTestStatus = .created,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.variantA = variantA
        self.variantB = variantB
        self.configuration = configuration
        self.status = status
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}
