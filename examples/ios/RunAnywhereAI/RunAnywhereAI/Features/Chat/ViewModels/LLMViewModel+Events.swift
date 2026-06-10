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
        lifecycleCancellable = RunAnywhere.events.modelLifecycle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self = self else { return }
                Task { @MainActor in
                    self.handleModelLifecycle(change)
                }
            }

        // Generation analytics (TTFT, completion metrics) are chat-screen
        // analytics, not lifecycle — they stay on the raw event bus.
        generationCancellable = RunAnywhere.events.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self = self else { return }
                Task { @MainActor in
                    self.handleGenerationEvent(event)
                }
            }
    }

    func checkModelStatusFromSDK() async {
        // Resolve currently-loaded LLM via canonical proto snapshot API.
        var request = RACurrentModelRequest()
        request.category = .language
        let snapshot = RunAnywhere.currentModel(request)
        let isLoaded = snapshot.found
        let modelId = snapshot.found ? snapshot.modelID : nil

        await MainActor.run {
            self.updateModelLoadedState(isLoaded: isLoaded)
            if let id = modelId,
               let matchingModel = ModelListViewModel.shared.availableModels.first(where: { $0.id == id }) {
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

    /// Decode generation-analytics signals (TTFT, completion metrics) from
    /// the raw event bus.
    private func handleGenerationEvent(_ event: RASDKEvent) {
        guard event.category == .llm || event.component == .llm else { return }

        let modelId = event.model.modelID.isEmpty ? event.generation.modelID : event.model.modelID
        let generationId = event.generation.sessionID.isEmpty ? event.operationID : event.generation.sessionID

        switch event.generation.kind {
        case .firstTokenGenerated:
            let ttft = Double(event.generation.firstTokenLatencyMs)
            handleFirstToken(generationId: generationId, timeToFirstTokenMs: ttft)

        case .completed, .streamCompleted:
            let outputTokens = Int(event.generation.tokensUsed)
            let durationMs = Double(event.generation.latencyMs)
            let tps = durationMs > 0 && outputTokens > 0
                ? Double(outputTokens) / (durationMs / 1000.0)
                : 0
            handleGenerationCompleted(
                generationId: generationId,
                modelId: modelId,
                inputTokens: Int(event.generation.inputTokens),
                outputTokens: outputTokens,
                durationMs: durationMs,
                tokensPerSecond: tps
            )

        default:
            break
        }
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

    func handleFirstToken(generationId: String, timeToFirstTokenMs: Double) {
        recordFirstTokenLatency(generationId: generationId, latency: timeToFirstTokenMs)
    }

    // swiftlint:disable:next function_parameter_count
    func handleGenerationCompleted(
        generationId: String,
        modelId: String,
        inputTokens: Int,
        outputTokens: Int,
        durationMs: Double,
        tokensPerSecond: Double
    ) {
        let ttft = getFirstTokenLatency(for: generationId)
        let metrics = GenerationMetricsFromSDK(
            generationId: generationId,
            modelId: modelId,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            durationMs: durationMs,
            tokensPerSecond: tokensPerSecond,
            timeToFirstTokenMs: ttft
        )
        recordGenerationMetrics(generationId: generationId, metrics: metrics)
        cleanupOldMetricsIfNeeded()
    }
}
