//
//  LLMViewModel+Events.swift
//  RunAnywhereAI
//
//  Event handling functionality for LLMViewModel
//

import Foundation
import Combine
import RunAnywhere

extension LLMViewModel {
    // MARK: - Model Lifecycle Subscription

    /// Subscribe to the SDK event bus for model lifecycle and generation
    /// signals. The bus is the single source of truth — there is no parallel
    /// NotificationCenter channel.
    func subscribeToModelLifecycle() {
        // Typed lifecycle stream: the SDK folds all native load/unload
        // channels into one publisher.
        lifecycleCancellable = RunAnywhere.eventBus.modelLifecycle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self = self else { return }
                Task { @MainActor in
                    self.handleModelLifecycle(change)
                }
            }

        // Generation analytics (TTFT, completion metrics) are chat-screen
        // analytics, not lifecycle — they stay on the raw event bus.
        generationCancellable = RunAnywhere.eventBus.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self = self else { return }
                Task { @MainActor in
                    self.handleGenerationEvent(event)
                }
            }

        subscribeToStoredTitle()
    }

    /// Follow the open chat's name in the store.
    ///
    /// The view model keeps its own `Conversation` copy, and the Mac window
    /// title, the iOS top bar, and the details sheet all read *that* copy. So a
    /// name written by anyone else — the model naming a new chat, or Rename… in
    /// the sidebar — landed in the sidebar row and the header kept the old one
    /// until the user switched chats and back.
    ///
    /// Only the title is adopted. Taking the whole stored conversation would
    /// also replace `messages`, and the store's copy is a turn behind while a
    /// reply is still streaming into the visible transcript.
    private func subscribeToStoredTitle() {
        storedTitleCancellable = conversationStore.$conversations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversations in
                guard let self,
                      let id = self.currentConversation?.id,
                      let stored = conversations.first(where: { $0.id == id }),
                      stored.title != self.currentConversation?.title else { return }
                self.adoptStoredTitle(stored.title)
            }
    }

    func checkModelStatusFromSDK() async {
        let loadedModelId = await RunAnywhere.models.state().loaded[.language]?.id

        await MainActor.run {
            self.updateModelLoadedState(isLoaded: loadedModelId != nil)
            if let loadedModelId,
               let matchingModel = ModelListViewModel.shared.availableModels.first(where: { $0.id == loadedModelId }) {
                self.updateLoadedModelInfo(name: matchingModel.name, framework: matchingModel.framework)
                self.setLoadedModelSupportsThinking(matchingModel.supportsThinking)
            }
        }
    }

    // MARK: - SDK Event Handling

    /// Apply a typed model load/unload change.
    private func handleModelLifecycle(_ change: RAModelLifecycleChange) {
        guard change.component == .llm || change.event.category == .llm else { return }

        switch change.kind {
        case .loaded:
            handleModelLoadCompleted(modelId: change.modelID)
        case .unloaded:
            handleModelUnloaded(modelId: change.modelID)
        }
    }

    /// Generation events no longer drive chat analytics — TTFT / tok/s come
    /// from GenerationResult via buildMessageAnalytics.
    private func handleGenerationEvent(_ event: RASDKEvent) {
        guard event.category == .llm || event.component == .llm else { return }
        _ = event
    }

    func handleModelLoadCompleted(modelId: String) {
        let wasLoaded = isModelLoadedValue
        updateModelLoadedState(isLoaded: true)
        // All LLM backends expose streaming via the canonical generateStream
        // entry; the SDK no longer publishes a per-model capability flag.
        setModelSupportsStreaming(true)

        if let matchingModel = ModelListViewModel.shared.availableModels.first(where: { $0.id == modelId }) {
            updateLoadedModelInfo(name: matchingModel.name, framework: matchingModel.framework)
            setLoadedModelSupportsThinking(matchingModel.supportsThinking)
        }

        if !wasLoaded {
            if messagesValue.first?.role != .system {
                addSystemMessage()
            }
            Task { await refreshAvailableAdapters() }
        }
    }

    func handleModelUnloaded(modelId: String) {
        updateModelLoadedState(isLoaded: false)
        clearLoadedModelInfo()
    }
}
