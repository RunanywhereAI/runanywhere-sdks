//
//  TestVariant.swift
//  RunAnywhere SDK
//
//  Test variant model
//

import Foundation

/// Test variant
public struct TestVariant {
    public let id: UUID
    public let name: String
    public let configuration: [String: Any] // Framework-specific config

    public init(
        id: UUID = UUID(),
        name: String,
        configuration: [String: Any] = [:]
    ) {
        self.id = id
        self.name = name
        self.configuration = configuration
    }
}
