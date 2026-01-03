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
        // Events now come from C++ via generic BridgedEvent
        guard event.category == .llm else { return }

        let modelId = event.properties["model_id"] ?? ""
        let generationId = event.properties["generation_id"] ?? ""

        switch event.type {
        case "llm_model_load_completed":
            handleModelLoadCompleted(modelId: modelId)

        case "llm_model_unloaded":
            handleModelUnloaded(modelId: modelId)

        case "llm_model_load_started":
            break

        case "llm_first_token":
            let ttft = Double(event.properties["time_to_first_token_ms"] ?? "0") ?? 0
            handleFirstToken(generationId: generationId, timeToFirstTokenMs: ttft)

        case "llm_generation_completed":
            let inputTokens = Int(event.properties["input_tokens"] ?? "0") ?? 0
            let outputTokens = Int(event.properties["output_tokens"] ?? "0") ?? 0
            let durationMs = Double(event.properties["processing_time_ms"] ?? "0") ?? 0
            let tps = Double(event.properties["tokens_per_second"] ?? "0") ?? 0
            handleGenerationCompleted(
                generationId: generationId,
                modelId: modelId,
                inputTokens: inputTokens,
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
