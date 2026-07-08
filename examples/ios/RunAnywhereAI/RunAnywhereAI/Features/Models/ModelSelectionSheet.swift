//
//  ModelSelectionSheet.swift
//  RunAnywhereAI
//
//  Reusable model selection sheet that can be used across the app
//

import SwiftUI
import RunAnywhere
import os

// MARK: - Model Selection Context

/// Context for filtering frameworks and models based on the current experience/modality
enum ModelSelectionContext {
    case llm           // Chat experience - show LLM frameworks (llama.cpp, Foundation Models)
    case stt           // Speech-to-Text - show STT frameworks (ONNX STT)
    case tts           // Text-to-Speech - show TTS frameworks (ONNX TTS/Piper, System TTS)
    case vad           // Voice Activity Detection - show VAD frameworks (ONNX VAD/Silero)
    case voice         // Voice Assistant - show all voice-related (LLM + STT + TTS)
    case vlm           // Vision Language Model - show VLM frameworks
    case ragEmbedding  // RAG embedding model - ONNX language/embedding models
    case ragLLM        // RAG generation model - LLM for answering questions

    var title: String {
        switch self {
        case .llm: return "Choose Chat Model"
        case .stt: return "Choose Dictation Model"
        case .tts: return "Choose Voice Model"
        case .vad: return "Choose Speech Detector"
        case .voice: return "Choose Voice Component"
        case .vlm: return "Choose Vision Model"
        case .ragEmbedding: return "Choose Document Model"
        case .ragLLM: return "Choose Answer Model"
        }
    }

    var relevantCategories: Set<ModelCategory> {
        switch self {
        case .llm:
            return [.language]
        case .stt:
            return [.speechRecognition]
        case .tts:
            return [.speechSynthesis]
        case .vad:
            return [.voiceActivityDetection]
        case .voice:
            return [.language, .speechRecognition, .speechSynthesis]
        case .vlm:
            return [.multimodal, .vision]
        case .ragEmbedding:
            return [.embedding]
        case .ragLLM:
            return [.language]
        }
    }

    /// Frameworks to include. nil means all frameworks that have matching models.
    var allowedFrameworks: Set<InferenceFramework>? {
        switch self {
        case .ragEmbedding:
            return [.onnx, .mlx]
        case .ragLLM:
            return [.llamaCpp, .mlx]
        default:
            return nil
        }
    }
}

struct ModelSelectionSheet: View {
    @StateObject private var viewModel = ModelListViewModel.shared
    @StateObject private var deviceInfo = DeviceInfoService.shared

    @Environment(\.dismiss)
    var dismiss

    @State private var selectedModel: RAModelInfo?
    @State private var expandedFramework: InferenceFramework?
    @State private var availableFrameworks: [InferenceFramework] = []
    @State private var isLoadingModel = false
    @State private var loadingProgress: String = ""
    @State private var loadErrorMessage: String?
    @State private var searchText = ""

    let context: ModelSelectionContext
    let onModelSelected: (RAModelInfo) async -> Void

    private let recommendationEngine = ModelRecommendationEngine()
    private let tierResolver = HardwareTierResolver()

    init(
        context: ModelSelectionContext = .llm,
        onModelSelected: @escaping (RAModelInfo) async -> Void
    ) {
        self.context = context
        self.onModelSelected = onModelSelected
    }

    /// The single best-for-device model for this scoped context, highlighted at
    /// the top of the picker. Pure recommendation over the live catalog.
    private var recommendedModel: RAModelInfo? {
        let tier = tierResolver.resolve(from: deviceInfo.deviceInfo)
        let selection = recommendationEngine.recommend(
            tier: tier,
            appleFoundationAvailable: tierResolver.appleFoundationAvailable,
            from: viewModel.availableModels
        )
        let pick: RAModelInfo?
        switch context {
        case .llm, .voice, .ragLLM:
            pick = selection.defaultChatModel
        case .stt:
            pick = selection.recommendedASR
        case .tts:
            pick = selection.recommendedTTS
        case .vlm:
            pick = selection.recommendedVLM
        case .ragEmbedding:
            pick = selection.recommendedEmbedding
        case .vad:
            pick = nil
        }
        // Only surface it if it actually belongs to this scoped candidate set.
        guard let pick, candidateModels.contains(where: { $0.id == pick.id }) else { return nil }
        return pick
    }

