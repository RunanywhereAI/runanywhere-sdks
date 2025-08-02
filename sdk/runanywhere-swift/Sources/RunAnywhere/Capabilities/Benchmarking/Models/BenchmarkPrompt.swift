//
//  BenchmarkPrompt.swift
//  RunAnywhere SDK
//
//  Benchmark prompt configuration
//

import Foundation

/// Benchmark prompt configuration
public struct BenchmarkPrompt {
    public let id: String
    public let text: String
    public let category: PromptCategory
    public let expectedTokens: Int

    public init(id: String, text: String, category: PromptCategory, expectedTokens: Int) {
        self.id = id
        self.text = text
        self.category = category
        self.expectedTokens = expectedTokens
    }
}

/// Prompt categories for benchmarking
public enum PromptCategory: String, CaseIterable, Codable {
    case simple
    case reasoning
    case coding
    case creative
    case analysis
    case custom
}
