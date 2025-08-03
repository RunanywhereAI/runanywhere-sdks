//
//  ChatViewModel.swift
//  RunAnywhereAI
//
//  Simplified version that uses SDK directly
//

import Foundation
import SwiftUI
import RunAnywhereSDK

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var currentInput = ""
    @Published var error: Error?

    private let sdk = RunAnywhereSDK.shared
    private var generationTask: Task<Void, Never>?

    var canSend: Bool {
        !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    init() {
        addSystemMessage()
    }

    private func addSystemMessage() {
        let systemMessage = ChatMessage(
            role: .system,
            content: "Welcome! Select a model from the Models tab to start chatting."
        )
        messages.append(systemMessage)
    }

    func sendMessage() async {
        guard canSend else { return }

        let userMessage = ChatMessage(role: .user, content: currentInput)
        messages.append(userMessage)

        let prompt = currentInput
        currentInput = ""
        isGenerating = true
        error = nil

        // Create assistant message that we'll update with streaming tokens
        let assistantMessage = ChatMessage(role: .assistant, content: "")
        messages.append(assistantMessage)
        let messageIndex = messages.count - 1

        generationTask = Task {
            do {
                // Direct SDK usage - simple generate call for now
                let response = try await sdk.generate(prompt: prompt)

                // Update the assistant message with the response
                if messageIndex < self.messages.count {
                    self.messages[messageIndex].content = response.text
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    // Add error message to chat
                    if messageIndex < self.messages.count {
                        self.messages[messageIndex].content = "❌ Generation failed: \(error.localizedDescription)"
                    }
                }
            }

            await MainActor.run {
                self.isGenerating = false
            }
        }
    }

    func clearChat() {
        generationTask?.cancel()
        messages.removeAll()
        addSystemMessage()
        currentInput = ""
        isGenerating = false
        error = nil
    }

    func stopGeneration() {
        generationTask?.cancel()
        isGenerating = false
    }
}