    private var candidateModels: [RAModelInfo] {
        viewModel.availableModels
            .filter { model in
                guard !model.isLoRAAdapterArtifact else { return false }
                guard context.relevantCategories.contains(model.category) else { return false }
                if let allowed = context.allowedFrameworks {
                    guard allowed.contains(model.framework) else { return false }
                }
                // For RAG embedding context, exclude supporting files (vocab, tokenizer)
                // that are not selectable as standalone embedding models.
                // Supporting files have ids ending in "-vocab" or "-tokenizer".
                if context == .ragEmbedding {
                    guard !model.id.hasSuffix("-vocab") && !model.id.hasSuffix("-tokenizer") else {
                        return false
                    }
                }
                return true
            }
            .sorted {
                let lhsPriority = modelPriority($0)
                let rhsPriority = modelPriority($1)
                return lhsPriority != rhsPriority ? lhsPriority < rhsPriority : $0.name < $1.name
            }
    }

    private var availableModels: [RAModelInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return candidateModels }
        return candidateModels.filter { model in
            [
                model.name,
                model.id,
                model.framework.consumerBackendLabel,
                model.framework.consumerBackendDescription,
                model.consumerModelGroup.title,
                model.requiresHfAuth ? "private hf auth hugging face" : ""
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    private var groupedModels: [ConsumerModelGroup: [RAModelInfo]] {
        Dictionary(grouping: availableModels, by: \.consumerModelGroup)
    }

    private var visibleModelGroups: [ConsumerModelGroup] {
        ConsumerModelGroup.allCases.filter { !(groupedModels[$0] ?? []).isEmpty }
    }

    private func modelPriority(_ model: RAModelInfo) -> Int {
        if unavailableReason(for: model) != nil { return 4 }
        if model.framework == .foundationModels { return 0 }
        if model.localPathURL != nil { return 1 }
        return model.framework == .mlx ? 2 : 3
    }

    private func unavailableReason(for model: RAModelInfo) -> String? {
        guard model.framework == .foundationModels else { return nil }
        return SystemFoundationModels.unavailableReason
    }

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    modelSearchSection
                    deviceStatusSection
                    modelsListSection
                }
                if isLoadingModel {
                    LoadingModelOverlay(loadingProgress: loadingProgress)
                }
            }
            .navigationTitle(context.title)
            #if os(iOS)
            .navigationBarTitleDisplayModeCompat(.inline)
            #endif
            .toolbar { toolbarContent }
        }
        .adaptiveSheetFrame()
        .task { await loadInitialData() }
        .alert(
            "Unable to Load Model",
            isPresented: Binding(
                get: { loadErrorMessage != nil },
                set: { if !$0 { loadErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { loadErrorMessage = nil }
        } message: {
            if let loadErrorMessage {
                Text(loadErrorMessage)
            }
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItemGroup(placement: .navigationBarLeading) {
            Button("Cancel") { dismiss() }.disabled(isLoadingModel)
        }
        #else
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }.disabled(isLoadingModel).keyboardShortcut(.escape)
        }
        #endif
    }

    private func loadInitialData() async {
        await viewModel.loadModels()
        await loadAvailableFrameworks()
    }

    private func loadAvailableFrameworks() async {
        let allFrameworks = await RunAnywhere.getRegisteredFrameworks()
        var filtered = allFrameworks.filter { shouldShowFramework($0) }
        if context == .tts && !filtered.contains(.systemTts) {
            filtered.insert(.systemTts, at: 0)
        }
        await MainActor.run { self.availableFrameworks = filtered }
    }

    private func shouldShowFramework(_ framework: InferenceFramework) -> Bool {
        if let allowed = context.allowedFrameworks, !allowed.contains(framework) {
            return false
        }
        return viewModel.availableModels
            .filter { $0.framework == framework }
            .contains { context.relevantCategories.contains($0.category) }
    }
}

