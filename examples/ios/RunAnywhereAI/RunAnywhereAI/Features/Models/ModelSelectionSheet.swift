//
//  ModelSelectionSheet.swift
//  RunAnywhereAI
//
//  Reusable model selection sheet, scoped by modality context. Uses the same
//  family-first components as the Models tab: the recommended pick highlighted
//  up top, then one clean row per family with variants in a family detail.
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

    // MARK: - Data

    private var hardwareTier: HardwareTier {
        tierResolver.resolve(from: deviceInfo.deviceInfo)
    }

    private var candidateModels: [RAModelInfo] {
        viewModel.availableModels
            .filter { model in
                guard !model.isLoRAAdapterArtifact else { return false }
                guard context.relevantCategories.contains(model.category) else { return false }
                if let allowed = context.allowedFrameworks {
                    guard allowed.contains(model.framework) else { return false }
                }
                // For RAG embedding context, exclude supporting files (vocab,
                // tokenizer) that are not selectable as standalone models.
                if context == .ragEmbedding {
                    guard !model.id.hasSuffix("-vocab") && !model.id.hasSuffix("-tokenizer") else {
                        return false
                    }
                }
                return true
            }
    }

    /// Candidates matching the friendly search (clean name / ability only).
    private var filteredModels: [RAModelInfo] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return candidateModels }
        return candidateModels.filter { model in
            let tagText = model.consumerTags.map(\.label).joined(separator: " ")
            return [model.consumerDisplayName, model.category.consumerCapabilityLabel, tagText]
                .joined(separator: " ")
                .lowercased()
                .contains(query)
        }
    }

    /// The single best-for-device model for this scoped context, highlighted at
    /// the top of the picker.
    private var recommendedModel: RAModelInfo? {
        let selection = recommendationEngine.recommend(
            tier: hardwareTier,
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
        guard let pick, candidateModels.contains(where: { $0.id == pick.id }) else { return nil }
        return pick
    }

    /// Families over all scoped candidates. The recommended pick stays in its
    /// family too, so every family detail shows its complete variant list.
    private var browseFamilies: [ModelFamily] {
        ModelFamilyCatalog.families(from: filteredModels)
    }

    private var handlers: ModelActionHandlers {
        ModelActionHandlers(
            onSelect: { model in Task { await selectAndLoadModel(model) } },
            onChanged: { Task { await viewModel.loadModels() } }
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    searchSection
                    recommendedSection
                    familiesSection
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
        .task { await viewModel.loadModels() }
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

    // MARK: - Sections

    private var searchSection: some View {
        Section {
            HStack(spacing: AppSpacing.smallMedium) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.textSecondary)
                TextField("Search models by name or ability", text: $searchText)
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
        }
    }

    @ViewBuilder private var recommendedSection: some View {
        if let recommended = recommendedModel, searchText.isEmpty {
            Section {
                ModelVariantRow(
                    variant: recommended,
                    highlight: "Recommended for your device",
                    availabilityReason: unavailableReason(for: recommended),
                    isSelected: selectedModel?.id == recommended.id,
                    isLoadingModel: isLoadingModel,
                    handlers: handlers
                )
            } header: {
                Label("Recommended", systemImage: "sparkles")
            }
        }
    }

    @ViewBuilder private var familiesSection: some View {
        if browseFamilies.isEmpty {
            Section {
                emptyStateView
            } header: {
                Text("Browse Models")
            }
        } else {
            Section {
                ForEach(browseFamilies) { family in
                    NavigationLink {
                        ModelFamilyDetailView(
                            family: family,
                            tier: hardwareTier,
                            selectedModelID: selectedModel?.id,
                            isLoadingModel: isLoadingModel,
                            availabilityReason: unavailableReason(for:),
                            handlers: handlers
                        )
                    } label: {
                        ModelFamilyRow(family: family)
                    }
                }
            } header: {
                Text("Browse Models")
            } footer: {
                Text("Pick a family, then choose the size that fits. Tap Use to switch models.")
                    .font(AppTypography.caption)
            }
        }
    }

    private var emptyStateView: some View {
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

    private func unavailableReason(for model: RAModelInfo) -> String? {
        guard model.framework == .foundationModels else { return nil }
        return SystemFoundationModels.unavailableReason
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
            loadingProgress = "Initializing \(model.consumerDisplayName)..."
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
                    ? "Failed to load \(model.consumerDisplayName)."
                    : "Failed to load \(model.consumerDisplayName): \(message)"
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
