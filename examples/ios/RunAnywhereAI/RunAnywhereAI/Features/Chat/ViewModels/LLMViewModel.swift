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
    /// The conversation the in-flight generation is writing into. When the user
    /// switches or clears conversations mid-generation this stops matching
    /// `currentConversation`, so late streaming tokens, error writes, and
    /// finalization are dropped instead of corrupting the newly-selected
    /// conversation. `String?` to match `Conversation.id`.
    private(set) var generatingConversationId: String?
    /// Identity of the generation that currently owns the chat state. A
    /// superseded generation (user navigated away / cleared / started a new one)
    /// sees an id mismatch at finalize and no-ops — which lets
    /// `cancelActiveGeneration()` clear `isGenerating` eagerly (restoring the send
    /// control the instant the user leaves) without a stale finalize corrupting
    /// the newly-selected conversation.
    private(set) var activeGenerationID: UUID?
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
        // Drop writes from a generation the user has navigated away from. Every
        // in-memory message mutation during generation — streaming tokens, final
        // result, error text, vision, document, and tool-calling — funnels
        // through here, so this single guard prevents a stale generation from
        // corrupting the now-active conversation's messages.
        guard isActiveGenerationTarget else { return }
        guard index < messages.count else { return }
        messages[index] = message
    }

    func setIsGenerating(_ value: Bool) {
        isGenerating = value
    }

    /// True while the generation started for `generatingConversationId` still
    /// owns the visible chat. Every message write/persist consults this so a
    /// generation the user navigated away from cannot mutate or persist the
    /// now-active conversation. Strict match (a nil target is never active), so a
    /// cancelled generation's late tokens are also rejected.
    var isActiveGenerationTarget: Bool {
        generatingConversationId != nil && generatingConversationId == currentConversation?.id
    }

    /// True while `generationID` is still THE active generation. Write
    /// initiations consult this (generation identity — not just conversation
    /// identity) so a superseded, still-draining stream (e.g. a vision/RAG turn
    /// the user navigated away from, whose SDK stream isn't cancelled) cannot
    /// re-acquire the write path once a NEW generation re-pins the same visible
    /// conversation.
    func isCurrentGeneration(_ generationID: UUID?) -> Bool {
        generationID != nil && activeGenerationID == generationID
    }

    func setGeneratingConversationId(_ id: String?) {
        generatingConversationId = id
    }

    func setActiveGenerationID(_ id: UUID?) {
        activeGenerationID = id
    }

    /// Store the task backing the current turn so `stopGeneration()` /
    /// `cancelActiveGeneration()` can cancel image- and document-question turns,
    /// which run outside `sendMessage` (the text path assigns `generationTask`
    /// directly). Without this, Stop cancels a stale/nil task and the composer
    /// stays locked until the turn finishes on its own.
    func setGenerationTask(_ task: Task<Void, Never>?) {
        generationTask = task
    }

    /// Cancel the in-flight generation and detach it from the active conversation
    /// so its late token writes and finalization become no-ops. Shared by
    /// `clearChat()` and `loadConversation(_:)`.
    ///
    /// Invalidating `activeGenerationID` supersedes the running generation: its
    /// trailing `finalizeGeneration` sees an id mismatch and does nothing (no
    /// persist, no state change). Because it can no longer clobber anything, we
    /// clear `isGenerating` here immediately — restoring the send control the
    /// instant the user leaves — instead of waiting for the abandoned generation
    /// to unwind. `stopGeneration()` (same conversation, wants its partial
    /// persisted) deliberately leaves both untouched.
    func cancelActiveGeneration() {
        generationTask?.cancel()
        activeGenerationID = nil
        generatingConversationId = nil
        setIsGenerating(false)
        Task { await RunAnywhere.cancelGeneration() }
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

    /// Drop a trailing empty assistant slot left behind by a Stop that produced
    /// no text, so a cancelled turn with nothing to show doesn't leave an orphan
    /// bubble. No-op unless the last message is a blank assistant message.
    func removeTrailingEmptyAssistantMessage() {
        guard let last = messages.last,
              last.role == .assistant,
              last.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        messages.removeLast()
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(conversationDeleted(_:)),
            name: .conversationDeleted,
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
        let generationID = activeGenerationID
        generationTask = Task {
            await executeGeneration(prompt: prompt, messageIndex: messageIndex, generationID: generationID)
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

        // Pin this generation to its conversation (drops stale writes on switch)
        // and give it an identity (lets a superseded finalize no-op).
        generatingConversationId = currentConversation?.id
        activeGenerationID = UUID()

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

    private func executeGeneration(prompt: String, messageIndex: Int, generationID: UUID?) async {
        do {
            try await ensureModelIsLoaded()

            let options = getGenerationOptions()
            // Send the raw user prompt and let C++ apply_chat_template handle
            // formatting via the model's embedded GGUF template. The system
            // prompt is passed separately in options so the C++ layer can
            // place it correctly.
            let effectiveOptions = options
            try await performGeneration(
                prompt: prompt,
                options: effectiveOptions,
                messageIndex: messageIndex,
                generationID: generationID
            )
        } catch {
            // Drop the error write if this generation was superseded (user
            // navigated away and possibly started a new one) or if the user
            // pressed Stop: a cooperative cancellation is not a real failure, so it
            // must not raise an error banner or leave a "Generation failed:
            // cancelled" bubble (nor overwrite already-streamed partial text).
            // finalizeGeneration then drops the now-empty assistant slot; a partial
            // response keeps its text and is persisted.
            if isCurrentGeneration(generationID), !Task.isCancelled {
                await handleGenerationError(error, at: messageIndex)
            }
        }

        await finalizeGeneration(at: messageIndex, generationID: generationID)
    }

    private func performGeneration(
        prompt: String,
        options: RALLMGenerationOptions,
        messageIndex: Int,
        generationID: UUID?
    ) async throws {
        // Check if tool calling is enabled and we have registered tools
        let registeredTools = await RunAnywhere.getRegisteredTools()
        let shouldUseToolCalling = useToolCalling && !registeredTools.isEmpty

        if shouldUseToolCalling {
            logger.info("Using tool calling with \(registeredTools.count) registered tools")
            try await generateWithToolCalling(
                prompt: prompt, options: options, messageIndex: messageIndex, generationID: generationID
            )
            return
        }

        // All LLM backends now handle streaming via the canonical generateStream
        // entry point; the SDK no longer exposes a per-model capability flag.
        if useStreaming {
            try await generateStreamingResponse(
                prompt: prompt, options: options, messageIndex: messageIndex, generationID: generationID
            )
        } else {
            try await generateNonStreamingResponse(
                prompt: prompt, options: options, messageIndex: messageIndex, generationID: generationID
            )
        }
    }

    func clearChat() {
        cancelActiveGeneration()

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
        // `isGenerating` is intentionally NOT reset here: if a generation is
        // still unwinding, its own `finalizeGeneration` clears it (and drops its
        // now-stale persist). If none is running it is already false.
        error = nil

        // Create new conversation
        let conversation = conversationStore.createConversation()
        currentConversation = conversation

        if isModelLoaded {
            addSystemMessage()
        }
    }

    func stopGeneration() {
        // Cancel cooperatively and stop the SDK, but do NOT flip `isGenerating`
        // here: cancellation is async, so the in-flight generation keeps
        // unwinding. Its own `finalizeGeneration` owns the true->false
        // transition, which keeps `canSend` false until the stream has actually
        // stopped — otherwise a second `sendMessage()` could start and overlap
        // the still-running generation on the single-callback LLM component.
        generationTask?.cancel()

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

        var effectiveSystemPrompt = (savedSystemPrompt?.isEmpty == false) ? savedSystemPrompt : nil

        #if os(iOS)
        // The get_health_data tool surfaces real vitals (heart rate, SpO2,
        // resting heart rate, ...). Without guidance, a small on-device model
        // asked to comment on those numbers will readily improvise a medical
        // opinion. This instruction is appended (not swapped in) so it holds
        // even when the user has set their own custom system prompt.
        if ToolSettingsViewModel.shared.toolCallingEnabled, ToolSettingsViewModel.shared.healthToolEnabled {
            let healthSafetyInstructions = """
                You have access to the user's real Apple Health data via get_health_data. \
                Never provide a medical diagnosis, treatment recommendation, or interpret \
                vitals as indicating a health condition. If the user describes concerning \
                symptoms (e.g. chest pain, severe dizziness, fainting, difficulty breathing), \
                tell them to seek medical attention immediately instead of analyzing their \
                Health data for it. Present Health data factually and encourage consulting a \
                qualified healthcare professional for any medical concerns. Only state \
                numbers that literally appear in a get_health_data tool result — if a field \
                is missing, say the data isn't available rather than estimating a number.
                """
            effectiveSystemPrompt = [effectiveSystemPrompt, healthSafetyInstructions]
                .compactMap { $0 }
                .joined(separator: "\n\n")
        }
        #endif

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

    @objc
    private func conversationDeleted(_ notification: Notification) {
        guard let deletedId = notification.object as? String,
              currentConversation?.id == deletedId
                || generatingConversationId == deletedId else { return }
        // The chat the user is viewing/generating was deleted: stop any in-flight
        // generation (so its finalize can't persist) and move off the tombstoned
        // conversation so a later send starts a fresh chat instead of being
        // silently dropped by the store's tombstone guard.
        cancelActiveGeneration()
        if let replacement = conversationStore.currentConversation, replacement.id != deletedId {
            loadConversation(replacement)
        } else {
            messages.removeAll()
            currentInput = ""
            currentConversation = nil
        }
    }

}
// swiftlint:enable type_body_length
