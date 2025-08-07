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

// MARK: - Analytics Models

public struct MessageAnalytics: Codable {
    // Identifiers
    let messageId: String
    let conversationId: String
    let modelId: String
    let modelName: String
    let framework: String
    let timestamp: Date

    // Timing Metrics
    let timeToFirstToken: TimeInterval?
    let totalGenerationTime: TimeInterval
    let thinkingTime: TimeInterval?
    let responseTime: TimeInterval?

    // Token Metrics
    let inputTokens: Int
    let outputTokens: Int
    let thinkingTokens: Int?
    let responseTokens: Int
    let averageTokensPerSecond: Double

    // Quality Metrics
    let messageLength: Int
    let wasThinkingMode: Bool
    let wasInterrupted: Bool
    let retryCount: Int
    let completionStatus: CompletionStatus

    // Performance Indicators
    let tokensPerSecondHistory: [Double] // Real-time speed tracking
    let generationMode: GenerationMode // streaming vs non-streaming

    // Context Information
    let contextWindowUsage: Double // percentage
    let generationParameters: GenerationParameters

    public enum CompletionStatus: String, Codable {
        case complete
        case interrupted
        case failed
        case timeout
    }

    public enum GenerationMode: String, Codable {
        case streaming
        case nonStreaming
    }

    public struct GenerationParameters: Codable {
        let temperature: Double
        let maxTokens: Int
        let topP: Double?
        let topK: Int?

        init(temperature: Double = 0.7, maxTokens: Int = 500, topP: Double? = nil, topK: Int? = nil) {
            self.temperature = temperature
            self.maxTokens = maxTokens
            self.topP = topP
            self.topK = topK
        }
    }
}

public struct ConversationAnalytics: Codable {
    let conversationId: String
    let startTime: Date
    let endTime: Date?
    let messageCount: Int

    // Aggregate Metrics
    let averageTTFT: TimeInterval
    let averageGenerationSpeed: Double
    let totalTokensUsed: Int
    let modelsUsed: Set<String>

    // Efficiency Metrics
    let thinkingModeUsage: Double // percentage
    let completionRate: Double // successful / total
    let averageMessageLength: Int

    // Real-time Metrics
    let currentModel: String?
    let ongoingMetrics: MessageAnalytics?
}

// Simple model reference for messages
public struct MessageModelInfo: Codable {
    public let modelId: String
    public let modelName: String
    public let framework: String

    public init(from modelInfo: ModelInfo) {
        self.modelId = modelInfo.id
        self.modelName = modelInfo.name
        self.framework = modelInfo.compatibleFrameworks.first?.rawValue ?? "unknown"
    }
}

// Local Message type for the app
public struct Message: Identifiable, Codable {
    public let id: UUID
    public let role: Role
    public let content: String
    public let thinkingContent: String?
    public let timestamp: Date

    // NEW: Analytics data
    public let analytics: MessageAnalytics?
    public let modelInfo: MessageModelInfo? // Link to specific model used

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
        timestamp: Date = Date(),
        analytics: MessageAnalytics? = nil,
        modelInfo: MessageModelInfo? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.timestamp = timestamp
        self.analytics = analytics
        self.modelInfo = modelInfo
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
    @Published var currentConversation: Conversation?

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

        // Ensure user settings are applied (safety check)
        Task {
            await ensureSettingsAreApplied()
        }

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

                // Get SDK configuration for generation options
                let effectiveSettings = await sdk.getGenerationSettings()
                let options = GenerationOptions(
                    maxTokens: effectiveSettings.maxTokens,
                    temperature: Float(effectiveSettings.temperature)
                    // No context passed - it's all in the prompt now
                )

                logger.info("📝 Generation options created, useStreaming: \(self.useStreaming)")

