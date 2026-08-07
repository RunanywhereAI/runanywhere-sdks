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
    private(set) var isUsingConnect = false
    private(set) var connectedHostName: String?
    private(set) var currentConversation: Conversation?

    // MARK: - LoRA Adapter State

    private(set) var loraAdapters: [RALoraAdapterInfo] = []
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
    /// Keeps the header's copy of the chat's name in step with the store's.
    var storedTitleCancellable: AnyCancellable?
    private var firstTokenLatencies: [String: Double] = [:]
    private var generationMetrics: [String: GenerationMetricsFromSDK] = [:]
    var preparedDocumentRAGPipelineKey: ChatDocumentRAGPipelineKey?
    /// RAG session backing the chat's document questions. Held open across turns
    /// for the same document/model triple and closed before a new one opens.
    var documentRAGSession: RagSession?
    /// When the turn in flight was started, so its duration is measured rather
    /// than reconstructed. `GenerationResult` reports throughput and a token
    /// count but no elapsed time, and dividing one by the other gives 0.0s on
    /// any backend that does not count tokens — which is what the Apple
    /// Foundation Models path does (`platform_llm_vtable_generate_stream` emits
    /// the whole reply as one token and reports `completion_tokens = 0`).
    private(set) var generationStartedAt: Date?
    /// TTFT (ms) reported by the SDK event bus for the generation in flight.
    /// The event carries an SDK-side generation id the app never sees on the
    /// result, so the single-generation-at-a-time chat keeps the latest value
    /// and merges it into the persisted `MessageAnalytics`.
    private(set) var activeGenerationTTFTMs: Double?
    private var isViewModelInitialized = false
    #if os(iOS)
    /// Tracks the in-flight hosted request so Stop can cancel by id.
    /// Written from generation helpers in `LLMViewModel+Generation` (other file),
    /// so this cannot use `private(set)` — that setter is file-private in Swift.
    var activeHostedRequestID: String?
    #endif

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

    #if os(iOS)
    /// Hosted Connect model identity used for message analytics when no local
    /// `ModelListViewModel.currentModel` is loaded (Android already builds
    /// `GenerationStats` from the Connect model descriptor).
    private(set) var activeConnectModelId: String?
    private(set) var activeConnectFramework: String?

    func activateConnectModel(_ model: ConnectModel, hostName: String) {
        isUsingConnect = true
        connectedHostName = hostName
        updateModelLoadedState(isLoaded: true)
        loadedModelName = model.displayName
        activeConnectModelId = model.id
        activeConnectFramework = model.framework
        loadedModelSupportsThinking = false
        selectedFramework = nil
        setModelSupportsStreaming(model.supportsStreaming)
        updateSystemMessageAfterModelLoad()
    }

    func deactivateConnectModel() async {
        guard isUsingConnect else { return }
        isUsingConnect = false
        connectedHostName = nil
        activeConnectModelId = nil
        activeConnectFramework = nil
        await checkModelStatusFromSDK()
        updateSystemMessageAfterModelLoad()
    }
    #endif

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
        // Cancelling the consuming task terminates the SDK stream, which forwards
        // the cancellation to the native layer.
        generationTask?.cancel()
        activeGenerationID = nil
        generatingConversationId = nil
        setIsGenerating(false)
        #if os(iOS)
        if isUsingConnect, let requestID = activeHostedRequestID {
            ConnectClientController.shared.session.cancelGeneration(requestID: requestID)
            activeHostedRequestID = nil
        }
        #endif
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

    /// Take a new name for the open chat without touching anything else on it.
    /// See `subscribeToStoredTitle` for why the whole conversation is not
    /// adopted instead.
    func adoptStoredTitle(_ title: String) {
        guard var conversation = currentConversation, conversation.title != title else { return }
        conversation.title = title
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

    /// `Error` is not `Equatable`, so a view cannot `.onChange(of: error)`. This
    /// gives the UI something it can observe, which is what lets the chat report
    /// failures the moment they happen instead of polling after a fixed delay.
    var errorDescription: String? {
        error?.localizedDescription
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

        // Deletion is a broadcast: `ConversationStore` cannot know which view
        // models are looking at the row it just removed, so this one stays on
        // NotificationCenter. Selection does not — the sidebar (Mac) and the
        // drawer (iOS) call `loadConversation` directly, which is traceable and
        // typed. Model lifecycle flows through the SDK event bus
        // (`subscribeToModelLifecycle`) instead.
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

    /// The prologue every turn shares: clear the last error, claim the chat, and
    /// mint this generation's identity.
    ///
    /// Extracted so a regenerated turn (`LLMViewModel+MessageActions`) claims the
    /// chat through exactly the same path as a typed one. Two copies of this
    /// drifted in every previous chat app in this repo: one forgot to reset
    /// `activeGenerationTTFTMs`, so the second reply reported the first's TTFT.
    func beginGeneration() {
        // The previous turn's epilogue may still be asking the model to name the
        // chat. One LLM component serves one generation, and the user's turn
        // outranks a sidebar label, so take it back before claiming the chat.
        conversationStore.cancelPendingTitleGeneration()

        isGenerating = true
        error = nil
        activeGenerationTTFTMs = nil
        generationStartedAt = Date()

        // Create conversation on first message
        if currentConversation == nil {
            let conversation = conversationStore.createConversation()
            currentConversation = conversation
        }

        // Pin this generation to its conversation (drops stale writes on switch)
        // and give it an identity (lets a superseded finalize no-op).
        generatingConversationId = currentConversation?.id
        activeGenerationID = UUID()
    }

    private func prepareMessagesForSending() -> (prompt: String, messageIndex: Int) {
        let prompt = currentInput
        currentInput = ""
        beginGeneration()

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

    /// Internal, not private: `LLMViewModel+MessageActions` re-enters this exact
    /// path to regenerate a reply, so a regenerated turn goes through the same
    /// preflight, tool routing, error handling, and finalization as a typed one.
    func executeGeneration(prompt: String, messageIndex: Int, generationID: UUID?) async {
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
        options: LlmOptions,
        messageIndex: Int,
        generationID: UUID?
    ) async throws {
        // Check if tool calling is enabled and we have registered tools.
        let registeredTools = await RunAnywhere.llm.tools.list()
        let toolsRequested = useToolCalling && !isUsingConnect && !registeredTools.isEmpty
        let pf = ToolCallingModelPolicy.preflight(
            toolsRequested: toolsRequested,
            registeredToolCount: registeredTools.count,
            model: ModelListViewModel.shared.currentModel
        )

        switch pf.route {
        case .toolGeneration:
            logger.info("Using tool calling with \(registeredTools.count) registered tools")
            try await generateWithToolCalling(
                prompt: prompt,
                options: options,
                messageIndex: messageIndex,
                generationID: generationID
            )
            return
        case .blocked:
            // Tools were requested but the model can't support them; log why and
            // fall through to standard generation so the user still gets a reply.
            logger.info("Tool calling blocked: \(pf.availability.message ?? "model not compatible")")
        case .standardGeneration:
            break
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
        // Cancel cooperatively, but do NOT flip `isGenerating` here: cancellation
        // is async, so the in-flight generation keeps unwinding. Its own
        // `finalizeGeneration` owns the true->false transition, which keeps
        // `canSend` false until the stream has actually stopped — otherwise a
        // second `sendMessage()` could start and overlap the still-running
        // generation on the single-callback LLM component.
        generationTask?.cancel()

        #if os(iOS)
        if isUsingConnect, let requestID = activeHostedRequestID {
            ConnectClientController.shared.session.cancelGeneration(requestID: requestID)
        }
        #endif
    }

    func createNewConversation() {
        clearChat()
    }

    // MARK: - LoRA Adapter Management

    func loadLoraAdapter(path: String, scale: Float) async {
        isLoadingLoRA = true
        error = nil
        do {
            var config = RALoraAdapterConfig()
            config.adapterPath = path
            config.scale = scale
            var request = RALoraApplyRequest()
            request.adapters = [config]
            let result = try await RunAnywhere.lora.apply(request)
            guard !result.hasError else {
                throw LLMError.custom(result.error.message)
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
            guard !result.hasError else {
                throw LLMError.custom(result.error.message)
            }
            loraAdapters = result.adapters
            logger.info("LoRA catalog adapter loaded: \(adapter.id) (scale=\(scale))")
        } catch {
            logger.error("Failed to load LoRA catalog adapter: \(error)")
            self.error = error
        }
        isLoadingLoRA = false
    }

    /// `RALoraRemoveRequest.adapterPaths` was deleted outright
    /// (idl/lora_options.proto): removal is by catalog adapter id, or
    /// `clearAll_p`, only now. A loose adapter applied straight from a file
    /// path (no catalog id) can only be removed individually when it is the
    /// sole loaded adapter, via `clearAll_p` -- the SDK no longer exposes a
    /// path-keyed removal for that case when other adapters are also loaded.
    func removeLoraAdapter(path: String) async {
        do {
            let target = loraAdapters.first { $0.adapterPath == path }
            var request = RALoraRemoveRequest()
            if let adapterID = target?.adapterID, !adapterID.isEmpty {
                request.adapterIds = [adapterID]
            } else if loraAdapters.count <= 1 {
                request.clearAll_p = true
            } else {
                throw LLMError.custom(
                    "Can't remove this adapter individually: it has no catalog id and other adapters are also loaded."
                )
            }
            let state = try await RunAnywhere.lora.remove(request)
            try handleLoraState(state)
        } catch {
            logger.error("Failed to remove LoRA adapter: \(error)")
            self.error = error
        }
    }

    func clearLoraAdapters() async {
        do {
            var request = RALoraRemoveRequest()
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
            // `lora.state()` rather than `lora.list()`: the adapter rows key on the
            // on-disk adapter path (remove, example prompts), which `LoraState`
            // does not carry.
            let state = try await RunAnywhere.lora.state()
            try handleLoraState(state)
        } catch {
            logger.error("Failed to refresh LoRA adapters: \(error)")
        }
    }

    private func handleLoraState(_ state: RALoraState) throws {
        if state.hasError, !state.error.message.isEmpty {
            throw LLMError.custom(state.error.message)
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
            guard !result.hasError else {
                throw LLMError.custom(
                    result.error.message.isEmpty ? "LoRA catalog query failed" : result.error.message
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
        // `RALoraAdapterCatalogEntry.isDownloaded` was deleted outright
        // (idl/lora_options.proto); a non-empty `localPath` is the single
        // definition of "downloaded" now.
        guard adapter.hasLocalPath, !adapter.localPath.isEmpty else {
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
    ///
    /// `importAdapter(from:)` no longer auto-matches the import against an
    /// existing catalog entry (idl/lora_options.proto,
    /// lora-delete-download-import-bookkeeping): it returns a plain
    /// `RAModelImportResult`, not a catalog-entry match. A caller that knows
    /// which catalog adapter this file corresponds to would call
    /// `register(_:)`/`registerArtifact(_:)` itself; a user-picked file from
    /// the document picker has no such known catalog id, so it is always
    /// applied as a loose adapter path.
    func importAndLoadLoraAdapter(url: URL, scale: Float) async {
        isLoadingLoRA = true
        error = nil

        do {
            let imported = try await RunAnywhere.lora.importAdapter(from: url)
            isLoadingLoRA = false
            await loadLoraAdapter(path: imported.localPath, scale: scale)
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
            return entry
        }

        guard !adapter.id.isEmpty else {
            throw LLMError.custom("LoRA catalog adapter id is required")
        }

        // `RALoraAdapterCatalogEntry` no longer carries url/filename/size
        // (idl/lora_options.proto), so the downloadable bytes are described
        // by the companion `RAModelInfo` artifact registered at bootstrap
        // time under the SDK's `lora-adapter:{id}` convention
        // (`ModelCatalogBootstrap.registerLoraAdapters()`).
        guard let artifact = await RunAnywhere.models.get(id: adapter.loraArtifactModelID) else {
            throw LLMError.custom("LoRA adapter '\(adapter.id)' has no registered download artifact")
        }

        // One SDK call owns everything: artifact registration, transfer with
        // resume/checksum/progress, on-disk placement, and catalog completion.
        let localPath = try await RunAnywhere.lora.download(adapter, artifact: artifact)

        var entry = adapter
        entry.localPath = localPath
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

    private func getGenerationOptions() -> LlmOptions {
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

        var options = LlmOptions()
        options.maxOutputTokens = effectiveSettings.maxTokens
        options.temperature = Float(effectiveSettings.temperature)
        options.systemPrompt = effectiveSystemPrompt
        // Structured reasoning control — commons applies the model's no-think
        // directive; the app never injects control tokens into prompts. Chat
        // document attachments use the same gate before calling the SDK RAG
        // pipeline. Thought tokens only reach the UI when includeInOutput is set.
        // `pattern` stays nil so the SDK uses the loaded model's own thinking tags.
        var reasoning = ReasoningOptions()
        if loadedModelSupportsThinking && !thinkingModeEnabled {
            reasoning.mode = .off
        }
        reasoning.includeInOutput = thinkingModeEnabled
        options.reasoning = reasoning
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
