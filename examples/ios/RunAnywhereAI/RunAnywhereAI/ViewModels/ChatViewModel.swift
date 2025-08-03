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
    @Published var useStreaming = true  // Toggle between streaming and non-streaming

    private let sdk = RunAnywhereSDK.shared
    private var generationTask: Task<Void, Never>?

    var canSend: Bool {
        !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating && isModelLoaded
    }

    init() {
        addSystemMessage()

        // Listen for model loaded notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modelLoaded(_:)),
            name: Notification.Name("ModelLoaded"),
            object: nil
        )
    }

    private func addSystemMessage() {
        let content: String
        if isModelLoaded, let modelName = loadedModelName {
            content = "Model '\(modelName)' is loaded and ready to chat!"
        } else {
            content = "Welcome! Select and download a model from the Models tab to start chatting."
        }

        let systemMessage = ChatMessage(role: .system, content: content)
        messages.insert(systemMessage, at: 0)
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

                print("Starting generation with prompt: \(prompt), streaming: \(useStreaming)")

                if useStreaming {
                    // Use streaming generation for real-time updates
                    var fullResponse = ""
                    let stream = sdk.generateStream(prompt: prompt)

                    // Stream tokens as they arrive
                    for try await token in stream {
                        fullResponse += token
                        // Update the assistant message with each new token
                        await MainActor.run {
                            if messageIndex < self.messages.count {
                                self.messages[messageIndex].content += token
                            }
                        }
                    }

                    print("Streaming completed with response: \(fullResponse)")

                    // Note: Thinking content is not available in streaming mode
                    // Could potentially parse it from the fullResponse if needed
                } else {
                    // Use non-streaming generation to get thinking content
                    let result = try await sdk.generate(prompt: prompt)

                    print("Generation completed with result: \(result.text)")

                    // Update the assistant message with the complete response
                    await MainActor.run {
                        if messageIndex < self.messages.count {
                            self.messages[messageIndex].content = result.text
                            // Add thinking content if available
                            if let thinkingContent = result.thinkingContent, !thinkingContent.isEmpty {
                                self.messages[messageIndex].thinkingContent = thinkingContent
                            }
                        }
                    }
                }
            } catch {
                print("Generation failed with error: \(error)")
                await MainActor.run {
                    self.error = error
                    // Add error message to chat
                    if messageIndex < self.messages.count {
                        let errorMessage: String
                        if error is ChatError {
                            errorMessage = error.localizedDescription
                        } else {
                            errorMessage = "❌ Generation failed: \(error.localizedDescription)"
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
        // Check if a model is currently loaded in the SDK
        // Since we can't directly access SDK's current model, we'll check via ModelListViewModel
        let modelListViewModel = ModelListViewModel.shared

        await MainActor.run {
            if let currentModel = modelListViewModel.currentModel {
                self.isModelLoaded = true
                self.loadedModelName = currentModel.name
            } else {
                self.isModelLoaded = false
                self.loadedModelName = nil
            }

            // Update system message
            if self.messages.first?.role == .system {
                self.messages.removeFirst()
            }
            self.addSystemMessage()
        }
    }

    @objc private func modelLoaded(_ notification: Notification) {
        if let model = notification.object as? ModelInfo {
            Task {
                await MainActor.run {
                    self.isModelLoaded = true
                    self.loadedModelName = model.name
                    // Update system message to reflect loaded model
                    if self.messages.first?.role == .system {
                        self.messages.removeFirst()
                    }
                    self.addSystemMessage()
                }
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
