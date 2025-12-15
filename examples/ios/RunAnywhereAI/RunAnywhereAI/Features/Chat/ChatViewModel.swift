//
//  ChatViewModel.swift
//  RunAnywhereAI
//
//  Simplified version that uses SDK directly
//

import Foundation
import SwiftUI
import RunAnywhere
import Combine
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
    // MARK: - Published Properties
    @Published var messages: [Message] = []
    @Published var isGenerating = false
    @Published var currentInput = ""
    @Published var error: Error?
    @Published var selectedFramework: InferenceFramework?
    @Published var isModelLoaded = false
    @Published var loadedModelName: String?
    @Published var useStreaming = true  // Enable streaming for real-time token display
    @Published var modelSupportsStreaming = true  // Whether the loaded model supports streaming

    // SDK reference removed - use RunAnywhere static methods directly
    private let conversationStore = ConversationStore.shared
    private var generationTask: Task<Void, Never>?
    @Published var currentConversation: Conversation?
    private var lifecycleCancellable: AnyCancellable?

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "ChatViewModel")

    var canSend: Bool {
        !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating && isModelLoaded
    }

    init() {
        // Always start with a new conversation for a fresh chat experience
        let conversation = conversationStore.createConversation()
        currentConversation = conversation
        messages = [] // Start with empty messages array

        // Subscribe to model lifecycle changes from SDK
        subscribeToModelLifecycle()

        // Add system message only if model is already loaded
        if isModelLoaded {
            addSystemMessage()
        }

        // Listen for model loaded notifications (legacy support)
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

    /// Subscribe to SDK events for real-time model state updates
    private func subscribeToModelLifecycle() {
        // Subscribe to LLM events via EventBus
        lifecycleCancellable = RunAnywhere.events.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self = self else { return }
                self.handleSDKEvent(event)
            }

        // Check initial state from SDK
        Task {
            await checkModelStatusFromSDK()
        }
    }

    // MARK: - Performance Metrics from SDK Events

    /// Tracks time-to-first-token for the current generation (keyed by generationId)
    private var firstTokenLatencies: [String: Double] = [:]

    /// Tracks generation completion metrics (keyed by generationId)
    private var generationMetrics: [String: GenerationMetricsFromSDK] = [:]

    /// Performance metrics captured from SDK events
    struct GenerationMetricsFromSDK {
        let generationId: String
        let modelId: String
        let inputTokens: Int
        let outputTokens: Int
        let durationMs: Double
        let tokensPerSecond: Double
        let timeToFirstTokenMs: Double?
    }

    /// Handle SDK events to update model state and capture performance metrics
    private func handleSDKEvent(_ event: any SDKEvent) {
        // Check for LLM model load/unload events
        if let llmEvent = event as? LLMEvent {
            switch llmEvent {
            case .modelLoadCompleted(let modelId, _, _):
                let wasLoaded = self.isModelLoaded
                self.isModelLoaded = true

                // Get the model info from the view model
                if let matchingModel = ModelListViewModel.shared.availableModels.first(where: { $0.id == modelId }) {
                    self.loadedModelName = matchingModel.name
                    self.selectedFramework = matchingModel.preferredFramework
                }

                // Add system message when model becomes loaded
                if !wasLoaded {
                    self.logger.info("✅ LLM model loaded via SDK event: \(self.loadedModelName ?? modelId)")
                    if self.messages.first?.role != .system {
                        self.addSystemMessage()
                    }
                }

            case .modelUnloaded(let modelId):
                self.logger.info("ℹ️ LLM model unloaded: \(modelId)")
                self.isModelLoaded = false
                self.loadedModelName = nil
                self.selectedFramework = nil

            case .modelLoadStarted(let modelId, _):
                self.logger.info("⏳ LLM model loading: \(modelId)")

            case .firstToken(let generationId, let latencyMs):
                // Capture time-to-first-token from SDK event
                self.firstTokenLatencies[generationId] = latencyMs
                self.logger.info("⚡ First token received: \(latencyMs)ms (generationId: \(generationId))")

            case .generationCompleted(let generationId, let modelId, let inputTokens, let outputTokens, let durationMs, let tokensPerSecond, _):
                // Capture generation metrics from SDK event
                let ttft = self.firstTokenLatencies[generationId]
                let metrics = GenerationMetricsFromSDK(
                    generationId: generationId,
                    modelId: modelId,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    durationMs: durationMs,
                    tokensPerSecond: tokensPerSecond,
                    timeToFirstTokenMs: ttft
                )
                self.generationMetrics[generationId] = metrics
                self.logger.info("📊 Generation completed via SDK event - Tokens: \(outputTokens), Speed: \(tokensPerSecond) tok/s, TTFT: \(ttft ?? 0)ms")

                // Clean up old entries (keep last 10)
                if self.firstTokenLatencies.count > 10 {
                    self.firstTokenLatencies.removeAll()
                }
                if self.generationMetrics.count > 10 {
                    self.generationMetrics.removeAll()
                }

            default:
                break
            }
        }
    }

    /// Get the latest generation metrics from SDK events for a given generationId
    func getMetricsFromSDKEvents(generationId: String) -> GenerationMetricsFromSDK? {
        return generationMetrics[generationId]
    }

    /// Check model status from SDK
    private func checkModelStatusFromSDK() async {
        let isLoaded = await RunAnywhere.isModelLoaded
        let modelId = await RunAnywhere.getCurrentModelId()

        await MainActor.run {
            self.isModelLoaded = isLoaded
            if let id = modelId,
               let matchingModel = ModelListViewModel.shared.availableModels.first(where: { $0.id == id }) {
                self.loadedModelName = matchingModel.name
                self.selectedFramework = matchingModel.preferredFramework
            }
            self.logger.info("📊 Initial LLM state: loaded=\(self.isModelLoaded), model=\(self.loadedModelName ?? "none")")
        }
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
                            try await RunAnywhere.loadModel(model.id)
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
                // Use settings from UserDefaults with fallback to 1000 tokens for chat
                let savedTemperature = UserDefaults.standard.double(forKey: "defaultTemperature")
                let savedMaxTokens = UserDefaults.standard.integer(forKey: "defaultMaxTokens")

                let effectiveSettings = (
                    temperature: savedTemperature != 0 ? savedTemperature : 0.7,
                    maxTokens: savedMaxTokens != 0 ? savedMaxTokens : 1000  // Default to 1000 tokens for chat
                )

                let options = LLMGenerationOptions(
                    maxTokens: effectiveSettings.maxTokens,
                    temperature: Float(effectiveSettings.temperature)
                )

                // Check if the model actually supports streaming
                // Some models (like Apple Foundation Models) don't support streaming
                let modelSupportsStreaming = await RunAnywhere.supportsLLMStreaming
                let effectiveUseStreaming = useStreaming && modelSupportsStreaming

                if !modelSupportsStreaming && useStreaming {
                    logger.info("⚠️ Model doesn't support streaming, falling back to non-streaming mode")
                }

                logger.info("📝 Generation options created, useStreaming: \(self.useStreaming), modelSupportsStreaming: \(modelSupportsStreaming), effectiveUseStreaming: \(effectiveUseStreaming)")

                if effectiveUseStreaming {
                    // Use streaming generation with SDK metrics tracking
                    var fullResponse = ""
                    var isInThinkingMode = false
                    var thinkingContent = ""
                    var responseContent = ""

                    logger.info("📤 Sending prompt to SDK.generateStream (with analytics)")
                    let streamingResult = try await RunAnywhere.generateStream(fullPrompt, options: options)
                    let stream = streamingResult.stream
                    let metricsTask = streamingResult.result

                    // Stream tokens as they arrive
                    for try await token in stream {
                        fullResponse += token

                        // SDK handles thinking content parsing automatically
                        // Display content is already cleaned by SDK
                        responseContent = fullResponse

                        // Update the assistant message with current content
                        await MainActor.run {
                            if messageIndex < self.messages.count {
                                let currentMessage = self.messages[messageIndex]
                                let updatedMessage = Message(
                                    id: currentMessage.id,
                                    role: currentMessage.role,
                                    content: responseContent,
                                    thinkingContent: nil, // SDK will provide this in final result
                                    timestamp: currentMessage.timestamp
                                )
                                self.messages[messageIndex] = updatedMessage

                                // Notify UI to scroll during streaming
                                NotificationCenter.default.post(name: Notification.Name("MessageContentUpdated"), object: nil)
                            }
                        }
                    }

                    logger.info("Streaming completed with response: \(fullResponse)")

                    // Get metrics from SDK
                    let sdkResult = try await metricsTask.value
                    logger.info("📊 SDK Metrics - Tokens: \(sdkResult.tokensUsed), Thinking: \(sdkResult.thinkingTokens ?? 0), Response: \(sdkResult.responseTokens)")
                    logger.info("⏱️ SDK Timing - Total: \(sdkResult.latencyMs)ms")
                    logger.info("🚀 SDK Performance - Speed: \(sdkResult.tokensPerSecond) tok/s")

                    // Update final message with SDK-provided thinking content
                    await MainActor.run {
                        if messageIndex < self.messages.count {
                            let currentMessage = self.messages[messageIndex]
                            let updatedMessage = Message(
                                id: currentMessage.id,
                                role: currentMessage.role,
                                content: sdkResult.text,
                                thinkingContent: sdkResult.thinkingContent,
                                timestamp: currentMessage.timestamp
                            )
                            self.messages[messageIndex] = updatedMessage
                        }
                    }

                    // Convert SDK metrics to app analytics using the existing helper
                    if let conversationId = currentConversation?.id,
                       messageIndex < messages.count {
                        let analytics = analyticsFromGenerationResult(
                            sdkResult,
                            messageId: messages[messageIndex].id.uuidString,
                            conversationId: conversationId,
                            startTime: Date(timeIntervalSinceNow: -(sdkResult.latencyMs / 1000)),
                            inputText: prompt,
                            wasInterrupted: false,
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
                    // Use non-streaming generation - SDK returns full metrics
                    let startTime = Date()
                    logger.info("🎯 Using non-streaming generation with SDK metrics")

                    let result = try await RunAnywhere.generate(fullPrompt, options: options)

                    logger.info("✅ Generation completed: \(result.text.prefix(100))...")
                    logger.info("📊 SDK Metrics - Tokens: \(result.tokensUsed), Thinking: \(result.thinkingTokens ?? 0), Response: \(result.responseTokens)")
                    logger.info("⏱️ SDK Timing - Total: \(result.latencyMs)ms")

                    // Update the assistant message with response from SDK
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

                    // Convert SDK metrics to app analytics
                    if let conversationId = currentConversation?.id,
                       messageIndex < messages.count {
                        let analytics = analyticsFromGenerationResult(
                            result,
                            messageId: messages[messageIndex].id.uuidString,
                            conversationId: conversationId,
                            startTime: startTime,
                            inputText: prompt,
                            wasInterrupted: false,
                            options: options
                        )

                        // Update message with analytics from SDK
                        await MainActor.run {
                            if let analytics = analytics, messageIndex < self.messages.count {
                                let currentMessage = self.messages[messageIndex]
                                let modelInfo = ModelListViewModel.shared.currentModel != nil ? MessageModelInfo(from: ModelListViewModel.shared.currentModel!) : nil

                                self.logger.info("📊 Using SDK analytics: tokens/sec = \(analytics.averageTokensPerSecond), time = \(analytics.totalGenerationTime)")

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

        // Also cancel at SDK level
        Task {
            await RunAnywhere.cancelGeneration()
        }
    }

    func loadModel(_ modelInfo: ModelInfo) async {
        do {
            try await RunAnywhere.loadModel(modelInfo.id)
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
                self.selectedFramework = currentModel.preferredFramework
                self.logger.info("✅ Model status updated: '\(currentModel.name)' is loaded with framework: \(currentModel.preferredFramework?.displayName ?? "unknown")")

                // Ensure the model is actually loaded in the SDK (but don't block the UI update)
                Task {
                    do {
                        try await RunAnywhere.loadModel(currentModel.id)
                        self.logger.info("✅ Verified model '\(currentModel.name)' is loaded in SDK")

                        // Check if model supports streaming
                        let supportsStreaming = await RunAnywhere.supportsLLMStreaming
                        await MainActor.run {
                            self.modelSupportsStreaming = supportsStreaming
                            self.logger.info("📡 Model streaming support: \(supportsStreaming)")
                        }
                    } catch {
                        self.logger.error("❌ Failed to verify model is loaded: \(error)")
                        await MainActor.run {
                            self.isModelLoaded = false
                            self.loadedModelName = nil
                            self.selectedFramework = nil
                        }
                    }
                }
            } else {
                self.isModelLoaded = false
                self.loadedModelName = nil
                self.selectedFramework = nil
                self.logger.info("❌ No current model in ModelListViewModel")
            }

            // Update system message to reflect current state
            if self.messages.first?.role == .system {
                self.messages.removeFirst()
            }
            if self.isModelLoaded {
                self.addSystemMessage()
            }
        }
    }

    @objc private func modelLoaded(_ notification: Notification) {
        Task {
            if let model = notification.object as? ModelInfo {
                // Check streaming support
                let supportsStreaming = await RunAnywhere.supportsLLMStreaming

                await MainActor.run {
                    self.isModelLoaded = true
                    self.loadedModelName = model.name
                    self.selectedFramework = model.preferredFramework
                    self.modelSupportsStreaming = supportsStreaming
                    self.logger.info("📡 Model '\(model.name)' streaming support: \(supportsStreaming)")

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
        // Settings are now passed per-request, not globally
        // Store in UserDefaults for persistence
        UserDefaults.standard.set(temperature, forKey: "defaultTemperature")
        UserDefaults.standard.set(maxTokens, forKey: "defaultMaxTokens")

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

    /// Convert SDK's LLMGenerationResult to MessageAnalytics (uses SDK metrics)
    private func analyticsFromGenerationResult(
        _ result: LLMGenerationResult,
        messageId: String,
        conversationId: String,
        startTime: Date,
        inputText: String,
        wasInterrupted: Bool = false,
        options: LLMGenerationOptions,
        generationId: String? = nil
    ) -> MessageAnalytics? {
        guard let modelName = loadedModelName,
              let currentModel = ModelListViewModel.shared.currentModel else {
            logger.warning("Cannot create analytics - no model info available")
            return nil
        }

        // SDK provides timing metrics (convert ms to seconds)
        let totalGenerationTime = result.latencyMs / 1000.0

        // Get time-to-first-token from SDK events if available
        var timeToFirstToken: TimeInterval? = nil
        if let genId = generationId, let ttftMs = firstTokenLatencies[genId] {
            timeToFirstToken = ttftMs / 1000.0
        }

        // SDK provides accurate token counts
        let inputTokens = RunAnywhere.estimateTokenCount(inputText) // Use SDK's token counter via RunAnywhere namespace
        let outputTokens = result.tokensUsed
        let thinkingTokens = result.thinkingTokens
        let responseTokens = result.responseTokens

        // SDK provides tokens per second
        let averageTokensPerSecond = result.tokensPerSecond

        // Determine completion status
        let completionStatus: MessageAnalytics.CompletionStatus = wasInterrupted ? .interrupted : .complete

        // Create generation parameters
        let generationParameters = MessageAnalytics.GenerationParameters(
            temperature: Double(options.temperature ?? 0.7),
            maxTokens: options.maxTokens ?? 10000,
            topP: nil,
            topK: nil
        )

        logger.info("📊 Creating analytics from SDK result and events:")
        logger.info("  - Total tokens: \(outputTokens) (thinking: \(thinkingTokens ?? 0), response: \(responseTokens))")
        logger.info("  - Timing: total=\(totalGenerationTime)s, TTFT=\(timeToFirstToken ?? 0)s")
        logger.info("  - Speed: \(averageTokensPerSecond) tok/s")

        return MessageAnalytics(
            messageId: messageId,
            conversationId: conversationId,
            modelId: currentModel.id,
            modelName: modelName,
            framework: result.framework?.rawValue ?? currentModel.compatibleFrameworks.first?.rawValue ?? "unknown",
            timestamp: startTime,
            timeToFirstToken: timeToFirstToken,
            totalGenerationTime: totalGenerationTime,
            thinkingTime: nil,
            responseTime: nil,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            thinkingTokens: thinkingTokens,
            responseTokens: responseTokens,
            averageTokensPerSecond: averageTokensPerSecond,
            messageLength: result.text.count,
            wasThinkingMode: result.thinkingContent != nil,
            wasInterrupted: wasInterrupted,
            retryCount: 0,
            completionStatus: completionStatus,
            tokensPerSecondHistory: [], // Not tracked in non-streaming
            generationMode: .nonStreaming,
            contextWindowUsage: 0.0,
            generationParameters: generationParameters
        )
    }

    // Note: collectMessageAnalytics removed - now using SDK metrics directly via analyticsFromGenerationResult

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