// MARK: - Search Section

extension ModelSelectionSheet {
    private var modelSearchSection: some View {
        Section {
            HStack(spacing: AppSpacing.smallMedium) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.textSecondary)
                TextField("Search models, backends, private access", text: $searchText)
                    .disableAutocorrection(true)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.smallMedium)
            .background(AppColors.backgroundSecondary)
            .cornerRadius(AppSpacing.cornerRadiusRegular)
        } footer: {
            Text("\(availableModels.count) of \(candidateModels.count) models shown")
                .font(AppTypography.caption)
        }
    }
}

// MARK: - Device Status Section

extension ModelSelectionSheet {
    private var deviceStatusSection: some View {
        Section("Device Status") {
            if let device = deviceInfo.deviceInfo {
                DeviceInfoRow(label: "Model", systemImage: "iphone", value: device.modelName)
                DeviceInfoRow(label: "Chip", systemImage: "cpu", value: device.chipName)
                DeviceInfoRow(
                    label: "Memory",
                    systemImage: "memorychip",
                    value: ByteCountFormatter.string(
                        fromByteCount: device.totalMemory,
                        countStyle: .memory
                    )
                )
                if device.neuralEngineAvailable {
                    NeuralEngineRow()
                }
            } else {
                LoadingDeviceRow()
            }
        }
    }
}

// MARK: - Models List Section

extension ModelSelectionSheet {
    private var modelsListSection: some View {
        Group {
            if availableModels.isEmpty {
                Section {
                    loadingModelsView
                } header: {
                    Text("Choose a Model")
                }
            } else {
                modelsContent
            }
        }
    }

