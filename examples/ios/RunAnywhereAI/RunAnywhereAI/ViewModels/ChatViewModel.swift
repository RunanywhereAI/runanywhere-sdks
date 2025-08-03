//
//  ChatViewModel.swift
//  RunAnywhereAI
//
//  Simplified version that uses SDK directly
//

import Foundation
import SwiftUI
import RunAnywhereSDK

enum ChatError: LocalizedError {
    case noModelLoaded

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            return "❌ No model is loaded. Please select and load a model from the Models tab first."
        }
    }
}

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var currentInput = ""
    @Published var error: Error?
    @Published var isModelLoaded = false
    @Published var loadedModelName: String?

    private let sdk = RunAnywhereSDK.shared
    private var generationTask: Task<Void, Never>?

    var canSend: Bool {
        !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating && isModelLoaded
    }

    init() {
        addSystemMessage()
    }

    private func addSystemMessage() {
        let content = if isModelLoaded, let modelName = loadedModelName {
            "Model '\(modelName)' is loaded and ready to chat!"
        } else {
            "Welcome! Select and download a model from the Models tab to start chatting."
        }

        let systemMessage = ChatMessage(role: .system, content: content)
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
                // Ensure model is loaded before generating
                if !isModelLoaded {
                    throw ChatError.noModelLoaded
                }

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
                        let errorMessage = if error is ChatError {
                            error.localizedDescription
                        } else {
                            "❌ Generation failed: \(error.localizedDescription)"
                        }
                        self.messages[messageIndex].content = errorMessage
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

    func loadModel(_ modelInfo: ModelInfo) async {
        do {
            _ = try await sdk.loadModel(modelInfo.id)
            await MainActor.run {
                self.isModelLoaded = true
                self.loadedModelName = modelInfo.name
                // Update system message to reflect loaded model
                self.messages.removeAll()
                self.addSystemMessage()
            }
        } catch {
            await MainActor.run {
                self.error = error
                self.isModelLoaded = false
                self.loadedModelName = nil
            }
        }
    }

    func checkModelStatus() async {
        // This could be enhanced to check SDK's current model state
        // For now, we'll rely on our internal state
    }
}
