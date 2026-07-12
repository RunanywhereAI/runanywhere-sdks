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

// swiftlint:disable type_body_length
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
    private(set) var loadedModelSupportsThinking = false
    private(set) var selectedFramework: InferenceFramework?
    private(set) var modelSupportsStreaming = true
    private(set) var currentConversation: Conversation?

    // MARK: - LoRA Adapter State

    private(set) var loraAdapters: [RALoRAAdapterInfo] = []
    private(set) var isLoadingLoRA = false

    // MARK: - LoRA Adapter Catalog State

    private(set) var availableAdapters: [RALoraAdapterCatalogEntry] = []

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
    var generationCancellable: AnyCancellable?
    private var firstTokenLatencies: [String: Double] = [:]
    private var generationMetrics: [String: GenerationMetricsFromSDK] = [:]
    var preparedDocumentRAGPipelineKey: ChatDocumentRAGPipelineKey?
    /// TTFT (ms) reported by the SDK event bus for the generation in flight.
    /// The event carries an SDK-side generation id the app never sees on the
    /// result, so the single-generation-at-a-time chat keeps the latest value
    /// and merges it into the persisted `MessageAnalytics`.
    private(set) var activeGenerationTTFTMs: Double?
    private var isViewModelInitialized = false

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

    func setLoadedModelSupportsThinking(_ value: Bool) {
        loadedModelSupportsThinking = value
    }

    func clearLoadedModelInfo() {
        loadedModelName = nil
        loadedModelSupportsThinking = false
        selectedFramework = nil
    }

    func recordFirstTokenLatency(generationId: String, latency: Double) {
        firstTokenLatencies[generationId] = latency
        activeGenerationTTFTMs = latency
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
        // Sync model state immediately from shared state to avoid the race condition
        // where the model was loaded before this ViewModel was created.
        if let currentModel = ModelListViewModel.shared.currentModel {
            isModelLoaded = true
            loadedModelName = currentModel.name
            loadedModelSupportsThinking = currentModel.supportsThinking
            selectedFramework = currentModel.framework
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Subscribes to SDK events and applies initial settings.
    /// Idempotent — safe to call from View's `.task { }`.
    func initialize() async {
        guard !isViewModelInitialized else { return }
        isViewModelInitialized = true

        // Conversation selection is purely intra-app state with no SDK event
        // counterpart, so it stays on NotificationCenter. Model lifecycle flows
        // through the SDK event bus (subscribeToModelLifecycle) instead.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(conversationSelected(_:)),
            name: .conversationSelected,
            object: nil
        )

        subscribeToModelLifecycle()

        // Reconcile against the SDK's authoritative model snapshot in case a
        // model was loaded before this ViewModel subscribed.
        await checkModelStatusFromSDK()
        await ModelListViewModel.shared.loadDefaultChatModelIfAvailable()
        await checkModelStatusFromSDK()

        if isModelLoaded {
            addSystemMessage()
        }

        await ensureSettingsAreApplied()
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
        activeGenerationTTFTMs = nil

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

        // Append an empty assistant message slot that streaming tokens are written into.
        let assistantMessage = Message(role: .assistant, content: "")
        messages.append(assistantMessage)

        return (prompt, messages.count - 1)
    }

    private func executeGeneration(prompt: String, messageIndex: Int) async {
        do {
            try await ensureModelIsLoaded()

            let options = getGenerationOptions()
            // Send the raw user prompt and let C++ apply_chat_template handle
            // formatting via the model's embedded GGUF template. The system
            // prompt is passed separately in options so the C++ layer can
            // place it correctly.
            let effectiveOptions = options
            try await performGeneration(prompt: prompt, options: effectiveOptions, messageIndex: messageIndex)
        } catch {
            await handleGenerationError(error, at: messageIndex)
        }

        await finalizeGeneration(at: messageIndex)
    }

    private func performGeneration(
        prompt: String,
        options: RALLMGenerationOptions,
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

        // All LLM backends now handle streaming via the canonical generateStream
        // entry point; the SDK no longer exposes a per-model capability flag.
        if useStreaming {
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
            var config = RALoRAAdapterConfig()
            config.adapterPath = path
            config.scale = scale
            var request = RALoRAApplyRequest()
            request.adapters = [config]
            let result = try await RunAnywhere.lora.apply(request)
            guard result.success else {
                throw LLMError.custom(result.errorMessage)
            }
            loraAdapters = result.adapters
            logger.info("LoRA adapter loaded: \(path) (scale=\(scale))")
        } catch {
            logger.error("Failed to load LoRA adapter: \(error)")
            self.error = error
        }
        isLoadingLoRA = false
    }

    func loadCatalogLoraAdapter(
        _ adapter: RALoraAdapterCatalogEntry,
        localPath: String? = nil,
        scale: Float
    ) async {
        isLoadingLoRA = true
        error = nil
        do {
            let result = try await RunAnywhere.lora.applyCatalogAdapter(
                adapter,
                localPath: localPath,
                scale: scale
            )
            guard result.success else {
                throw LLMError.custom(result.errorMessage)
            }
            loraAdapters = result.adapters
            logger.info("LoRA catalog adapter loaded: \(adapter.id) (scale=\(scale))")
        } catch {
            logger.error("Failed to load LoRA catalog adapter: \(error)")
            self.error = error
        }
        isLoadingLoRA = false
    }

    func removeLoraAdapter(path: String) async {
        do {
            var request = RALoRARemoveRequest()
            request.adapterPaths = [path]
            let state = try await RunAnywhere.lora.remove(request)
            try handleLoraState(state)
        } catch {
            logger.error("Failed to remove LoRA adapter: \(error)")
            self.error = error
        }
    }

    func clearLoraAdapters() async {
        do {
            var request = RALoRARemoveRequest()
            request.clearAll_p = true
            let state = try await RunAnywhere.lora.remove(request)
            try handleLoraState(state)
        } catch {
            logger.error("Failed to clear LoRA adapters: \(error)")
            self.error = error
        }
    }

    func refreshLoraAdapters() async {
        do {
            let state = try await RunAnywhere.lora.list()
            try handleLoraState(state)
        } catch {
            logger.error("Failed to refresh LoRA adapters: \(error)")
        }
    }

    private func handleLoraState(_ state: RALoRAState) throws {
        if state.hasErrorMessage, !state.errorMessage.isEmpty {
            throw LLMError.custom(state.errorMessage)
        }
        loraAdapters = state.loadedAdapters
    }

    // MARK: - LoRA Adapter Catalog & Download

    /// Refreshes the list of available adapters for the currently loaded model from the SDK registry.
    func refreshAvailableAdapters() async {
        guard let modelId = ModelListViewModel.shared.currentModel?.id else {
            availableAdapters = []
            return
        }
        do {
            var query = RALoraAdapterCatalogQuery()
            query.modelID = modelId
            let result = try await RunAnywhere.lora.queryCatalog(query)
            guard result.success else {
                throw LLMError.custom(
                    result.errorMessage.isEmpty ? "LoRA catalog query failed" : result.errorMessage
                )
            }
            availableAdapters = result.entries
        } catch {
            logger.error("Failed to refresh LoRA catalog: \(error)")
            self.error = error
            availableAdapters = []
        }
    }

    func isAdapterDownloaded(_ adapter: RALoraAdapterCatalogEntry) -> Bool {
        localPath(for: adapter) != nil
    }

    func localPath(for adapter: RALoraAdapterCatalogEntry) -> String? {
        guard adapter.isDownloaded, adapter.hasLocalPath, !adapter.localPath.isEmpty else {
            return nil
        }
        return FileManager.default.fileExists(atPath: adapter.localPath) ? adapter.localPath : nil
    }

    /// Downloads a catalog adapter through the SDK's canonical download
    /// pipeline, then applies the stable local path.
    func downloadAndLoadAdapter(_ adapter: RALoraAdapterCatalogEntry, scale: Float) async {
        isLoadingLoRA = true
        error = nil

        do {
            let entry = try await ensureCatalogAdapterDownloaded(adapter)
            updateAvailableAdapter(entry)
            guard let localPath = localPath(for: entry) else {
                throw LLMError.custom("LoRA adapter completion did not return a usable local path")
            }
            isLoadingLoRA = false
            await loadCatalogLoraAdapter(entry, localPath: localPath, scale: scale)
        } catch {
            logger.error("Failed to load adapter \(adapter.id): \(error)")
            self.error = error
            isLoadingLoRA = false
        }
    }

    /// Imports a user-selected LoRA file through the SDK (sandbox access,
    /// on-disk placement, and catalog completion are SDK-owned), then applies it.
    func importAndLoadLoraAdapter(url: URL, scale: Float) async {
        isLoadingLoRA = true
        error = nil

        do {
            let imported = try await RunAnywhere.lora.importAdapter(from: url)
            if imported.matched, imported.hasEntry {
                updateAvailableAdapter(imported.entry)
                isLoadingLoRA = false
                await loadCatalogLoraAdapter(imported.entry, localPath: imported.localPath, scale: scale)
            } else {
                isLoadingLoRA = false
                await loadLoraAdapter(path: imported.localPath, scale: scale)
            }
        } catch {
            logger.error("Failed to import LoRA adapter: \(error)")
            self.error = error
            isLoadingLoRA = false
        }
    }

    private func ensureCatalogAdapterDownloaded(
        _ adapter: RALoraAdapterCatalogEntry
    ) async throws -> RALoraAdapterCatalogEntry {
        if let localPath = localPath(for: adapter) {
            var entry = adapter
            entry.localPath = localPath
            entry.isDownloaded = true
            return entry
        }

        guard !adapter.id.isEmpty else {
            throw LLMError.custom("LoRA catalog adapter id is required")
        }

        // One SDK call owns everything: artifact registration, transfer with
        // resume/checksum/progress, on-disk placement, and catalog completion.
        let localPath = try await RunAnywhere.lora.download(adapter)

        var entry = adapter
        entry.localPath = localPath
        entry.isDownloaded = true
        return entry
    }

    private func updateAvailableAdapter(_ entry: RALoraAdapterCatalogEntry) {
        if let index = availableAdapters.firstIndex(where: { $0.id == entry.id }) {
            availableAdapters[index] = entry
        } else {
            availableAdapters.append(entry)
        }
    }

    // MARK: - Private Methods - Message Generation

    private func ensureModelIsLoaded() async throws {
        if !isModelLoaded {
            throw LLMError.noModelLoaded
        }
    }

    private func getGenerationOptions() -> RALLMGenerationOptions {
        // Use object(forKey:) to distinguish an unset key (nil) from a value explicitly set to 0.0
        let savedTemperature = UserDefaults.standard.object(forKey: "defaultTemperature") as? Double
        let savedMaxTokens = UserDefaults.standard.integer(forKey: "defaultMaxTokens")
        let savedSystemPrompt = UserDefaults.standard.string(forKey: "defaultSystemPrompt")
        let thinkingModeEnabled = SettingsViewModel.shared.thinkingModeEnabled

        let effectiveSettings = (
            temperature: savedTemperature ?? Self.defaultTemperatureValue,
            maxTokens: savedMaxTokens != 0 ? savedMaxTokens : Self.defaultMaxTokensValue
        )

        let effectiveSystemPrompt = (savedSystemPrompt?.isEmpty == false) ? savedSystemPrompt : nil

        let systemPromptInfo: String = {
            guard let prompt = effectiveSystemPrompt else { return "nil" }
            return "set(\(prompt.count) chars)"
        }()

        logger.info(
            """
            [PARAMS] App getGenerationOptions: \
            temperature=\(effectiveSettings.temperature), \
            maxTokens=\(effectiveSettings.maxTokens), \
            thinkingMode=\(thinkingModeEnabled), \
            systemPrompt=\(systemPromptInfo)
            """
        )

        var options = RALLMGenerationOptions.defaults()
        options.maxTokens = Int32(effectiveSettings.maxTokens)
        options.temperature = Float(effectiveSettings.temperature)
        if let effectiveSystemPrompt {
            options.systemPrompt = effectiveSystemPrompt
        }
        options.streamingEnabled = useStreaming
        // Structured flag — commons applies the model's no-think directive;
        // the app never injects control tokens into prompts. Chat document
        // attachments use the same gate before calling the SDK RAG pipeline.
        options.disableThinking = loadedModelSupportsThinking && !thinkingModeEnabled
        if let currentModel = ModelListViewModel.shared.currentModel, currentModel.supportsThinking {
            options.thinkingPattern = currentModel.hasThinkingPattern
                ? currentModel.thinkingPattern
                : .defaultPattern
        } else if loadedModelSupportsThinking {
            options.thinkingPattern = .defaultPattern
        }
        return options
    }

    // MARK: - Internal Methods - Helpers

    func addSystemMessage() {
        // Model loaded notification is now shown as a toast instead
        // No need to add a system message to the chat
    }

    private func ensureSettingsAreApplied() async {
        let savedTemperature = UserDefaults.standard.object(forKey: "defaultTemperature") as? Double
        let temperature = savedTemperature ?? Self.defaultTemperatureValue

        let savedMaxTokens = UserDefaults.standard.integer(forKey: "defaultMaxTokens")
        let maxTokens = savedMaxTokens != 0 ? savedMaxTokens : Self.defaultMaxTokensValue

        let savedSystemPrompt = UserDefaults.standard.string(forKey: "defaultSystemPrompt")

        UserDefaults.standard.set(temperature, forKey: "defaultTemperature")
        UserDefaults.standard.set(maxTokens, forKey: "defaultMaxTokens")

        logger.info(
            """
            Settings applied - Temperature: \(temperature), \
            MaxTokens: \(maxTokens), \
            SystemPrompt: \(savedSystemPrompt ?? "nil")
            """
        )
    }

    @objc
    private func conversationSelected(_ notification: Notification) {
        if let conversation = notification.object as? Conversation {
            loadConversation(conversation)
        }
    }

}
// swiftlint:enable type_body_length