    private var loadingModelsView: some View {
        VStack(alignment: .center, spacing: AppSpacing.mediumLarge) {
            if candidateModels.isEmpty {
                ProgressView()
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary.opacity(0.7))
            }
            Text(candidateModels.isEmpty ? "Loading available models..." : "No models match your search")
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xLarge)
    }

    @ViewBuilder private var modelsContent: some View {
        if let recommended = recommendedModel, searchText.isEmpty {
            Section {
                FlatModelRow(
                    model: recommended,
                    availabilityReason: unavailableReason(for: recommended),
                    isSelected: selectedModel?.id == recommended.id,
                    isLoading: isLoadingModel,
                    onDownloadCompleted: { Task { await viewModel.loadModels() } },
                    onSelectModel: { Task { await selectAndLoadModel(recommended) } },
                    onModelUpdated: { Task { await viewModel.loadModels() } }
                )
            } header: {
                Label("Recommended for your device", systemImage: "sparkles")
            }
        }

        ForEach(visibleModelGroups) { group in
            if let models = groupedModels[group] {
                Section {
                    ForEach(models, id: \.id) { model in
                        FlatModelRow(
                            model: model,
                            availabilityReason: unavailableReason(for: model),
                            isSelected: selectedModel?.id == model.id,
                            isLoading: isLoadingModel,
                            onDownloadCompleted: { Task { await viewModel.loadModels() } },
                            onSelectModel: { Task { await selectAndLoadModel(model) } },
                            onModelUpdated: { Task { await viewModel.loadModels() } }
                        )
                    }
                } header: {
                    Text(group.title)
                } footer: {
                    Text(group.footer)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }
}

// MARK: - Model Loading Actions

extension ModelSelectionSheet {
    private func selectAndLoadModel(_ model: RAModelInfo) async {
        if let reason = unavailableReason(for: model) {
            await MainActor.run {
                selectedModel = nil
                loadErrorMessage = reason
            }
            return
        }

        // Built-in models (Foundation Models, System TTS, artifactType .builtIn)
        // have no on-disk artifact and are always ready to load via the platform
        // backend. All other frameworks require a resolved local path — if it is
        // missing we surface an error rather than silently dropping the tap.
        if !model.isBuiltIn, model.localPathURL == nil {
            await MainActor.run {
                selectedModel = nil
                loadErrorMessage = "Model files are not available on this device. Download the model and try again."
            }
            return
        }

        // RAG model selection does not pre-load into memory; just select and dismiss.
        let isRAGContext = context == .ragEmbedding || context == .ragLLM
        if isRAGContext {
            await MainActor.run { selectedModel = model }
            await handleModelLoadSuccess(model)
            await MainActor.run { dismiss() }
            return
        }

        await MainActor.run {
            isLoadingModel = true
            loadingProgress = "Initializing \(model.name)..."
            selectedModel = model
        }

        do {
            await MainActor.run { loadingProgress = "Loading model into memory..." }
            try await loadModelForContext(model)
            await MainActor.run { loadingProgress = "Model loaded successfully!" }
            try await Task.sleep(nanoseconds: 500_000_000)
            await handleModelLoadSuccess(model)
            await MainActor.run { dismiss() }
        } catch {
            // Surface the failure to the user instead of silently printing.
            // The sheet stays open so the user can retry or pick a different
            // model without navigating back through the setup flow.
            let message = (error as? SDKException)?.message ?? error.localizedDescription
            await MainActor.run {
                isLoadingModel = false
                loadingProgress = ""
                selectedModel = nil
                loadErrorMessage = message.isEmpty
                    ? "Failed to load \(model.name)."
                    : "Failed to load \(model.name): \(message)"
            }
        }
    }

    private func loadModelForContext(_ model: RAModelInfo) async throws {
        let category: RAModelCategory
        switch context {
        case .llm: category = .language
        case .stt: category = .speechRecognition
        case .tts: category = .speechSynthesis
        case .vad: category = .voiceActivityDetection
        case .voice: category = voiceContextCategory(for: model)
        case .vlm: category = .multimodal
        case .ragEmbedding, .ragLLM:
            // RAG models are referenced by local file path at pipeline creation time,
            // not pre-loaded into memory via the SDK model loader.
            return
        }
        try await loadViaCanonicalAPI(modelID: model.id, category: category)
    }

    private func voiceContextCategory(for model: RAModelInfo) -> RAModelCategory {
        switch model.category {
        case .speechRecognition: return .speechRecognition
        case .speechSynthesis: return .speechSynthesis
        default: return .language
        }
    }

    private func loadViaCanonicalAPI(modelID: String, category: RAModelCategory) async throws {
        var request = RAModelLoadRequest()
        request.modelID = modelID
        request.category = category
        let result = await RunAnywhere.loadModel(request)
        if !result.success {
            throw SDKException(code: .unknown, message: result.errorMessage, category: .internal)
        }
        let resolvedID = result.modelID.isEmpty ? modelID : result.modelID
        Logger(subsystem: "com.runanywhere", category: "Models").info(
            "Model load succeeded for \(resolvedID, privacy: .public)"
        )
        if context == .stt {
            Logger(subsystem: "com.runanywhere", category: "STT").info(
                "STT model loaded successfully: \(resolvedID, privacy: .public)"
            )
        }
    }

    private func handleModelLoadSuccess(_ model: RAModelInfo) async {
        let isLLM = context == .llm ||
            (context == .voice && [.language, .multimodal].contains(model.category))

        // `RunAnywhere.loadModel` already published the canonical
        // component-lifecycle event the LLM/VLM ViewModels subscribe to, so the
        // app only updates its own shared selection state here.
        if isLLM {
            await MainActor.run {
                viewModel.setCurrentModel(model)
            }
        }

        await onModelSelected(model)
    }
}
