//
//  PromptManager.swift
//  RunAnywhere SDK
//
//  Manages benchmark prompts
//

import Foundation

/// Manages benchmark prompts
public class PromptManager {
    // MARK: - Properties

    /// Default benchmark prompts
    public let defaultPrompts: [BenchmarkPrompt] = [
        BenchmarkPrompt(
            id: "simple",
            text: "Hello, how are you?",
            category: .simple,
            expectedTokens: 20
        ),
        BenchmarkPrompt(
            id: "reasoning",
            text: "Explain the concept of quantum computing in simple terms.",
            category: .reasoning,
            expectedTokens: 150
        ),
        BenchmarkPrompt(
            id: "coding",
            text: "Write a Swift function to sort an array of integers using merge sort.",
            category: .coding,
            expectedTokens: 200
        ),
        BenchmarkPrompt(
            id: "creative",
            text: "Write a short story about a robot learning to paint.",
            category: .creative,
            expectedTokens: 300
        ),
        BenchmarkPrompt(
            id: "analysis",
            text: "Analyze the pros and cons of renewable energy sources.",
            category: .analysis,
            expectedTokens: 250
        )
    ]

    /// Simple prompt for quick benchmarks
    public var simplePrompt: BenchmarkPrompt {
        defaultPrompts.first { $0.category == .simple }!
    }

    /// Reasoning prompt for comparisons
    public var reasoningPrompt: BenchmarkPrompt {
        defaultPrompts.first { $0.category == .reasoning }!
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Get prompts by category
    public func prompts(for category: PromptCategory) -> [BenchmarkPrompt] {
        defaultPrompts.filter { $0.category == category }
    }

    /// Create custom prompt
    public func createCustomPrompt(
        text: String,
        expectedTokens: Int = 100
    ) -> BenchmarkPrompt {
        BenchmarkPrompt(
            id: "custom-\(UUID().uuidString)",
            text: text,
            category: .custom,
            expectedTokens: expectedTokens
        )
    }
}
