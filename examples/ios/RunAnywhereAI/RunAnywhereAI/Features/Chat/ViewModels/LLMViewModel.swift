//
//  LLMViewModel.swift
//  RunAnywhereAI
//
//  Clean ViewModel for LLM chat functionality following MVVM pattern
//  All business logic for LLM inference, model management, and chat state
//

// swiftlint:disable type_body_length

import Foundation
import SwiftUI
import RunAnywhere
import Combine
import os.log

// MARK: - LLM View Model

@MainActor
@Observable
final class LLMViewModel {
    // MARK: - Constants

    private static let defaultMaxTokens = 1000
    private static let defaultTemperature = 0.7

    // MARK: - Published State

    private(set) var messages: [Message] = []
    private(set) var isGenerating = false
    private(set) var error: Error?
    private(set) var isModelLoaded = false
    private(set) var loadedModelName: String?
    private(set) var selectedFramework: InferenceFramework?
    private(set) var modelSupportsStreaming = true
    private(set) var currentConversation: Conversation?

    // MARK: - User Settings

    var currentInput = ""
    var useStreaming = true

    // MARK: - Dependencies

    private let conversationStore = ConversationStore.shared
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "LLMViewModel")

    // MARK: - Private State

    private var generationTask: Task<Void, Never>?
    private var lifecycleCancellable: AnyCancellable?
    private var firstTokenLatencies: [String: Double] = [:]
    private var generationMetrics: [String: GenerationMetricsFromSDK] = [:]

    // MARK: - Computed Properties

    var canSend: Bool {
        !currentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isGenerating
        && isModelLoaded
    }

    // MARK: - Initialization

    init() {
        // Create new conversation
        let conversation = conversationStore.createConversation()
        currentConversation = conversation

        // Listen for model loaded notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modelLoaded(_:)),
            name: Notification.Name("ModelLoaded"),
            object: nil
        )

        // Listen for conversation selection
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(conversationSelected(_:)),
            name: Notification.Name("ConversationSelected"),
            object: nil
        )

        // Defer state-modifying operations to avoid "Publishing changes within view updates" warning
        // These are deferred because init() may be called during view body evaluation
        Task { @MainActor in
            // Small delay to ensure view is fully initialized
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

            // Subscribe to SDK events
            self.subscribeToModelLifecycle()

            // Add system message if model is already loaded
            if self.isModelLoaded {
                self.addSystemMessage()
            }

            // Ensure settings are applied
            await self.ensureSettingsAreApplied()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public Methods

    func sendMessage() async {
        logger.info("Sending message")

        guard canSend else {
            logger.error("Cannot send - validation failed")
            return
        }

        let prompt = currentInput
        currentInput = ""
        isGenerating = true
        error = nil

        // Add user message
        let userMessage = Message(role: .user, content: prompt)
        messages.append(userMessage)

        if let conversation = currentConversation {
            conversationStore.addMessage(userMessage, to: conversation)
        }

        // Create placeholder assistant message
        let assistantMessage = Message(role: .assistant, content: "")
        messages.append(assistantMessage)
        let messageIndex = messages.count - 1

        generationTask = Task {
            do {
                // Ensure model is loaded
                try await ensureModelIsLoaded()

                // Get generation options
                let options = getGenerationOptions()

                // Check streaming support
                let modelSupportsStreaming = await RunAnywhere.supportsLLMStreaming
                let effectiveUseStreaming = useStreaming && modelSupportsStreaming

                if !modelSupportsStreaming && useStreaming {
                    logger.info("Model doesn't support streaming, using non-streaming mode")
                }

                // Generate response
                if effectiveUseStreaming {
                    try await generateStreamingResponse(
                        prompt: prompt,
                        options: options,
                        messageIndex: messageIndex
                    )
                } else {
                    try await generateNonStreamingResponse(
                        prompt: prompt,
                        options: options,
                        messageIndex: messageIndex
                    )
                }

            } catch {
                await handleGenerationError(error, at: messageIndex)
            }

            await finalizeGeneration(at: messageIndex)
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

        if isModelLoaded {
            addSystemMessage()
        }
    }

    func stopGeneration() {
        generationTask?.cancel()
        isGenerating = false

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

                // Update system message
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
        let modelListViewModel = ModelListViewModel.shared

        await MainActor.run {
            if let currentModel = modelListViewModel.currentModel {
                self.isModelLoaded = true
                self.loadedModelName = currentModel.name
                self.selectedFramework = currentModel.preferredFramework

                Task {
                    do {
                        try await RunAnywhere.loadModel(currentModel.id)

                        let supportsStreaming = await RunAnywhere.supportsLLMStreaming
                        await MainActor.run {
                            self.modelSupportsStreaming = supportsStreaming
                        }
                    } catch {
                        logger.error("Failed to verify model is loaded: \(error)")
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
            }

            // Update system message
            if self.messages.first?.role == .system {
                self.messages.removeFirst()
            }
            if self.isModelLoaded {
                self.addSystemMessage()
            }
        }
    }

    func loadConversation(_ conversation: Conversation) {
        currentConversation = conversation

        if conversation.messages.isEmpty {
            messages = []
            if isModelLoaded {
                addSystemMessage()
            }
        } else {
            messages = conversation.messages

            let analyticsCount = messages.compactMap { $0.analytics }.count
            logger.info("Loaded conversation with \(self.messages.count) messages, \(analyticsCount) have analytics")
        }

        if let modelName = conversation.modelName {
            loadedModelName = modelName
        }
    }

    func createNewConversation() {
        clearChat()
    }

    // MARK: - Private Methods - Model Lifecycle

    private func subscribeToModelLifecycle() {
        lifecycleCancellable = RunAnywhere.events.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self = self else { return }
                // Defer state modifications to avoid "Publishing changes within view updates" warning
                Task { @MainActor in
                    self.handleSDKEvent(event)
                }
            }

        Task { @MainActor in
            // Small delay to ensure view is fully initialized before state changes
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            await checkModelStatusFromSDK()
        }
    }

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
        }
    }

    private func handleSDKEvent(_ event: any SDKEvent) {
        guard let llmEvent = event as? LLMEvent else { return }

        switch llmEvent {
        case .modelLoadCompleted(let modelId, _, _, _):
            let wasLoaded = self.isModelLoaded
            self.isModelLoaded = true

            if let matchingModel = ModelListViewModel.shared.availableModels.first(where: { $0.id == modelId }) {
                self.loadedModelName = matchingModel.name
                self.selectedFramework = matchingModel.preferredFramework
            }

            if !wasLoaded {
                logger.info("LLM model loaded: \(self.loadedModelName ?? modelId)")
                if self.messages.first?.role != .system {
                    self.addSystemMessage()
                }
            }

        case .modelUnloaded(let modelId):
            logger.info("LLM model unloaded: \(modelId)")
            self.isModelLoaded = false
            self.loadedModelName = nil
            self.selectedFramework = nil

        case .modelLoadStarted(let modelId, _, _):
            logger.info("LLM model loading: \(modelId)")

        case .firstToken(let generationId, _, let timeToFirstTokenMs, _):
            self.firstTokenLatencies[generationId] = timeToFirstTokenMs
            logger.info("First token: \(timeToFirstTokenMs)ms")

        case .generationCompleted(let generationId, let modelId, let inputTokens, let outputTokens, let durationMs, let tokensPerSecond, _, _, _, _, _, _):
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

            // Cleanup old entries
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

    // MARK: - Private Methods - Message Generation

    private func ensureModelIsLoaded() async throws {
        if !isModelLoaded {
            throw LLMError.noModelLoaded
        }

        // Verify model is actually loaded in SDK
        if let model = ModelListViewModel.shared.currentModel {
            try await RunAnywhere.loadModel(model.id)
        }
    }

    private func getGenerationOptions() -> LLMGenerationOptions {
        let savedTemperature = UserDefaults.standard.double(forKey: "defaultTemperature")
        let savedMaxTokens = UserDefaults.standard.integer(forKey: "defaultMaxTokens")

        let effectiveSettings = (
            temperature: savedTemperature != 0 ? savedTemperature : Self.defaultTemperature,
            maxTokens: savedMaxTokens != 0 ? savedMaxTokens : Self.defaultMaxTokens
        )

        return LLMGenerationOptions(
            maxTokens: effectiveSettings.maxTokens,
            temperature: Float(effectiveSettings.temperature)
        )
    }

    private func generateStreamingResponse(
        prompt: String,
        options: LLMGenerationOptions,
        messageIndex: Int
    ) async throws {
        var fullResponse = ""

        let streamingResult = try await RunAnywhere.generateStream(prompt, options: options)
        let stream = streamingResult.stream
        let metricsTask = streamingResult.result

        // Stream tokens
        for try await token in stream {
            fullResponse += token

            await updateMessageContent(at: messageIndex, content: fullResponse)

            // Notify UI to scroll
            NotificationCenter.default.post(
                name: Notification.Name("MessageContentUpdated"),
                object: nil
            )
        }

        // Get final metrics from SDK
        let sdkResult = try await metricsTask.value
        logger.info("SDK Metrics - Tokens: \(sdkResult.tokensUsed), Speed: \(sdkResult.tokensPerSecond) tok/s")

        // Update final message with thinking content
        await updateMessageWithResult(
            at: messageIndex,
            result: sdkResult,
            prompt: prompt,
            options: options,
            wasInterrupted: false
        )
    }

    private func generateNonStreamingResponse(
        prompt: String,
        options: LLMGenerationOptions,
        messageIndex: Int
    ) async throws {
        let startTime = Date()
        let result = try await RunAnywhere.generate(prompt, options: options)

        logger.info("Generation completed: \(result.text.prefix(100))...")
        logger.info("SDK Metrics - Tokens: \(result.tokensUsed), Speed: \(result.tokensPerSecond) tok/s")

        // Update message with result
        await updateMessageWithResult(
            at: messageIndex,
            result: result,
            prompt: prompt,
            options: options,
            wasInterrupted: false
        )
    }

    private func updateMessageContent(at index: Int, content: String) async {
        await MainActor.run {
            guard index < self.messages.count else { return }

            let currentMessage = self.messages[index]
            let updatedMessage = Message(
                id: currentMessage.id,
                role: currentMessage.role,
                content: content,
                thinkingContent: currentMessage.thinkingContent,
                timestamp: currentMessage.timestamp
            )
            self.messages[index] = updatedMessage
        }
    }

    private func updateMessageWithResult(
        at index: Int,
        result: LLMGenerationResult,
        prompt: String,
        options: LLMGenerationOptions,
        wasInterrupted: Bool
    ) async {
        await MainActor.run {
            guard index < self.messages.count,
                  let conversationId = self.currentConversation?.id else { return }

            let currentMessage = self.messages[index]

            // Create analytics
            let analytics = self.createAnalytics(
                from: result,
                messageId: currentMessage.id.uuidString,
                conversationId: conversationId,
                wasInterrupted: wasInterrupted,
                options: options
            )

            let modelInfo = ModelListViewModel.shared.currentModel != nil
                ? MessageModelInfo(from: ModelListViewModel.shared.currentModel!)
                : nil

            // Update message
            let updatedMessage = Message(
                id: currentMessage.id,
                role: currentMessage.role,
                content: result.text,
                thinkingContent: result.thinkingContent,
                timestamp: currentMessage.timestamp,
                analytics: analytics,
                modelInfo: modelInfo
            )
            self.messages[index] = updatedMessage

            // Update conversation analytics
            self.updateConversationAnalytics()
        }
    }

    private func handleGenerationError(_ error: Error, at index: Int) async {
        logger.error("Generation failed: \(error)")

        await MainActor.run {
            self.error = error

            if index < self.messages.count {
                let errorMessage: String
                if error is LLMError {
                    errorMessage = error.localizedDescription
                } else {
                    errorMessage = "Generation failed: \(error.localizedDescription)"
                }

                let currentMessage = self.messages[index]
                let updatedMessage = Message(
                    id: currentMessage.id,
                    role: currentMessage.role,
                    content: errorMessage,
                    timestamp: currentMessage.timestamp
                )
                self.messages[index] = updatedMessage
            }
        }
    }

    private func finalizeGeneration(at index: Int) async {
        await MainActor.run {
            self.isGenerating = false

            if index < self.messages.count,
               let conversation = self.currentConversation {
                var updatedConversation = conversation
                updatedConversation.messages = self.messages
                updatedConversation.modelName = self.loadedModelName

                let analyticsCount = self.messages.compactMap { $0.analytics }.count
                logger.info("Saving conversation with \(self.messages.count) messages, \(analyticsCount) have analytics")

                self.conversationStore.updateConversation(updatedConversation)
            }
        }
    }

    // MARK: - Private Methods - Analytics

    private func createAnalytics(
        from result: LLMGenerationResult,
        messageId: String,
        conversationId: String,
        wasInterrupted: Bool,
        options: LLMGenerationOptions
    ) -> MessageAnalytics? {
        guard let modelName = loadedModelName,
              let currentModel = ModelListViewModel.shared.currentModel else {
            logger.warning("Cannot create analytics - no model info available")
            return nil
        }

        let totalGenerationTime = result.latencyMs / 1000.0
        let inputTokens = result.inputTokens
        let outputTokens = result.tokensUsed
        let thinkingTokens = result.thinkingTokens
        let responseTokens = result.responseTokens
        let averageTokensPerSecond = result.tokensPerSecond
        let completionStatus: MessageAnalytics.CompletionStatus = wasInterrupted ? .interrupted : .complete

        let generationParameters = MessageAnalytics.GenerationParameters(
            temperature: Double(options.temperature ?? Float(Self.defaultTemperature)),
            maxTokens: options.maxTokens ?? Self.defaultMaxTokens,
            topP: nil,
            topK: nil
        )

        return MessageAnalytics(
            messageId: messageId,
            conversationId: conversationId,
            modelId: currentModel.id,
            modelName: modelName,
            framework: result.framework ?? currentModel.compatibleFrameworks.first?.rawValue ?? "unknown",
            timestamp: Date(),
            timeToFirstToken: nil,
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
            tokensPerSecondHistory: [],
            generationMode: .nonStreaming,
            contextWindowUsage: 0.0,
            generationParameters: generationParameters
        )
    }

    private func updateConversationAnalytics() {
        guard let conversation = currentConversation else { return }

        let analyticsMessages = messages.compactMap { $0.analytics }

        guard !analyticsMessages.isEmpty else { return }

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

        var updatedConversation = conversation
        updatedConversation.analytics = conversationAnalytics
        updatedConversation.performanceSummary = PerformanceSummary(from: messages)
        conversationStore.updateConversation(updatedConversation)
    }

    // MARK: - Private Methods - Helpers

    private func addSystemMessage() {
        guard isModelLoaded, let modelName = loadedModelName else { return }

        let content = "Model '\(modelName)' is loaded and ready to chat!"
        let systemMessage = Message(role: .system, content: content)
        messages.insert(systemMessage, at: 0)

        if var conversation = currentConversation {
            conversation.messages = messages
            conversationStore.updateConversation(conversation)
        }
    }

    private func ensureSettingsAreApplied() async {
        let savedTemperature = UserDefaults.standard.double(forKey: "defaultTemperature")
        let temperature = savedTemperature != 0 ? savedTemperature : Self.defaultTemperature

        let savedMaxTokens = UserDefaults.standard.integer(forKey: "defaultMaxTokens")
        let maxTokens = savedMaxTokens != 0 ? savedMaxTokens : Self.defaultMaxTokens

        UserDefaults.standard.set(temperature, forKey: "defaultTemperature")
        UserDefaults.standard.set(maxTokens, forKey: "defaultMaxTokens")

        logger.info("Settings applied - Temperature: \(temperature), MaxTokens: \(maxTokens)")
    }

    @objc private func modelLoaded(_ notification: Notification) {
        Task {
            if let model = notification.object as? ModelInfo {
                let supportsStreaming = await RunAnywhere.supportsLLMStreaming

                await MainActor.run {
                    self.isModelLoaded = true
                    self.loadedModelName = model.name
                    self.selectedFramework = model.preferredFramework
                    self.modelSupportsStreaming = supportsStreaming

                    if self.messages.first?.role == .system {
                        self.messages.removeFirst()
                    }
                    self.addSystemMessage()
                }
            } else {
                await self.checkModelStatus()
            }
        }
    }

    @objc private func conversationSelected(_ notification: Notification) {
        if let conversation = notification.object as? Conversation {
            loadConversation(conversation)
        }
    }
}

// MARK: - Supporting Types

enum LLMError: LocalizedError {
    case noModelLoaded

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            return "No model is loaded. Please select and load a model from the Models tab first."
        }
    }
}

struct GenerationMetricsFromSDK: Sendable {
    let generationId: String
    let modelId: String
    let inputTokens: Int
    let outputTokens: Int
    let durationMs: Double
    let tokensPerSecond: Double
    let timeToFirstTokenMs: Double?
}
