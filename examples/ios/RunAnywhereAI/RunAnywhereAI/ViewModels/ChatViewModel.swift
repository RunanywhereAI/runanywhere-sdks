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
    @Published var useStreaming = false  // Use non-streaming for more reliable generation

    private let sdk = RunAnywhereSDK.shared
    private let conversationStore = ConversationStore.shared
    private var generationTask: Task<Void, Never>?
    private var conversationContext: Context?
    @Published var currentSessionId: UUID?
    @Published var showAnalytics = false
    private var currentConversation: Conversation?

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
        guard canSend else { return }

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
            do {
                // Check if we need to reload the model in SDK
                // This handles cases where the app was restarted but UI state shows model as loaded
                if isModelLoaded, let _ = loadedModelName {
                    // Try to ensure the model is actually loaded in the SDK
                    // Get the model from ModelListViewModel
                    if let model = ModelListViewModel.shared.currentModel {
                        do {
                            // This will reload the model if it's not already loaded
                            _ = try await sdk.loadModel(model.id)
                            print("Ensured model '\(model.name)' is loaded in SDK")
                        } catch {
                            print("Failed to ensure model is loaded: \(error)")
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
                    throw ChatError.noModelLoaded
                }

                print("Starting generation with prompt: \(prompt), streaming: \(useStreaming)")

                // Build conversation context with previous messages
                var contextMessages: String = ""
                for message in self.messages where message.role != .system {
                    if message.role == .user {
                        contextMessages += "User: \(message.content)\n"
                    } else if message.role == .assistant {
                        contextMessages += "Assistant: \(message.content)\n"
                    }
                }

                // Create a full prompt with context
                let fullPrompt = contextMessages.isEmpty ? prompt : contextMessages + "User: \(prompt)\nAssistant:"

                let options = GenerationOptions(
                    maxTokens: 500,
                    temperature: 0.7,
                    context: self.conversationContext
                )

                // Ensure analytics are initialized before generation
                await self.initializeAnalytics()

                // Get the current session ID - will be set after generation starts
                let sessionId = await sdk.getCurrentSessionId()
                print("📊 [ChatViewModel] Current session ID before generation: \(sessionId?.uuidString ?? "nil")")

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

                    print("Streaming completed with response: \(fullResponse)")

                    // Get the session ID after generation (should be created now)
                    currentSessionId = await sdk.getCurrentSessionId()
                    print("📊 [ChatViewModel] Session ID after streaming generation: \(currentSessionId?.uuidString ?? "nil")")

                    // Log analytics info
                    await logAnalyticsForCurrentGeneration()

                    // Update context with the assistant's response
                    self.updateContextWithResponse(fullResponse)

                    // Note: Thinking content is not available in streaming mode
                    // Could potentially parse it from the fullResponse if needed
                } else {
                    // Use non-streaming generation to get thinking content
                    let result = try await sdk.generate(prompt: fullPrompt, options: options)

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

                    // Get the session ID after generation (should be created now)
                    currentSessionId = await sdk.getCurrentSessionId()
                    print("📊 [ChatViewModel] Session ID after non-streaming generation: \(currentSessionId?.uuidString ?? "nil")")

                    // Log analytics info
                    await logAnalyticsForCurrentGeneration()

                    // Update context with the assistant's response
                    self.updateContextWithResponse(result.text)
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

                // Save final assistant message to conversation
                if messageIndex < self.messages.count,
                   let conversation = self.currentConversation {
                    let assistantMessage = self.messages[messageIndex]
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
        currentSessionId = nil  // Start a new analytics session
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
                        print("Verified model '\(currentModel.name)' is loaded in SDK")

                        // Now that SDK is initialized and model is loaded, initialize analytics
                        await self.initializeAnalytics()
                    } catch {
                        print("Failed to verify model is loaded: \(error)")
                        await MainActor.run {
                            self.isModelLoaded = false
                            self.loadedModelName = nil
                        }
                    }
                }
            } else {
                self.isModelLoaded = false
                self.loadedModelName = nil

                // Still try to initialize analytics even without a model
                Task {
                    await self.initializeAnalytics()
                }
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

    private func initializeAnalytics() async {
        do {
            // Enable analytics for real-time data capture - force enable with fallback
            print("📊 Initializing analytics safely after SDK startup...")

            // Always ensure analytics are enabled with hardcoded fallback
            await sdk.setAnalyticsEnabled(true)
            await sdk.setEnableLiveMetrics(true)

            // Log current analytics configuration
            let analyticsEnabled = await sdk.getAnalyticsEnabled()
            let liveMetricsEnabled = await sdk.getEnableLiveMetrics()
            print("📊 Analytics Configuration - Enabled: \(analyticsEnabled), Live Metrics: \(liveMetricsEnabled)")

        } catch {
            print("⚠️ Failed to initialize analytics: \(error)")
            // Continue without analytics rather than crashing
        }
    }

    func logAnalyticsForCurrentGeneration() async {
        guard let sessionId = currentSessionId else { return }

        // Get the current session
        if let session = await sdk.getAnalyticsSession(sessionId) {
            print("📊 Current Session Analytics:")
            print("   Session ID: \(String(session.id.uuidString.prefix(8)))")
            print("   Model: \(session.modelId)")
            print("   Type: \(session.sessionType)")
            print("   Generations: \(session.generationCount)")
            print("   Total Tokens: \(session.totalInputTokens + session.totalOutputTokens)")
            print("   Avg Speed: \(String(format: "%.2f", session.averageTokensPerSecond)) tokens/sec")
            print("   Duration: \(String(format: "%.2f", session.totalDuration))s")
        }

        // Get the latest generation
        let generations = await sdk.getGenerationsForSession(sessionId)
        if let latestGen = generations.last, let performance = latestGen.performance {
            print("📊 Latest Generation:")
            print("   Time to First Token: \(String(format: "%.2f", performance.timeToFirstToken))s")
            print("   Total Time: \(String(format: "%.2f", performance.totalGenerationTime))s")
            print("   Tokens/sec: \(String(format: "%.2f", performance.tokensPerSecond))")
            print("   Execution: \(performance.executionTarget)")
        }
    }

    func getAllAnalytics() async -> [GenerationSession] {
        return await sdk.getAllAnalyticsSessions()
    }
}
