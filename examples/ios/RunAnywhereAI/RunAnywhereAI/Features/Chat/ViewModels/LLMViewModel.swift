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
    private var firstTokenLatencies: [String: Double] = [:]
    private var generationMetrics: [String: GenerationMetricsFromSDK] = [:]
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
            name: Notification.Name("ConversationSelected"),
            object: nil
        )

        subscribeToModelLifecycle()

        // Reconcile against the SDK's authoritative model snapshot in case a
        // model was loaded before this ViewModel subscribed.
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

    /// Downloads a catalog adapter with URLSession, reports completion through
    /// commons, then applies the stable local path.
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
            await loadLoraAdapter(path: localPath, scale: scale)
        } catch {
            logger.error("Failed to load adapter \(adapter.id): \(error)")
            self.error = error
            isLoadingLoRA = false
        }
    }

    /// Copies a user-selected LoRA file into the sandbox before applying it. If
    /// the file matches a catalog entry, the import completion is persisted
    /// through the generated LoRA catalog ABI.
    func importAndLoadLoraAdapter(url: URL, scale: Float) async {
        isLoadingLoRA = true
        error = nil

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let destination = try copyImportedAdapterToSandbox(from: url)
            if let entry = availableAdapters.first(where: { catalogEntryMatches($0, fileURL: url) }) {
                var request = RALoraAdapterDownloadCompletedRequest()
                request.adapterID = entry.id
                request.localPath = destination.path
                request.imported = true
                request.completedAtUnixMs = currentUnixMilliseconds()
                request.statusMessage = "import completed"
                if let fileSize = try fileSize(at: destination) {
                    request.sizeBytes = fileSize
                }

                let result = try await RunAnywhere.lora.markImportCompleted(request)
                guard result.success else {
                    throw LLMError.custom(
                        result.errorMessage.isEmpty
                            ? "LoRA adapter import completion was not persisted"
                            : result.errorMessage
                    )
                }
                updateAvailableAdapter(result.entry)
            }

            isLoadingLoRA = false
            await loadLoraAdapter(path: destination.path, scale: scale)
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
        guard let sourceURL = URL(string: adapter.url), sourceURL.scheme != nil else {
            throw LLMError.custom("LoRA catalog adapter has an invalid download URL")
        }

        let directory = Self.loraDownloadDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(Self.loraFilename(for: adapter), isDirectory: false)

        let (temporaryURL, response) = try await URLSession.shared.download(from: sourceURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw LLMError.custom("LoRA adapter download failed with HTTP \(httpResponse.statusCode)")
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)

        var request = RALoraAdapterDownloadCompletedRequest()
        request.adapterID = adapter.id
        request.localPath = destination.path
        request.completedAtUnixMs = currentUnixMilliseconds()
        request.imported = false
        request.statusMessage = "download completed"
        if let fileSize = try fileSize(at: destination) {
            request.sizeBytes = fileSize
        }

        let result = try await RunAnywhere.lora.markDownloadCompleted(request)
        guard result.success else {
            throw LLMError.custom(
                result.errorMessage.isEmpty
                    ? "LoRA adapter download completion was not persisted"
                    : result.errorMessage
            )
        }
        return result.entry
    }

    private func copyImportedAdapterToSandbox(from url: URL) throws -> URL {
        let directory = Self.loraDownloadDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(url.lastPathComponent, isDirectory: false)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    private func updateAvailableAdapter(_ entry: RALoraAdapterCatalogEntry) {
        if let index = availableAdapters.firstIndex(where: { $0.id == entry.id }) {
            availableAdapters[index] = entry
        } else {
            availableAdapters.append(entry)
        }
    }

    private func catalogEntryMatches(_ entry: RALoraAdapterCatalogEntry, fileURL: URL) -> Bool {
        let filename = fileURL.lastPathComponent
        return entry.filename == filename || entry.localPath == fileURL.path
    }

    private func fileSize(at url: URL) throws -> Int64? {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value
    }

    private func currentUnixMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }

    static func loraDownloadDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("LoRA", isDirectory: true)
    }

    private static func loraFilename(for adapter: RALoraAdapterCatalogEntry) -> String {
        if !adapter.filename.isEmpty {
            return adapter.filename
        }
        if let filename = URL(string: adapter.url)?.lastPathComponent, !filename.isEmpty {
            return filename
        }
        return "\(adapter.id).gguf"
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

    /// Thin pass-through to the app's `ThinkingContentParser.strip(from:)` so the
    /// app has a single source of truth for `<think>` tag handling on raw
    /// streaming-token text (the proto `RALLMGenerationResult` carries thinking
    /// fields separately on the non-streaming path).
    static func stripThinkTags(from text: String) -> String {
        ThinkingContentParser.strip(from: text)
    }
}
// swiftlint:enable type_body_length