                if useStreaming {
                    // Use streaming generation for real-time updates
                    var fullResponse = ""
                    var isInThinkingMode = false
                    var thinkingContent = ""
                    var responseContent = ""
                    var _ = Date() // lastTokenTime tracking for future use
                    let _ : TimeInterval = 30.0 // 30 seconds timeout for thinking (not used yet)

                    // Analytics tracking
                    let startTime = Date()
                    var firstTokenTime: Date? = nil
                    var thinkingStartTime: Date? = nil
                    var thinkingEndTime: Date? = nil
                    var tokensPerSecondHistory: [Double] = []
                    var totalTokensReceived = 0
                    var wasInterrupted = false

                    logger.info("📤 Sending prompt to SDK.generateStream")
                    let stream = sdk.generateStream(prompt: fullPrompt, options: options)

                    // Stream tokens as they arrive
                    for try await token in stream {
                        fullResponse += token
                        // Track token timing (lastTokenTime could be used for timeout detection)
                        totalTokensReceived += 1

                        // Track first token time
                        if firstTokenTime == nil {
                            firstTokenTime = Date()
                        }

                        // Calculate real-time tokens per second every 10 tokens
                        if totalTokensReceived % 10 == 0 {
                            let elapsed = Date().timeIntervalSince(firstTokenTime ?? startTime)
                            if elapsed > 0 {
                                let currentSpeed = Double(totalTokensReceived) / elapsed
                                tokensPerSecondHistory.append(currentSpeed)
                            }
                        }

                        // Check for thinking tags
                        if fullResponse.contains("<think>") && !isInThinkingMode {
                            isInThinkingMode = true
                            thinkingStartTime = Date()
                            logger.info("🧠 Entering thinking mode")
                        }

                        if isInThinkingMode {
                            if fullResponse.contains("</think>") {
                                // Extract thinking and response content
                                if let thinkingStart = fullResponse.range(of: "<think>"),
                                   let thinkingEnd = fullResponse.range(of: "</think>") {
                                    thinkingContent = String(fullResponse[thinkingStart.upperBound..<thinkingEnd.lowerBound])
                                    responseContent = String(fullResponse[thinkingEnd.upperBound...])
                                    isInThinkingMode = false
                                    thinkingEndTime = Date()
                                    logger.info("🧠 Exiting thinking mode - found closing tag")
                                }
                            } else {
                                // Still in thinking mode, extract current thinking content
                                if let thinkingStart = fullResponse.range(of: "<think>") {
                                    thinkingContent = String(fullResponse[thinkingStart.upperBound...])
                                }
                            }
                        } else {
                            // Not in thinking mode, show response tokens directly
                            responseContent = fullResponse.replacingOccurrences(of: "</think>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        }

                        // Update the assistant message with current content
                        await MainActor.run {
                            if messageIndex < self.messages.count {
                                let currentMessage = self.messages[messageIndex]
                                let displayContent = isInThinkingMode ? "" : responseContent
                                let updatedMessage = Message(
                                    id: currentMessage.id,
                                    role: currentMessage.role,
                                    content: displayContent,
                                    thinkingContent: thinkingContent.isEmpty ? nil : thinkingContent.trimmingCharacters(in: .whitespacesAndNewlines),
                                    timestamp: currentMessage.timestamp
                                )
                                self.messages[messageIndex] = updatedMessage

                                // Notify UI to scroll during streaming
                                NotificationCenter.default.post(name: Notification.Name("MessageContentUpdated"), object: nil)
                            }
                        }
                    }

                    logger.info("Streaming completed with response: \(fullResponse)")

                    // Analytics: Mark end time and check for interruption
                    let endTime = Date()
                    wasInterrupted = isInThinkingMode && !fullResponse.contains("</think>")

                    // Handle edge case: Stream ended while still in thinking mode (token limit reached)
                    if isInThinkingMode && !fullResponse.contains("</think>") {
                        logger.warning("⚠️ Stream ended while in thinking mode - handling gracefully")
                        wasInterrupted = true

                        // Check if we have any thinking content to show
                        if !thinkingContent.isEmpty {
                            // Show the partial thinking content and treat the rest as response
                            let remainingContent = fullResponse
                                .replacingOccurrences(of: "<think>", with: "")
                                .replacingOccurrences(of: thinkingContent, with: "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)

                            await MainActor.run {
                                if messageIndex < self.messages.count {
                                    // Generate intelligent response based on thinking content
                                    let intelligentResponse = remainingContent.isEmpty ?
                                        self.generateThinkingSummaryResponse(from: thinkingContent) : remainingContent

                                    let updatedMessage = Message(
                                        id: self.messages[messageIndex].id,
                                        role: self.messages[messageIndex].role,
                                        content: intelligentResponse,
                                        thinkingContent: thinkingContent.trimmingCharacters(in: .whitespacesAndNewlines),
                                        timestamp: self.messages[messageIndex].timestamp
                                    )
                                    self.messages[messageIndex] = updatedMessage
                                }
                            }
                        } else {
                            // No thinking content, treat entire response as regular content
                            let cleanContent = fullResponse
                                .replacingOccurrences(of: "<think>", with: "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)

                            await MainActor.run {
                                if messageIndex < self.messages.count {
                                    let fallbackResponse = cleanContent.isEmpty ?
                                        "I need to think more about this. Could you rephrase your question?" : cleanContent

                                    let updatedMessage = Message(
                                        id: self.messages[messageIndex].id,
                                        role: self.messages[messageIndex].role,
                                        content: fallbackResponse,
                                        thinkingContent: nil,
                                        timestamp: self.messages[messageIndex].timestamp
                                    )
                                    self.messages[messageIndex] = updatedMessage
                                }
                            }
                        }
                    } else {
                        // Normal completion with proper closing tag
                        if let thinkingRange = fullResponse.range(of: "<think>"),
                           let thinkingEndRange = fullResponse.range(of: "</think>") {
                            thinkingContent = String(fullResponse[thinkingRange.upperBound..<thinkingEndRange.lowerBound])
                            responseContent = String(fullResponse[thinkingEndRange.upperBound...])

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
                    }

                    // Collect analytics for streaming generation
                    if let conversationId = currentConversation?.id,
                       messageIndex < messages.count {
                        let finalResponseContent = responseContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        let finalThinkingContent = thinkingContent.isEmpty ? nil : thinkingContent.trimmingCharacters(in: .whitespacesAndNewlines)

                        let analytics = collectMessageAnalytics(
                            messageId: messages[messageIndex].id.uuidString,
                            conversationId: conversationId,
                            startTime: startTime,
                            endTime: endTime,
                            firstTokenTime: firstTokenTime,
                            thinkingStartTime: thinkingStartTime,
                            thinkingEndTime: thinkingEndTime,
                            inputText: prompt,
                            outputText: finalResponseContent,
                            thinkingText: finalThinkingContent,
                            tokensPerSecondHistory: tokensPerSecondHistory,
                            wasInterrupted: wasInterrupted,
                            options: options
                        )

                        // Update message with analytics
                        await MainActor.run {
                            if let analytics = analytics, messageIndex < self.messages.count {
                                let currentMessage = self.messages[messageIndex]
                                let modelInfo = ModelListViewModel.shared.currentModel != nil ? MessageModelInfo(from: ModelListViewModel.shared.currentModel!) : nil

                                self.logger.info("📊 Attaching analytics to message \(messageIndex): tokens/sec = \(analytics.averageTokensPerSecond), time = \(analytics.totalGenerationTime)")

                                let updatedMessage = Message(
                                    id: currentMessage.id,
                                    role: currentMessage.role,
                                    content: currentMessage.content,
                                    thinkingContent: currentMessage.thinkingContent,
                                    timestamp: currentMessage.timestamp,
                                    analytics: analytics,
                                    modelInfo: modelInfo
                                )
                                self.messages[messageIndex] = updatedMessage

                                // Update conversation-level analytics
                                self.updateConversationAnalytics()
                            }
                        }
                    }
                } else {
                    // Use non-streaming generation to get thinking content
                    let startTime = Date()
                    let wasInterrupted = false
                    let result = try await sdk.generate(prompt: fullPrompt, options: options)
                    let endTime = Date()

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

                    // Collect analytics for non-streaming generation
                    if let conversationId = currentConversation?.id,
                       messageIndex < messages.count {
                        let analytics = collectMessageAnalytics(
                            messageId: messages[messageIndex].id.uuidString,
                            conversationId: conversationId,
                            startTime: startTime,
                            endTime: endTime,
                            firstTokenTime: nil, // Not applicable for non-streaming
                            thinkingStartTime: nil, // Not tracked separately in non-streaming
                            thinkingEndTime: nil,
                            inputText: prompt,
                            outputText: result.text,
                            thinkingText: result.thinkingContent,
                            tokensPerSecondHistory: [], // Not applicable for non-streaming
                            wasInterrupted: wasInterrupted,
                            options: options
                        )

                        // Update message with analytics
                        await MainActor.run {
                            if let analytics = analytics, messageIndex < self.messages.count {
                                let currentMessage = self.messages[messageIndex]
                                let modelInfo = ModelListViewModel.shared.currentModel != nil ? MessageModelInfo(from: ModelListViewModel.shared.currentModel!) : nil

                                self.logger.info("📊 Attaching analytics to message \(messageIndex): tokens/sec = \(analytics.averageTokensPerSecond), time = \(analytics.totalGenerationTime)")

                                let updatedMessage = Message(
                                    id: currentMessage.id,
                                    role: currentMessage.role,
                                    content: currentMessage.content,
                                    thinkingContent: currentMessage.thinkingContent,
                                    timestamp: currentMessage.timestamp,
                                    analytics: analytics,
                                    modelInfo: modelInfo
                                )
                                self.messages[messageIndex] = updatedMessage

                                // Update conversation-level analytics
                                self.updateConversationAnalytics()
                            }
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

                // Save final assistant message to conversation with analytics
                if messageIndex < self.messages.count,
                   let conversation = self.currentConversation {
                    // Update conversation with final message including analytics
                    var updatedConversation = conversation
                    updatedConversation.messages = self.messages
                    updatedConversation.modelName = self.loadedModelName

                    // Log analytics status
                    let analyticsCount = self.messages.compactMap { $0.analytics }.count
                    self.logger.info("💾 Saving conversation with \(self.messages.count) messages, \(analyticsCount) have analytics")

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

        // For new conversations (empty messages), start fresh
        // For existing conversations, load the messages
        if conversation.messages.isEmpty {
            messages = []
            // Add system message if model is loaded
            if isModelLoaded {
                addSystemMessage()
            }
        } else {
            messages = conversation.messages

            // Log analytics status
            let analyticsCount = messages.compactMap { $0.analytics }.count
            logger.info("📂 Loaded conversation with \(self.messages.count) messages, \(analyticsCount) have analytics")
        }

        // Update model info if available
        if let modelName = conversation.modelName {
            loadedModelName = modelName
        }
    }

    func createNewConversation() {
        clearChat()
    }

    private func ensureSettingsAreApplied() async {
        // Load user settings from UserDefaults and apply to SDK if needed
        let savedTemperature = UserDefaults.standard.double(forKey: "defaultTemperature")
        let temperature = savedTemperature != 0 ? savedTemperature : 0.7

        let savedMaxTokens = UserDefaults.standard.integer(forKey: "defaultMaxTokens")
        let maxTokens = savedMaxTokens != 0 ? savedMaxTokens : 10000

        // Apply settings to SDK (this is idempotent, so safe to call multiple times)
        await sdk.setTemperature(Float(temperature))
        await sdk.setMaxTokens(maxTokens)

        logger.info("🔧 Ensured settings are applied - Temperature: \(temperature), MaxTokens: \(maxTokens)")
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
        for (_, message) in messages.enumerated() {
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

    // MARK: - Thinking Summary Generation

    private func generateThinkingSummaryResponse(from thinkingContent: String) -> String {
        let thinking = thinkingContent.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract key insights from thinking content
        let keyPhrases = extractKeyPhrasesFromThinking(thinking)

        if !keyPhrases.isEmpty {
            // Create natural response based on thinking
            if thinking.lowercased().contains("user") && thinking.lowercased().contains("help") {
                return "I'm here to help! \(keyPhrases.first ?? "")"
            } else if thinking.lowercased().contains("question") || thinking.lowercased().contains("ask") {
                return "That's a good question. \(keyPhrases.first ?? "")"
            } else if thinking.lowercased().contains("consider") || thinking.lowercased().contains("think") {
                return "Let me consider this. \(keyPhrases.first ?? "")"
            } else {
                return keyPhrases.first ?? "I was analyzing your message. How can I help you further?"
            }
        }

        // Fallback based on thinking content length and context
        if thinking.count > 200 {
            return "I was thinking through this carefully. Could you help me understand what you're looking for?"
        } else {
            return "I'm processing your message. What would be most helpful for you?"
        }
    }

    private func extractKeyPhrasesFromThinking(_ thinking: String) -> [String] {
        var keyPhrases: [String] = []

        // Split into sentences and find meaningful ones
        let sentences = thinking.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 10 && $0.count < 100 }

        // Look for sentences that seem like conclusions or key insights
        for sentence in sentences.prefix(3) {
            let lowercased = sentence.lowercased()

            // Skip meta-thinking sentences
            if lowercased.contains("i should") ||
               lowercased.contains("let me") ||
               lowercased.contains("i need to") ||
               lowercased.contains("maybe i") {
                continue
            }

            // Include substantive thoughts
            if lowercased.contains("because") ||
               lowercased.contains("since") ||
               lowercased.contains("this means") ||
               lowercased.contains("the key is") ||
               lowercased.contains("important") {
                keyPhrases.append(sentence)
            }
        }

        // If no good phrases found, take first substantial sentence
        if keyPhrases.isEmpty {
            if let firstGoodSentence = sentences.first(where: { $0.count > 20 && $0.count < 80 }) {
                keyPhrases.append(firstGoodSentence + "...")
            }
        }

        return keyPhrases
    }

    // MARK: - Analytics Service

    private func collectMessageAnalytics(
        messageId: String,
        conversationId: String,
        startTime: Date,
        endTime: Date,
        firstTokenTime: Date?,
        thinkingStartTime: Date?,
        thinkingEndTime: Date?,
        inputText: String,
        outputText: String,
        thinkingText: String?,
        tokensPerSecondHistory: [Double],
        wasInterrupted: Bool,
        options: GenerationOptions
    ) -> MessageAnalytics? {

        guard let modelName = loadedModelName,
              let currentModel = ModelListViewModel.shared.currentModel else {
            logger.warning("Cannot create analytics - no model info available")
            return nil
        }

        let totalGenerationTime = endTime.timeIntervalSince(startTime)
        let timeToFirstToken = firstTokenTime?.timeIntervalSince(startTime)

        var thinkingTime: TimeInterval? = nil
        var responseTime: TimeInterval? = nil

        if let thinkingStart = thinkingStartTime, let thinkingEnd = thinkingEndTime {
            thinkingTime = thinkingEnd.timeIntervalSince(thinkingStart)
            responseTime = totalGenerationTime - (thinkingTime ?? 0)
        }

        // Calculate token counts
        let inputTokens = estimateTokenCount(inputText)
        let outputTokens = estimateTokenCount(outputText)
        let thinkingTokens = thinkingText != nil ? estimateTokenCount(thinkingText!) : nil
        let responseTokens = outputTokens - (thinkingTokens ?? 0)

        // Calculate average tokens per second
        let averageTokensPerSecond = totalGenerationTime > 0 ? Double(outputTokens) / totalGenerationTime : 0

        // Determine completion status
        let completionStatus: MessageAnalytics.CompletionStatus = wasInterrupted ? .interrupted : .complete

        // Create generation parameters
        let generationParameters = MessageAnalytics.GenerationParameters(
            temperature: Double(options.temperature),
            maxTokens: options.maxTokens,
            topP: Double(options.topP),
            topK: nil // topK not available in current GenerationOptions
        )

        return MessageAnalytics(
            messageId: messageId,
            conversationId: conversationId,
            modelId: currentModel.id,
            modelName: modelName,
            framework: currentModel.compatibleFrameworks.first?.rawValue ?? "unknown",
            timestamp: startTime,
            timeToFirstToken: timeToFirstToken,
            totalGenerationTime: totalGenerationTime,
            thinkingTime: thinkingTime,
            responseTime: responseTime,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            thinkingTokens: thinkingTokens,
            responseTokens: responseTokens,
            averageTokensPerSecond: averageTokensPerSecond,
            messageLength: outputText.count,
            wasThinkingMode: thinkingText != nil,
            wasInterrupted: wasInterrupted,
            retryCount: 0,
            completionStatus: completionStatus,
            tokensPerSecondHistory: tokensPerSecondHistory,
            generationMode: useStreaming ? .streaming : .nonStreaming,
            contextWindowUsage: 0.0, // TODO: Calculate based on model context size
            generationParameters: generationParameters
        )
    }

    // Simple token estimation (approximate)
    private func estimateTokenCount(_ text: String) -> Int {
        // Rough estimation: ~4 characters per token for English text
        return Int(ceil(Double(text.count) / 4.0))
    }

    private func updateConversationAnalytics() {
        guard let conversation = currentConversation else { return }

        let analyticsMessages = messages.compactMap { $0.analytics }

        if !analyticsMessages.isEmpty {
            let averageTTFT = analyticsMessages.compactMap { $0.timeToFirstToken }.reduce(0, +) / Double(analyticsMessages.count)
            let averageGenerationSpeed = analyticsMessages.map { $0.averageTokensPerSecond }.reduce(0, +) / Double(analyticsMessages.count)
            let totalTokensUsed = analyticsMessages.reduce(0) { $0 + $1.inputTokens + $1.outputTokens }
            let modelsUsed = Set(analyticsMessages.map { $0.modelName })

            let thinkingMessages = analyticsMessages.filter { $0.wasThinkingMode }
            let thinkingModeUsage = Double(thinkingMessages.count) / Double(analyticsMessages.count)

            let completedMessages = analyticsMessages.filter { $0.completionStatus == .complete }
            let completionRate = Double(completedMessages.count) / Double(analyticsMessages.count)

            let averageMessageLength = analyticsMessages.reduce(0) { $0 + $1.messageLength } / analyticsMessages.count

            let conversationAnalytics = ConversationAnalytics(
                conversationId: conversation.id,
                startTime: conversation.createdAt,
                endTime: Date(),
                messageCount: messages.count,
                averageTTFT: averageTTFT,
                averageGenerationSpeed: averageGenerationSpeed,
                totalTokensUsed: totalTokensUsed,
                modelsUsed: modelsUsed,
                thinkingModeUsage: thinkingModeUsage,
                completionRate: completionRate,
                averageMessageLength: averageMessageLength,
                currentModel: loadedModelName,
                ongoingMetrics: nil
            )

            // Update conversation in store
            var updatedConversation = conversation
            updatedConversation.analytics = conversationAnalytics
            updatedConversation.performanceSummary = PerformanceSummary(from: messages)
            conversationStore.updateConversation(updatedConversation)
        }
    }

}
