//
//  ModelSelectionSheet.swift
//  RunAnywhereAI
//
//  Reusable model selection sheet that can be used across the app
//

import SwiftUI
import RunAnywhere

// MARK: - Model Selection Context

/// Context for filtering frameworks and models based on the current experience/modality
enum ModelSelectionContext {
    case llm       // Chat experience - show LLM frameworks (llama.cpp, Foundation Models)
    case stt       // Speech-to-Text - show STT frameworks (ONNX STT)
    case tts       // Text-to-Speech - show TTS frameworks (ONNX TTS/Piper, System TTS)
    case voice     // Voice Assistant - show all voice-related (LLM + STT + TTS)

    var title: String {
        switch self {
        case .llm: return "Select LLM Model"
        case .stt: return "Select STT Model"
        case .tts: return "Select TTS Model"
        case .voice: return "Select Model"
        }
    }

    var relevantCategories: Set<ModelCategory> {
        switch self {
        case .llm:
            return [.language, .multimodal]
        case .stt:
            return [.speechRecognition]
        case .tts:
            return [.speechSynthesis]
        case .voice:
            return [.language, .multimodal, .speechRecognition, .speechSynthesis]
        }
    }
}

struct ModelSelectionSheet: View {
    @StateObject private var viewModel = ModelListViewModel.shared
    @StateObject private var deviceInfo = DeviceInfoService.shared

    @Environment(\.dismiss)
    var dismiss

    @State private var selectedModel: ModelInfo?
    @State private var expandedFramework: InferenceFramework?
    @State private var availableFrameworks: [InferenceFramework] = []
    @State private var isLoadingModel = false
    @State private var loadingProgress: String = ""

    let context: ModelSelectionContext
    let onModelSelected: (ModelInfo) async -> Void

    init(
        context: ModelSelectionContext = .llm,
        onModelSelected: @escaping (ModelInfo) async -> Void
    ) {
        self.context = context
        self.onModelSelected = onModelSelected
    }

    private var availableModels: [ModelInfo] {
        viewModel.availableModels
            .filter { context.relevantCategories.contains($0.category) }
            .sorted { modelPriority($0) != modelPriority($1)
                ? modelPriority($0) < modelPriority($1)
                : $0.name < $1.name
            }
    }

    private func modelPriority(_ model: ModelInfo) -> Int {
        model.framework == .foundationModels ? 0 : (model.localPath != nil ? 1 : 2)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    deviceStatusSection
                    modelsListSection
                }
                if isLoadingModel {
                    LoadingModelOverlay(loadingProgress: loadingProgress)
                }
            }
            .navigationTitle(context.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
        }
        .adaptiveSheetFrame()
        .task { await loadInitialData() }
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
        if context == .tts && !filtered.contains(.systemTTS) {
            filtered.insert(.systemTTS, at: 0)
        }
        await MainActor.run { self.availableFrameworks = filtered }
    }

    private func shouldShowFramework(_ framework: InferenceFramework) -> Bool {
        viewModel.availableModels
            .filter { $0.framework == framework }
            .contains { context.relevantCategories.contains($0.category) }
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
        Section {
            if availableModels.isEmpty {
                loadingModelsView
            } else {
                modelsContent
            }
        } header: {
            Text("Choose a Model")
        } footer: {
            Text(
                "All models run privately on your device. " +
                "Larger models may provide better quality but use more memory."
            )
            .font(AppTypography.caption)
            .foregroundColor(AppColors.textSecondary)
        }
    }

    private var loadingModelsView: some View {
        VStack(alignment: .center, spacing: AppSpacing.mediumLarge) {
            ProgressView()
            Text("Loading available models...")
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xLarge)
    }

    @ViewBuilder private var modelsContent: some View {
        if context == .tts {
            SystemTTSRow(isLoading: isLoadingModel) { await selectSystemTTS() }
        }
        ForEach(availableModels, id: \.id) { model in
            FlatModelRow(
                model: model,
                isSelected: selectedModel?.id == model.id,
                isLoading: isLoadingModel,
                onDownloadCompleted: { Task { await viewModel.loadModels() } },
                onSelectModel: { Task { await selectAndLoadModel(model) } },
                onModelUpdated: { Task { await viewModel.loadModels() } }
            )
        }
    }
}

// MARK: - Model Loading Actions

extension ModelSelectionSheet {
    private func selectSystemTTS() async {
        await MainActor.run {
            isLoadingModel = true
            loadingProgress = "Configuring System TTS..."
        }

        let systemTTSModel = ModelInfo(
            id: "system-tts",
            name: "System TTS",
            category: .speechSynthesis,
            format: .unknown,
            framework: .systemTTS,
            downloadURL: nil
        )

        try? await Task.sleep(nanoseconds: 300_000_000)
        await MainActor.run { loadingProgress = "System TTS ready!" }
        try? await Task.sleep(nanoseconds: 200_000_000)

        await onModelSelected(systemTTSModel)
        await MainActor.run {
            isLoadingModel = false
            dismiss()
        }
    }

    private func selectAndLoadModel(_ model: ModelInfo) async {
        if model.framework != .foundationModels {
            guard model.localPath != nil else { return }
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
            await MainActor.run {
                isLoadingModel = false
                loadingProgress = ""
                selectedModel = nil
            }
            print("Failed to load model: \(error)")
        }
    }

    private func loadModelForContext(_ model: ModelInfo) async throws {
        switch context {
        case .llm: try await RunAnywhere.loadModel(model.id)
        case .stt: try await RunAnywhere.loadSTTModel(model.id)
        case .tts: try await RunAnywhere.loadTTSModel(model.id)
        case .voice: try await loadModelForVoiceContext(model)
        }
    }

    private func loadModelForVoiceContext(_ model: ModelInfo) async throws {
        switch model.category {
        case .speechRecognition: try await RunAnywhere.loadSTTModel(model.id)
        case .speechSynthesis: try await RunAnywhere.loadTTSModel(model.id)
        default: try await RunAnywhere.loadModel(model.id)
        }
    }

    private func handleModelLoadSuccess(_ model: ModelInfo) async {
        let isLLM = context == .llm ||
            (context == .voice && [.language, .multimodal].contains(model.category))

        if isLLM {
            await viewModel.setCurrentModel(model)
            await MainActor.run {
                NotificationCenter.default.post(
                    name: Notification.Name("ModelLoaded"),
                    object: model
                )
            }
        }
        await onModelSelected(model)
    }
}
