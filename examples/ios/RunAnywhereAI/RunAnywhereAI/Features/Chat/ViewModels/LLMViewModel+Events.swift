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

    func subscribeToModelLifecycle() {
        lifecycleCancellable = RunAnywhere.events.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self = self else { return }
                Task { @MainActor in
                    self.handleSDKEvent(event)
                }
            }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            await checkModelStatusFromSDK()
        }
    }

    func checkModelStatusFromSDK() async {
        let isLoaded = await RunAnywhere.isModelLoaded
        let modelId = await RunAnywhere.getCurrentModelId()

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

    func handleSDKEvent(_ event: RASDKEvent) {
        guard event.category == .llm || event.component == .llm else { return }

        let modelId = event.model.modelID.isEmpty ? event.generation.modelID : event.model.modelID
        let generationId = event.generation.sessionID.isEmpty ? event.operationID : event.generation.sessionID

        switch (event.model.kind, event.generation.kind) {
        case (.loadCompleted, _), (_, .modelLoaded):
            handleModelLoadCompleted(modelId: modelId)

        case (.unloadCompleted, _), (_, .modelUnloaded):
            handleModelUnloaded(modelId: modelId)

        case (.loadStarted, _):
            break

        case (_, .firstTokenGenerated):
            let ttft = Double(event.generation.firstTokenLatencyMs)
            handleFirstToken(generationId: generationId, timeToFirstTokenMs: ttft)

        case (_, .completed), (_, .streamCompleted):
            let outputTokens = Int(event.generation.tokensUsed)
            let durationMs = Double(event.generation.latencyMs)
            let tps = durationMs > 0 && outputTokens > 0
                ? Double(outputTokens) / (durationMs / 1000.0)
                : 0
            handleGenerationCompleted(
                generationId: generationId,
                modelId: modelId,
                inputTokens: 0,
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

        if let matchingModel = ModelListViewModel.shared.availableModels.first(where: { $0.id == modelId }) {
            updateLoadedModelInfo(name: matchingModel.name, framework: matchingModel.framework)
            setLoadedModelSupportsThinking(matchingModel.supportsThinking)
        }

        if !wasLoaded {
            if messagesValue.first?.role != .system {
                addSystemMessage()
            }
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
