//
//  ChatViewModel.swift
//  RunAnywhereAI
//
//  Simplified version that uses SDK directly
//

import Foundation
import SwiftUI
import RunAnywhereSDK
import os.log

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
    @Published var useStreaming = true  // Enable streaming for real-time token display

    private let sdk = RunAnywhereSDK.shared
    private let conversationStore = ConversationStore.shared
    private var generationTask: Task<Void, Never>?
    private var conversationContext: Context?
    private var currentConversation: Conversation?

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "ChatViewModel")

    var canSend: Bool {
        !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating && isModelLoaded
    }

    init() {
        // Load existing conversation or create new one
        if let conversation = conversationStore.currentConversation {
            currentConversation = conversation
            messages = conversation.messages
        } else {
            let conversation = conversationStore.createConversation()
            currentConversation = conversation
            addSystemMessage()
        }

        // Listen for model loaded notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modelLoaded(_:)),
            name: Notification.Name("ModelLoaded"),
            object: nil
        )

        // Delay analytics initialization to avoid crash during SDK startup
        // Analytics will be initialized when the view appears or when first used
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

        // Save to conversation store
        if var conversation = currentConversation {
            conversation.messages = messages
            conversationStore.updateConversation(conversation)
        }
    }

    func sendMessage() async {
        logger.info("🎯 sendMessage() called")
        logger.info("📝 canSend: \(self.canSend), isModelLoaded: \(self.isModelLoaded), loadedModelName: \(self.loadedModelName ?? "nil")")

        guard canSend else {
            logger.error("❌ canSend is false, returning")
            return
        }
        logger.info("✅ canSend is true, proceeding")

        let userMessage = ChatMessage(role: .user, content: currentInput)
        messages.append(userMessage)

        // Save user message to conversation
        if let conversation = currentConversation {
            conversationStore.addMessage(userMessage, to: conversation)
        }

        let prompt = currentInput
        currentInput = ""
        isGenerating = true
        error = nil

        // Create assistant message that we'll update with streaming tokens
        let assistantMessage = ChatMessage(role: .assistant, content: "")
        messages.append(assistantMessage)
        let messageIndex = messages.count - 1

        generationTask = Task {
            logger.info("🚀 Starting sendMessage task")
            do {
                logger.info("📋 Entering do block")
                logger.info("📝 Checking model status - isModelLoaded: \(self.isModelLoaded), loadedModelName: \(self.loadedModelName ?? "nil")")

                // Check if we need to reload the model in SDK
                // This handles cases where the app was restarted but UI state shows model as loaded
                if isModelLoaded, let _ = loadedModelName {
                    logger.info("📝 Model appears loaded, checking SDK state")
                    // Try to ensure the model is actually loaded in the SDK
                    // Get the model from ModelListViewModel
                    if let model = ModelListViewModel.shared.currentModel {
                        do {
                            // This will reload the model if it's not already loaded
                            _ = try await sdk.loadModel(model.id)
                            logger.info("✅ Ensured model '\(model.name)' is loaded in SDK")
                        } catch {
                            logger.error("Failed to ensure model is loaded: \(error)")
                            // If loading fails, update our state
                            await MainActor.run {
                                self.isModelLoaded = false
                                self.loadedModelName = nil
                            }
                            throw ChatError.noModelLoaded
                        }
                    }
                }

                // Final check - ensure model is loaded before generating
                if !isModelLoaded {
                    logger.error("❌ Model not loaded, throwing error")
                    throw ChatError.noModelLoaded
                }

                logger.info("🎯 Starting generation with prompt: \(String(prompt.prefix(50)))..., streaming: \(self.useStreaming)")

                // Just send the raw prompt - let the SDK handle context formatting
                let fullPrompt = prompt

                let options = GenerationOptions(
                    maxTokens: 500,
                    temperature: 0.7,
                    context: self.conversationContext
                )

                logger.info("📝 Generation options created, useStreaming: \(self.useStreaming)")

                if useStreaming {
                    // Use streaming generation for real-time updates
                    var fullResponse = ""
                    let stream = sdk.generateStream(prompt: fullPrompt, options: options)

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

                    logger.info("Streaming completed with response: \(fullResponse)")


                    // Update context with the assistant's response
                    self.updateContextWithResponse(fullResponse)

                    // Note: Thinking content is not available in streaming mode
                    // Could potentially parse it from the fullResponse if needed
                } else {
                    // Use non-streaming generation to get thinking content
                    let result = try await sdk.generate(prompt: fullPrompt, options: options)

                    logger.info("Generation completed with result: \(result.text)")

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


                    // Update context with the assistant's response
                    self.updateContextWithResponse(result.text)
                }
            } catch {
                logger.error("❌ Generation failed with error: \(error)")
                logger.error("❌ Error type: \(type(of: error))")
                logger.error("❌ Error details: \(String(describing: error))")

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

                // Save final assistant message to conversation
                if messageIndex < self.messages.count,
                   let conversation = self.currentConversation {
                    // Update conversation with final message
                    var updatedConversation = conversation
                    updatedConversation.messages = self.messages
                    updatedConversation.modelName = self.loadedModelName
                    self.conversationStore.updateConversation(updatedConversation)
                }
            }
        }
    }

    func clearChat() {
        generationTask?.cancel()
        messages.removeAll()
        currentInput = ""
        isGenerating = false
        error = nil

        // Create new conversation
        let conversation = conversationStore.createConversation()
        currentConversation = conversation
        addSystemMessage()
        conversationContext = nil  // Clear context when clearing chat
        // Keep allAnalytics to view history
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
                if self.messages.first?.role == .system {
                    self.messages.removeFirst()
                }
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

                // Ensure the model is actually loaded in the SDK
                Task {
                    do {
                        _ = try await sdk.loadModel(currentModel.id)
                        logger.info("Verified model '\(currentModel.name)' is loaded in SDK")

                    } catch {
                        logger.error("Failed to verify model is loaded: \(error)")
                        await MainActor.run {
                            self.isModelLoaded = false
                            self.loadedModelName = nil
                        }
                    }
                }
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

    func loadConversation(_ conversation: Conversation) {
        currentConversation = conversation
        messages = conversation.messages

        // Update model info if available
        if let modelName = conversation.modelName {
            loadedModelName = modelName
        }
    }

    func createNewConversation() {
        clearChat()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Context Management

    private func buildContext() -> Context {
        // For now, we'll just track context locally and let the SDK handle message creation
        // The SDK's ContextManager will append messages properly
        if conversationContext == nil {
            conversationContext = Context(
                messages: [],
                systemPrompt: nil,
                maxTokens: 2048
            )
        }

        return conversationContext!
    }

    private func updateContextWithResponse(_ response: String) {
        // Context will be rebuilt on next generation with all messages
        // This ensures the assistant's response is included in the next context
    }

    // MARK: - Analytics



}
