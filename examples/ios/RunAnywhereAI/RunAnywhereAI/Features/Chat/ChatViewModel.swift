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

// Local Message type for the app
public struct Message: Identifiable, Codable {
    public let id: UUID
    public let role: Role
    public let content: String
    public let thinkingContent: String?
    public let timestamp: Date

    public enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        thinkingContent: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.timestamp = timestamp
    }
}

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
    @Published var messages: [Message] = []
    @Published var isGenerating = false
    @Published var currentInput = ""
    @Published var error: Error?
    @Published var isModelLoaded = false
    @Published var loadedModelName: String?
    @Published var useStreaming = true  // Enable streaming for real-time token display

    private let sdk = RunAnywhereSDK.shared
    private let conversationStore = ConversationStore.shared
    private var generationTask: Task<Void, Never>?
    private var currentConversation: Conversation?

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "ChatViewModel")

    var canSend: Bool {
        !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating && isModelLoaded
    }

    init() {
        // Always start with a new conversation for a fresh chat experience
        let conversation = conversationStore.createConversation()
        currentConversation = conversation
        messages = [] // Start with empty messages array

        // Add system message only if model is already loaded
        if isModelLoaded {
            addSystemMessage()
        }

        // Listen for model loaded notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modelLoaded(_:)),
            name: Notification.Name("ModelLoaded"),
            object: nil
        )

        // Listen for conversation selection notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(conversationSelected(_:)),
            name: Notification.Name("ConversationSelected"),
            object: nil
        )

        // Delay analytics initialization to avoid crash during SDK startup
        // Analytics will be initialized when the view appears or when first used
    }

    private func addSystemMessage() {
        // Only add system message if model is loaded
        guard isModelLoaded, let modelName = loadedModelName else {
            return
        }

        let content = "Model '\(modelName)' is loaded and ready to chat!"
        let systemMessage = Message(role: .system, content: content)
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

                let prompt = currentInput
        currentInput = ""
        isGenerating = true
        error = nil

        let userMessage = Message(role: .user, content: prompt)
        messages.append(userMessage)

        // Save user message to conversation
        if let conversation = currentConversation {
            conversationStore.addMessage(userMessage, to: conversation)
        }

        // Create assistant message that we'll update with streaming tokens
        let assistantMessage = Message(role: .assistant, content: "")
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

                // Send only the new user message - LLM.swift manages history internally
                let fullPrompt = prompt
                logger.info("📝 Sending new message only: \(fullPrompt)")

                let options = GenerationOptions(
                    maxTokens: 500,
                    temperature: 0.7
                    // No context passed - it's all in the prompt now
                )

                logger.info("📝 Generation options created, useStreaming: \(self.useStreaming)")

                if useStreaming {
                    // Use streaming generation for real-time updates
                    var fullResponse = ""
                    logger.info("📤 Sending prompt to SDK.generateStream")
                    let stream = sdk.generateStream(prompt: fullPrompt, options: options)

                    // Stream tokens as they arrive
                    for try await token in stream {
                        fullResponse += token
                        // Update the assistant message with each new token
                        await MainActor.run {
                            if messageIndex < self.messages.count {
                                // Create a new message with updated content since Message is immutable
                                let currentMessage = self.messages[messageIndex]
                                let updatedMessage = Message(
                                    role: currentMessage.role,
                                    content: currentMessage.content + token,
                                    timestamp: currentMessage.timestamp
                                )
                                self.messages[messageIndex] = updatedMessage
                            }
                        }
                    }

                    logger.info("Streaming completed with response: \(fullResponse)")


                    // No need to update context - it's managed in messages array

                    // Parse thinking content from the full response
                    if let thinkingRange = fullResponse.range(of: "<think>"),
                       let thinkingEndRange = fullResponse.range(of: "</think>") {
                        let thinkingContent = String(fullResponse[thinkingRange.upperBound..<thinkingEndRange.lowerBound])
                        let responseContent = String(fullResponse[thinkingEndRange.upperBound...])

                        await MainActor.run {
                            if messageIndex < self.messages.count {
                                let updatedMessage = Message(
                                    id: self.messages[messageIndex].id,
                                    role: self.messages[messageIndex].role,
                                    content: responseContent.trimmingCharacters(in: .whitespacesAndNewlines),
                                    thinkingContent: thinkingContent.trimmingCharacters(in: .whitespacesAndNewlines),
                                    timestamp: self.messages[messageIndex].timestamp
                                )
                                self.messages[messageIndex] = updatedMessage
                            }
                        }
                    }
                } else {
                    // Use non-streaming generation to get thinking content
                    let result = try await sdk.generate(prompt: fullPrompt, options: options)

                    logger.info("Generation completed with result: \(result.text)")

                    // Update the assistant message with the complete response
                    await MainActor.run {
                        if messageIndex < self.messages.count {
                            let currentMessage = self.messages[messageIndex]
                            let updatedMessage = Message(
                                role: currentMessage.role,
                                content: result.text,
                                thinkingContent: result.thinkingContent,
                                timestamp: currentMessage.timestamp
                            )
                            self.messages[messageIndex] = updatedMessage
                        }
                    }


                    // No need to update context - it's managed in messages array
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
                        let currentMessage = self.messages[messageIndex]
                        let updatedMessage = Message(
                            role: currentMessage.role,
                            content: errorMessage,
                            timestamp: currentMessage.timestamp
                        )
                        self.messages[messageIndex] = updatedMessage
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

        // Only add system message if model is loaded
        if isModelLoaded {
            addSystemMessage()
        }
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
        Task {
            if let model = notification.object as? ModelInfo {
                await MainActor.run {
                    self.isModelLoaded = true
                    self.loadedModelName = model.name
                    // Update system message to reflect loaded model
                    if self.messages.first?.role == .system {
                        self.messages.removeFirst()
                    }
                    self.addSystemMessage()
                }
            } else {
                // If no model object is passed, check the current model state
                await self.checkModelStatus()
            }
        }
    }

    @objc private func conversationSelected(_ notification: Notification) {
        if let conversation = notification.object as? Conversation {
            loadConversation(conversation)
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

    private func buildFullPrompt() -> String {
        // Since LLM.swift handles its own template formatting, we should pass raw messages
        // Let's try a simple conversation format first
        var promptParts: [String] = []

        logger.info("Building simple prompt from \(self.messages.count) messages")

        // Build conversation in a simple format
        var hasMessages = false
        for (index, message) in messages.enumerated() {
            switch message.role {
            case .user:
                if hasMessages {
                    promptParts.append("")  // Add blank line between exchanges
                }
                promptParts.append("User: \(message.content)")
                hasMessages = true
            case .assistant:
                // Only add assistant messages that have content
                if !message.content.isEmpty {
                    promptParts.append("Assistant: \(message.content)")
                }
            case .system:
                // Skip system messages in the prompt
                continue
            }
        }

        // Don't add "Assistant:" at the end - let the model complete naturally

        let fullPrompt = promptParts.joined(separator: "\n")
        logger.info("📝 Built simple prompt with \(promptParts.count) parts")
        logger.info("📝 Final prompt:\n\(fullPrompt)")
        return fullPrompt
    }

    // MARK: - Analytics



}
