//
//  LLMViewModel.swift
//  RunAnywhereAI
//
//  Clean ViewModel for LLM chat functionality following MVVM pattern
//  All business logic for LLM inference, model management, and chat state
//

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

    static let defaultMaxTokensValue = 1000
    static let defaultTemperatureValue = 0.7

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

    let conversationStore = ConversationStore.shared
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "LLMViewModel")

    // MARK: - Private State

    private var generationTask: Task<Void, Never>?
    var lifecycleCancellable: AnyCancellable?
    private var firstTokenLatencies: [String: Double] = [:]
    private var generationMetrics: [String: GenerationMetricsFromSDK] = [:]

    // MARK: - Internal Accessors for Extensions

    var isModelLoadedValue: Bool { isModelLoaded }
    var messagesValue: [Message] { messages }

    func updateModelLoadedState(isLoaded: Bool) {
        isModelLoaded = isLoaded
    }

    func updateLoadedModelInfo(name: String, framework: InferenceFramework) {
        loadedModelName = name
        selectedFramework = framework
    }

    func clearLoadedModelInfo() {
        loadedModelName = nil
        selectedFramework = nil
    }

    func recordFirstTokenLatency(generationId: String, latency: Double) {
        firstTokenLatencies[generationId] = latency
    }

    func getFirstTokenLatency(for generationId: String) -> Double? {
        firstTokenLatencies[generationId]
    }

    func recordGenerationMetrics(generationId: String, metrics: GenerationMetricsFromSDK) {
        generationMetrics[generationId] = metrics
    }

    func cleanupOldMetricsIfNeeded() {
        if firstTokenLatencies.count > 10 {
            firstTokenLatencies.removeAll()
        }
        if generationMetrics.count > 10 {
            generationMetrics.removeAll()
        }
    }

    func updateMessage(at index: Int, with message: Message) {
        messages[index] = message
    }

    func setIsGenerating(_ value: Bool) {
        isGenerating = value
    }

    func clearMessages() {
        messages = []
    }

    func setMessages(_ newMessages: [Message]) {
        messages = newMessages
    }

    func removeFirstMessage() {
        if !messages.isEmpty {
            messages.removeFirst()
        }
    }

    func setLoadedModelName(_ name: String) {
        loadedModelName = name
    }

    func setCurrentConversation(_ conversation: Conversation) {
        currentConversation = conversation
    }

    func setError(_ err: Error?) {
        error = err
    }

    func setModelSupportsStreaming(_ value: Bool) {
        modelSupportsStreaming = value
    }

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

        let (prompt, messageIndex) = prepareMessagesForSending()
        generationTask = Task {
            await executeGeneration(prompt: prompt, messageIndex: messageIndex)
        }
    }

    private func prepareMessagesForSending() -> (prompt: String, messageIndex: Int) {
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

        return (prompt, messages.count - 1)
    }

    private func executeGeneration(prompt: String, messageIndex: Int) async {
        do {
            try await ensureModelIsLoaded()
            let options = getGenerationOptions()
            try await performGeneration(prompt: prompt, options: options, messageIndex: messageIndex)
        } catch {
            await handleGenerationError(error, at: messageIndex)
        }

        await finalizeGeneration(at: messageIndex)
    }

    private func performGeneration(
        prompt: String,
        options: LLMGenerationOptions,
        messageIndex: Int
    ) async throws {
        let modelSupportsStreaming = await RunAnywhere.supportsLLMStreaming
        let effectiveUseStreaming = useStreaming && modelSupportsStreaming

        if !modelSupportsStreaming && useStreaming {
            logger.info("Model doesn't support streaming, using non-streaming mode")
        }

        if effectiveUseStreaming {
            try await generateStreamingResponse(prompt: prompt, options: options, messageIndex: messageIndex)
        } else {
            try await generateNonStreamingResponse(prompt: prompt, options: options, messageIndex: messageIndex)
        }
    }

    func clearChat() {
        generationTask?.cancel()
        
        // Generate smart title for the old conversation before creating new one
        if let oldConversation = currentConversation,
           oldConversation.messages.count >= 2 {
            let conversationId = oldConversation.id
            Task { @MainActor in
                await self.conversationStore.generateSmartTitleForConversation(conversationId)
            }
        }
        
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

    func createNewConversation() {
        clearChat()
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
            temperature: savedTemperature != 0 ? savedTemperature : Self.defaultTemperatureValue,
            maxTokens: savedMaxTokens != 0 ? savedMaxTokens : Self.defaultMaxTokensValue
        )

        return LLMGenerationOptions(
            maxTokens: effectiveSettings.maxTokens,
            temperature: Float(effectiveSettings.temperature)
        )
    }

    // MARK: - Internal Methods - Helpers

    func addSystemMessage() {
        // Model loaded notification is now shown as a toast instead
        // No need to add a system message to the chat
    }

    private func ensureSettingsAreApplied() async {
        let savedTemperature = UserDefaults.standard.double(forKey: "defaultTemperature")
        let temperature = savedTemperature != 0 ? savedTemperature : Self.defaultTemperatureValue

        let savedMaxTokens = UserDefaults.standard.integer(forKey: "defaultMaxTokens")
        let maxTokens = savedMaxTokens != 0 ? savedMaxTokens : Self.defaultMaxTokensValue

        UserDefaults.standard.set(temperature, forKey: "defaultTemperature")
        UserDefaults.standard.set(maxTokens, forKey: "defaultMaxTokens")

        logger.info("Settings applied - Temperature: \(temperature), MaxTokens: \(maxTokens)")
    }

    @objc
    private func modelLoaded(_ notification: Notification) {
        Task {
            if let model = notification.object as? ModelInfo {
                let supportsStreaming = await RunAnywhere.supportsLLMStreaming

                await MainActor.run {
                    self.isModelLoaded = true
                    self.loadedModelName = model.name
                    self.selectedFramework = model.framework
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

    @objc
    private func conversationSelected(_ notification: Notification) {
        if let conversation = notification.object as? Conversation {
            loadConversation(conversation)
        }
    }
}
