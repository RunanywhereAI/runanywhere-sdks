//
//  LoraExamplePrompts.swift
//  RunAnywhereAI
//
//  Example prompts for each LoRA adapter, keyed by adapter filename.
//  Shown in the loaded LoRA adapter card so users can quickly test the adapter.
//  Matches Android's LoraExamplePrompts.kt.

import Foundation

enum LoraExamplePrompts {

    private static let promptsByFilename: [String: [String]] = [
        "code-assistant-Q8_0.gguf": [
            "Write a Python function to reverse a linked list",
            "Explain the difference between a stack and a queue with code examples",
        ],
        "reasoning-logic-Q8_0.gguf": [
            "If all roses are flowers and some flowers fade quickly, can we conclude some roses fade quickly?",
            "A farmer has 17 sheep. All but 9 die. How many are left?",
        ],
        "medical-qa-Q8_0.gguf": [
            "What are the common symptoms of vitamin D deficiency?",
            "Explain the difference between Type 1 and Type 2 diabetes",
        ],
        "creative-writing-Q8_0.gguf": [
            "Write a short story about a robot discovering emotions for the first time",
            "Describe a sunset over the ocean using vivid sensory language",
        ],
    ]

    /// Get example prompts for a loaded adapter by its file path.
    static func forAdapterPath(_ path: String) -> [String] {
        let filename = URL(fileURLWithPath: path).lastPathComponent
        return promptsByFilename[filename] ?? []
    }
}
