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
            }
        }
    }

    // MARK: - SDK Event Handling

    func handleSDKEvent(_ event: any SDKEvent) {
        guard let llmEvent = event as? LLMEvent else { return }

        switch llmEvent {
        case .modelLoadCompleted(let modelId, _, _, _):
            handleModelLoadCompleted(modelId: modelId)

        case .modelUnloaded(let modelId):
            handleModelUnloaded(modelId: modelId)

        case .modelLoadStarted:
            break

        case let .firstToken(generationId, _, timeToFirstTokenMs, _):
            handleFirstToken(generationId: generationId, timeToFirstTokenMs: timeToFirstTokenMs)

        case let .generationCompleted(genId, mId, inTok, outTok, dur, tps, _, _, _, _, _, _):
            handleGenerationCompleted(
                generationId: genId,
                modelId: mId,
                inputTokens: inTok,
                outputTokens: outTok,
                durationMs: dur,
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
