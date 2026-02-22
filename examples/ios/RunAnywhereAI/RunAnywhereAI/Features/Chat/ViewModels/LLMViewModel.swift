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

    // MARK: - LoRA Adapter State

    private(set) var loraAdapters: [LoRAAdapterInfo] = []
    private(set) var isLoadingLoRA = false

    // MARK: - LoRA Adapter Download State
    // TODO: [Portal Integration] Remove demo adapter download state once portal delivers adapters OTA.

    private(set) var availableDemoAdapters: [DemoLoRAAdapter] = []
    private(set) var adapterDownloadProgress: [String: Double] = [:]
    private(set) var downloadedAdapterPaths: [String: String] = [:]
    private(set) var isDownloadingAdapter: [String: Bool] = [:]

    // MARK: - User Settings

    var currentInput = ""
    var useStreaming = true
    var useToolCalling: Bool {
        get { ToolSettingsViewModel.shared.toolCallingEnabled }
        set { ToolSettingsViewModel.shared.toolCallingEnabled = newValue }
    }

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
        // Don't create conversation yet - wait until first message is sent
        currentConversation = nil

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

        // Create conversation on first message
        if currentConversation == nil {
            let conversation = conversationStore.createConversation()
            currentConversation = conversation
        }

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
        // Check if tool calling is enabled and we have registered tools
        let registeredTools = await RunAnywhere.getRegisteredTools()
        let shouldUseToolCalling = useToolCalling && !registeredTools.isEmpty

        if shouldUseToolCalling {
            logger.info("Using tool calling with \(registeredTools.count) registered tools")
            try await generateWithToolCalling(prompt: prompt, options: options, messageIndex: messageIndex)
            return
        }

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

    // MARK: - LoRA Adapter Management

    func loadLoraAdapter(path: String, scale: Float) async {
        isLoadingLoRA = true
        error = nil
        do {
            try await RunAnywhere.loadLoraAdapter(LoRAAdapterConfig(path: path, scale: scale))
            await refreshLoraAdapters()
            logger.info("LoRA adapter loaded: \(path) (scale=\(scale))")
        } catch {
            logger.error("Failed to load LoRA adapter: \(error)")
            self.error = error
        }
        isLoadingLoRA = false
    }

    func removeLoraAdapter(path: String) async {
        do {
            try await RunAnywhere.removeLoraAdapter(path)
            await refreshLoraAdapters()
        } catch {
            logger.error("Failed to remove LoRA adapter: \(error)")
            self.error = error
        }
    }

    func clearLoraAdapters() async {
        do {
            try await RunAnywhere.clearLoraAdapters()
            loraAdapters = []
        } catch {
            logger.error("Failed to clear LoRA adapters: \(error)")
            self.error = error
        }
    }

    func refreshLoraAdapters() async {
        do {
            loraAdapters = try await RunAnywhere.getLoadedLoraAdapters()
        } catch {
            logger.error("Failed to refresh LoRA adapters: \(error)")
        }
    }

    // MARK: - Demo LoRA Adapter Download
    // TODO: [Portal Integration] Remove demo adapter download logic once portal delivers adapters OTA.

    /// Refreshes the list of available demo adapters for the currently loaded model.
    func refreshAvailableDemoAdapters() {
        guard let modelId = ModelListViewModel.shared.currentModel?.id else {
            availableDemoAdapters = []
            return
        }
        availableDemoAdapters = DemoLoRAAdapterCatalog.adapters(forModelId: modelId)
        syncDownloadedAdapterPaths()
    }

    /// Checks if a demo adapter's file already exists on disk.
    func isAdapterDownloaded(_ adapter: DemoLoRAAdapter) -> Bool {
        downloadedAdapterPaths[adapter.id] != nil
    }

    /// Returns the local file path for a downloaded adapter, or nil.
    func localPath(for adapter: DemoLoRAAdapter) -> String? {
        downloadedAdapterPaths[adapter.id]
    }

    /// Downloads a demo adapter from its URL, then loads it.
    func downloadAndLoadAdapter(_ adapter: DemoLoRAAdapter, scale: Float) async {
        guard isDownloadingAdapter[adapter.id] != true else { return }

        isDownloadingAdapter[adapter.id] = true
        adapterDownloadProgress[adapter.id] = 0.0
        error = nil

        do {
            let localPath: String
            if let existing = downloadedAdapterPaths[adapter.id] {
                localPath = existing
            } else {
                localPath = try await downloadAdapter(adapter)
            }
            await loadLoraAdapter(path: localPath, scale: scale)
        } catch {
            logger.error("Failed to download/load adapter \(adapter.id): \(error)")
            self.error = error
        }

        isDownloadingAdapter[adapter.id] = false
        adapterDownloadProgress[adapter.id] = nil
    }

    /// Downloads the adapter file to the LoRA directory.
    private func downloadAdapter(_ adapter: DemoLoRAAdapter) async throws -> String {
        let loraDir = Self.loraDownloadDirectory()
        try FileManager.default.createDirectory(at: loraDir, withIntermediateDirectories: true)
        let destinationURL = loraDir.appendingPathComponent(adapter.fileName)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            downloadedAdapterPaths[adapter.id] = destinationURL.path
            return destinationURL.path
        }

        let delegate = DownloadProgressDelegate { [weak self] progress in
            Task { @MainActor in
                self?.adapterDownloadProgress[adapter.id] = progress
            }
        }

        let (tempURL, _) = try await URLSession.shared.download(from: adapter.downloadURL, delegate: delegate)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)

        downloadedAdapterPaths[adapter.id] = destinationURL.path
        logger.info("Adapter downloaded to \(destinationURL.path)")
        return destinationURL.path
    }

    /// Scans the LoRA directory to populate downloadedAdapterPaths.
    private func syncDownloadedAdapterPaths() {
        let loraDir = Self.loraDownloadDirectory()
        for adapter in availableDemoAdapters {
            let path = loraDir.appendingPathComponent(adapter.fileName).path
            if FileManager.default.fileExists(atPath: path) {
                downloadedAdapterPaths[adapter.id] = path
            }
        }
    }

    static func loraDownloadDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("LoRA", isDirectory: true)
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
        let savedSystemPrompt = UserDefaults.standard.string(forKey: "defaultSystemPrompt")

        let effectiveSettings = (
            temperature: savedTemperature != 0 ? savedTemperature : Self.defaultTemperatureValue,
            maxTokens: savedMaxTokens != 0 ? savedMaxTokens : Self.defaultMaxTokensValue
        )

        let effectiveSystemPrompt = (savedSystemPrompt?.isEmpty == false) ? savedSystemPrompt : nil

    let systemPromptInfo: String = {
        guard let prompt = effectiveSystemPrompt else { return "nil" }
        return "set(\(prompt.count) chars)"
    }()

    logger.info(
        "[PARAMS] App getGenerationOptions: temperature=\(effectiveSettings.temperature), maxTokens=\(effectiveSettings.maxTokens), systemPrompt=\(systemPromptInfo)"
    )

    return LLMGenerationOptions(
        maxTokens: effectiveSettings.maxTokens,
        temperature: Float(effectiveSettings.temperature),
        systemPrompt: effectiveSystemPrompt
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

        let savedSystemPrompt = UserDefaults.standard.string(forKey: "defaultSystemPrompt")

        UserDefaults.standard.set(temperature, forKey: "defaultTemperature")
        UserDefaults.standard.set(maxTokens, forKey: "defaultMaxTokens")

        logger.info("Settings applied - Temperature: \(temperature), MaxTokens: \(maxTokens), SystemPrompt: \(savedSystemPrompt ?? "nil")")
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
                    self.refreshAvailableDemoAdapters()
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
