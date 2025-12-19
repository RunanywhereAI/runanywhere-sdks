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
    case stt       // Speech-to-Text - show STT frameworks (WhisperKit, ONNX STT)
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
    @Environment(\.dismiss) var dismiss

    @State private var selectedModel: ModelInfo?
    @State private var expandedFramework: InferenceFramework?
    @State private var availableFrameworks: [InferenceFramework] = []
    @State private var showingAddModelSheet = false
    @State private var isLoadingModel = false
    @State private var loadingProgress: String = ""
    @State private var showSystemTTS = false

    /// The modality context for filtering frameworks and models
    let context: ModelSelectionContext

    let onModelSelected: (ModelInfo) async -> Void

    init(context: ModelSelectionContext = .llm, onModelSelected: @escaping (ModelInfo) async -> Void) {
        self.context = context
        self.onModelSelected = onModelSelected
    }

    /// Get all models relevant to this context, sorted by availability (downloaded first)
    private var availableModels: [ModelInfo] {
        viewModel.availableModels.filter { model in
            context.relevantCategories.contains(model.category)
        }.sorted { model1, model2 in
            // Foundation Models first (built-in), then downloaded, then not downloaded
            let m1Priority = model1.preferredFramework == .foundationModels ? 0 : (model1.localPath != nil ? 1 : 2)
            let m2Priority = model2.preferredFramework == .foundationModels ? 0 : (model2.localPath != nil ? 1 : 2)
            if m1Priority != m2Priority {
                return m1Priority < m2Priority
            }
            return model1.name < model2.name
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                mainContentView

                if isLoadingModel {
                    loadingOverlay
                }
            }
            .navigationTitle(context.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isLoadingModel)
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isLoadingModel)
                    .keyboardShortcut(.escape)
                }
                #endif
            }
        }
        .adaptiveSheetFrame()
        .task {
            await loadInitialData()
        }
    }

    private var mainContentView: some View {
        List {
            deviceStatusSection
            modelsListSection
        }
    }

    private var loadingOverlay: some View {
        AppColors.overlayMedium
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: AppSpacing.xLarge) {
                    ProgressView()
                        .scaleEffect(DeviceFormFactor.current == .desktop ? 1.5 : 1.2)
                        #if os(macOS)
                        .controlSize(.large)
                        #endif

                    Text("Loading Model")
                        .font(AppTypography.headline)

                    Text(loadingProgress)
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(minWidth: 200)
                }
                .padding(DeviceFormFactor.current == .desktop ? 40 : AppSpacing.xxLarge)
                .frame(minWidth: DeviceFormFactor.current == .desktop ? 300 : nil)
                .background(AppColors.backgroundPrimary)
                .cornerRadius(AppSpacing.cornerRadiusXLarge)
                .shadow(radius: AppSpacing.shadowXLarge)
            }
    }

    private func loadInitialData() async {
        await viewModel.loadModels()
        await loadAvailableFrameworks()
    }

    private func loadAvailableFrameworks() async {
        let allFrameworks = await MainActor.run {
            RunAnywhere.getRegisteredFrameworks()
        }

        // Filter frameworks based on context by checking if they have relevant models
        var filteredFrameworks = allFrameworks.filter { framework in
            shouldShowFramework(framework)
        }

        // For TTS context, always include System TTS as an option
        if context == .tts && !filteredFrameworks.contains(.systemTTS) {
            // Add System TTS at the beginning of the list
            filteredFrameworks.insert(.systemTTS, at: 0)
        }

        await MainActor.run {
            self.availableFrameworks = filteredFrameworks
        }
    }

    /// Determines if a framework should be shown based on the current context
    private func shouldShowFramework(_ framework: InferenceFramework) -> Bool {
        // Get models for this framework
        let modelsForFramework = viewModel.availableModels.filter { model in
            if framework == .foundationModels {
                return model.preferredFramework == .foundationModels
            } else {
                return model.compatibleFrameworks.contains(framework)
            }
        }

        // Check if any model's category matches the context's relevant categories
        let hasRelevantModels = modelsForFramework.contains { model in
            context.relevantCategories.contains(model.category)
        }

        return hasRelevantModels
    }

    private var deviceStatusSection: some View {
        Section("Device Status") {
            if let device = deviceInfo.deviceInfo {
                deviceInfoRows(device)
            } else {
                loadingDeviceRow
            }
        }
    }

    private func deviceInfoRows(_ device: SystemDeviceInfo) -> some View {
        Group {
            deviceInfoRow(label: "Model", systemImage: "iphone", value: device.modelName)
            deviceInfoRow(label: "Chip", systemImage: "cpu", value: device.chipName)
            deviceInfoRow(label: "Memory", systemImage: "memorychip",
                         value: ByteCountFormatter.string(fromByteCount: device.totalMemory, countStyle: .memory))

            if device.neuralEngineAvailable {
                neuralEngineRow
            }
        }
    }

    private func deviceInfoRow(label: String, systemImage: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    private var neuralEngineRow: some View {
        HStack {
            Label("Neural Engine", systemImage: "brain")
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppColors.statusGreen)
        }
    }

    private var loadingDeviceRow: some View {
        HStack {
            ProgressView()
            Text("Loading device info...")
                .foregroundColor(AppColors.textSecondary)
        }
    }

    /// Flat list of all available models with framework badges
    private var modelsListSection: some View {
        Section {
            if availableModels.isEmpty {
                VStack(alignment: .center, spacing: AppSpacing.mediumLarge) {
                    ProgressView()
                    Text("Loading available models...")
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.xLarge)
            } else {
                // System TTS option for TTS context
                if context == .tts {
                    systemTTSRow
                }

                // All models in a flat list
                ForEach(availableModels, id: \.id) { model in
                    FlatModelRow(
                        model: model,
                        isSelected: selectedModel?.id == model.id,
                        isLoading: isLoadingModel,
                        onDownloadCompleted: {
                            Task {
                                await viewModel.loadModels()
                            }
                        },
                        onSelectModel: {
                            Task {
                                await selectAndLoadModel(model)
                            }
                        },
                        onModelUpdated: {
                            Task {
                                await viewModel.loadModels()
                            }
                        }
                    )
                }
            }
        } header: {
            Text("Choose a Model")
        } footer: {
            Text("All models run privately on your device. Larger models may provide better quality but use more memory.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    /// System TTS selection row - uses built-in AVSpeechSynthesizer
    private var systemTTSRow: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                // Name with badge
                HStack(spacing: AppSpacing.smallMedium) {
                    Text("System Voice")
                        .font(AppTypography.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textPrimary)

                    // System badge
                    Text("System")
                        .font(AppTypography.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, AppSpacing.small)
                        .padding(.vertical, AppSpacing.xxSmall)
                        .background(Color.primary.opacity(0.1))
                        .foregroundColor(.primary)
                        .cornerRadius(AppSpacing.cornerRadiusSmall)
                }

                // Status
                HStack(spacing: AppSpacing.xxSmall) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.statusGreen)
                        .font(AppTypography.caption2)
                    Text("Built-in • Always available")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.statusGreen)
                }
            }

            Spacer()

            Button("Use") {
                Task {
                    await selectSystemTTS()
                }
            }
            .font(AppTypography.caption)
            .fontWeight(.semibold)
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primaryAccent)
            .controlSize(.small)
            .disabled(isLoadingModel)
        }
        .padding(.vertical, AppSpacing.smallMedium)
    }

    /// Select System TTS - no model loading needed
    private func selectSystemTTS() async {
        await MainActor.run {
            isLoadingModel = true
            loadingProgress = "Configuring System TTS..."
        }

        // Create a pseudo ModelInfo for System TTS
        let systemTTSModel = ModelInfo(
            id: "system-tts",
            name: "System TTS",
            category: .speechSynthesis,
            format: .unknown,
            downloadURL: nil,
            compatibleFrameworks: [.systemTTS],
            preferredFramework: .systemTTS
        )

        // Brief delay to show loading state
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

        await MainActor.run {
            loadingProgress = "System TTS ready!"
        }

        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // Call the callback with the system TTS model
        await onModelSelected(systemTTSModel)

        await MainActor.run {
            isLoadingModel = false
            dismiss()
        }
    }

    private func toggleFramework(_ framework: InferenceFramework) {
        withAnimation {
            if expandedFramework == framework {
                expandedFramework = nil
            } else {
                expandedFramework = framework
            }
        }
    }

    private func selectAndLoadModel(_ model: ModelInfo) async {
        // Foundation Models don't need local path check
        if model.preferredFramework != .foundationModels {
            guard model.localPath != nil else {
                return // Model not downloaded yet
            }
        }

        await MainActor.run {
            isLoadingModel = true
            loadingProgress = "Initializing \(model.name)..."
            selectedModel = model
        }

        do {
            await MainActor.run {
                loadingProgress = "Loading model into memory..."
            }

            // Load model based on the context/modality
            switch context {
            case .llm:
                // LLM models use RunAnywhere.loadModel()
                try await RunAnywhere.loadModel(model.id)

            case .stt:
                // STT models use RunAnywhere.loadSTTModel()
                try await RunAnywhere.loadSTTModel(model.id)

            case .tts:
                // TTS models use RunAnywhere.loadTTSModel()
                try await RunAnywhere.loadTTSModel(model.id)

            case .voice:
                // Voice context handles all three - determine which based on model category
                switch model.category {
                case .speechRecognition:
                    try await RunAnywhere.loadSTTModel(model.id)
                case .speechSynthesis:
                    try await RunAnywhere.loadTTSModel(model.id)
                case .language, .multimodal:
                    try await RunAnywhere.loadModel(model.id)
                default:
                    try await RunAnywhere.loadModel(model.id)
                }
            }

            await MainActor.run {
                loadingProgress = "Model loaded successfully!"
            }

            // Wait a moment to show success message
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            // Only update ModelListViewModel for LLM models
            // STT and TTS models are tracked separately via ModelLifecycleTracker
            if context == .llm || (context == .voice && (model.category == .language || model.category == .multimodal)) {
                // LLM models use ModelListViewModel to track current model
                await viewModel.setCurrentModel(model)

                // Post notification that model was loaded successfully
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: Notification.Name("ModelLoaded"),
                        object: model
                    )
                }
            }

            // Call the callback with the loaded model
            await onModelSelected(model)

            await MainActor.run {
                dismiss()
            }

        } catch {
            await MainActor.run {
                isLoadingModel = false
                loadingProgress = ""
                selectedModel = nil
                // Could show error alert here
            }
            print("Failed to load model: \(error)")
        }
    }

}

// MARK: - Supporting Views

private struct SelectableModelRow: View {
    let model: ModelInfo
    let isSelected: Bool
    let isLoading: Bool
    let onDownloadCompleted: () -> Void
    let onSelectModel: () -> Void
    let onModelUpdated: () -> Void

    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(model.name)
                    .font(AppTypography.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)

                HStack(spacing: AppSpacing.smallMedium) {
                    let size = model.memoryRequired ?? 0
                    if size > 0 {
                        Label(
                            ByteCountFormatter.string(fromByteCount: size, countStyle: .memory),
                            systemImage: "memorychip"
                        )
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)
                    }

                    let format = model.format
                    Text(format.rawValue.uppercased())
                        .font(AppTypography.caption2)
                        .padding(.horizontal, AppSpacing.small)
                        .padding(.vertical, AppSpacing.xxSmall)
                        .background(AppColors.badgeGray)
                        .cornerRadius(AppSpacing.cornerRadiusSmall)

                    // Show thinking indicator if model supports thinking
                    if model.supportsThinking {
                        HStack(spacing: AppSpacing.xxSmall) {
                            Image(systemName: "brain")
                                .font(AppTypography.caption2)
                            Text("THINKING")
                                .font(AppTypography.caption2)
                        }
                        .padding(.horizontal, AppSpacing.small)
                        .padding(.vertical, AppSpacing.xxSmall)
                        .background(AppColors.badgePurple)
                        .foregroundColor(AppColors.primaryPurple)
                        .cornerRadius(AppSpacing.cornerRadiusSmall)
                    } else if model.localPath != nil {
                        Button(action: {
                            Task {
                                // Thinking support update not available in new API
                                // Will be enabled when the model is loaded
                                onModelUpdated()
                            }
                        }) {
                            HStack(spacing: AppSpacing.xxSmall) {
                                Image(systemName: "brain")
                                    .font(AppTypography.caption2)
                                Text("ENABLE")
                                    .font(AppTypography.caption2)
                            }
                            .padding(.horizontal, AppSpacing.small)
                            .padding(.vertical, AppSpacing.xxSmall)
                            .background(AppColors.badgeOrange)
                            .foregroundColor(AppColors.primaryOrange)
                            .cornerRadius(AppSpacing.cornerRadiusSmall)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // Show download status or built-in status
                if model.preferredFramework == .foundationModels {
                    // Foundation Models are built-in
                    HStack(spacing: AppSpacing.xSmall) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(AppColors.statusGreen)
                            .font(AppTypography.caption2)
                        Text("Built-in")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.statusGreen)
                    }
                } else if let _ = model.downloadURL {
                    if model.localPath == nil {
                        HStack(spacing: AppSpacing.xSmall) {
                            if isDownloading {
                                ProgressView(value: downloadProgress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                Text("\(Int(downloadProgress * 100))%")
                                    .font(AppTypography.caption2)
                                    .foregroundColor(AppColors.textSecondary)
                            } else {
                                Text("Available for download")
                                    .font(AppTypography.caption2)
                                    .foregroundColor(AppColors.primaryAccent)
                            }
                        }
                    } else {
                        HStack(spacing: AppSpacing.xSmall) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppColors.statusGreen)
                                .font(AppTypography.caption2)
                            Text("Downloaded")
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.statusGreen)
                        }
                    }
                }
            }

            Spacer()

            // Action buttons based on model state
            HStack(spacing: AppSpacing.smallMedium) {
                if model.preferredFramework == .foundationModels {
                    // Foundation Models are built-in, always ready to select
                    Button("Select") {
                        onSelectModel()
                    }
                    .font(AppTypography.caption)
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.primaryAccent)
                    .controlSize(.small)
                    .disabled(isLoading || isSelected)
                } else if let _ = model.downloadURL, model.localPath == nil {
                    // Model needs to be downloaded
                    if isDownloading {
                        VStack(spacing: AppSpacing.xSmall) {
                            ProgressView()
                                .scaleEffect(0.8)
                            if downloadProgress > 0 {
                                Text("\(Int(downloadProgress * 100))%")
                                    .font(AppTypography.caption2)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    } else {
                        Button("Download") {
                            Task {
                                await downloadModel()
                            }
                        }
                        .font(AppTypography.caption)
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.primaryAccent)
                        .controlSize(.small)
                        .disabled(isLoading)
                    }
                } else if model.localPath != nil {
                    // Model is downloaded - show select button
                    Button("Select") {
                        onSelectModel()
                    }
                    .font(AppTypography.caption)
                    .buttonStyle(.borderedProminent)
                    .tint(AppColors.primaryAccent)
                    .controlSize(.small)
                    .disabled(isLoading || isSelected)
                }
            }
        }
        .padding(.vertical, AppSpacing.xSmall)
        .opacity(isLoading && !isSelected ? 0.6 : 1.0)
    }

    private func downloadModel() async {
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0.0
        }

        do {
            // Use the Download service to download the model
            let task = try await Download.shared.downloadModel(model)

            // Process progress updates
            for await progress in task.progress {
                await MainActor.run {
                    self.downloadProgress = progress.overallProgress
                    print("Download progress for \(model.name): \(Int(progress.overallProgress * 100))%")
                }

                // Check if download completed
                if progress.stage == .completed {
                    await MainActor.run {
                        self.downloadProgress = 1.0
                        self.isDownloading = false
                        onDownloadCompleted()
                        print("Model \(model.name) downloaded successfully")
                    }
                    return
                }
            }

            // If we exit the loop normally, download completed
            await MainActor.run {
                self.downloadProgress = 1.0
                self.isDownloading = false
                onDownloadCompleted()
            }

        } catch {
            print("Download failed: \(error)")
            await MainActor.run {
                downloadProgress = 0.0
                isDownloading = false
            }
        }
    }
}

// MARK: - Flat Model Row (New Consumer-Friendly Design)

/// A model row designed for flat list display with prominent framework badge
private struct FlatModelRow: View {
    let model: ModelInfo
    let isSelected: Bool
    let isLoading: Bool
    let onDownloadCompleted: () -> Void
    let onSelectModel: () -> Void
    let onModelUpdated: () -> Void

    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0

    private var frameworkColor: Color {
        guard let framework = model.preferredFramework else { return .gray }
        switch framework {
        case .llamaCpp: return AppColors.primaryAccent
        case .onnx: return .purple
        case .foundationModels: return .primary
        case .whisperKit: return .green
        default: return .gray
        }
    }

    private var frameworkName: String {
        guard let framework = model.preferredFramework else { return "Unknown" }
        switch framework {
        case .llamaCpp: return "Fast"
        case .onnx: return "ONNX"
        case .foundationModels: return "Apple"
        case .whisperKit: return "Whisper"
        default: return framework.displayName
        }
    }

    private var statusIcon: String {
        if model.preferredFramework == .foundationModels {
            return "checkmark.circle.fill"
        } else if model.localPath != nil {
            return "checkmark.circle.fill"
        } else {
            return "arrow.down.circle"
        }
    }

    private var statusColor: Color {
        if model.preferredFramework == .foundationModels || model.localPath != nil {
            return AppColors.statusGreen
        } else {
            return AppColors.primaryAccent
        }
    }

    var body: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            // Left: Model info with framework badge
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                // Model name with framework badge inline
                HStack(spacing: AppSpacing.smallMedium) {
                    Text(model.name)
                        .font(AppTypography.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textPrimary)

                    // Framework badge
                    Text(frameworkName)
                        .font(AppTypography.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, AppSpacing.small)
                        .padding(.vertical, AppSpacing.xxSmall)
                        .background(frameworkColor.opacity(0.15))
                        .foregroundColor(frameworkColor)
                        .cornerRadius(AppSpacing.cornerRadiusSmall)
                }

                // Size and status row
                HStack(spacing: AppSpacing.smallMedium) {
                    // Size badge
                    if let size = model.memoryRequired, size > 0 {
                        Label(
                            ByteCountFormatter.string(fromByteCount: size, countStyle: .memory),
                            systemImage: "memorychip"
                        )
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)
                    }

                    // Status indicator
                    if isDownloading {
                        HStack(spacing: AppSpacing.xSmall) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("\(Int(downloadProgress * 100))%")
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    } else {
                        HStack(spacing: AppSpacing.xxSmall) {
                            Image(systemName: statusIcon)
                                .foregroundColor(statusColor)
                                .font(AppTypography.caption2)
                            Text(model.preferredFramework == .foundationModels ? "Built-in" : (model.localPath != nil ? "Ready" : "Download"))
                                .font(AppTypography.caption2)
                                .foregroundColor(statusColor)
                        }
                    }

                    // Thinking support indicator
                    if model.supportsThinking {
                        HStack(spacing: AppSpacing.xxSmall) {
                            Image(systemName: "brain")
                            Text("Smart")
                        }
                        .font(AppTypography.caption2)
                        .padding(.horizontal, AppSpacing.small)
                        .padding(.vertical, AppSpacing.xxSmall)
                        .background(AppColors.badgePurple)
                        .foregroundColor(AppColors.primaryPurple)
                        .cornerRadius(AppSpacing.cornerRadiusSmall)
                    }
                }
            }

            Spacer()

            // Right: Action button
            actionButton
        }
        .padding(.vertical, AppSpacing.smallMedium)
        .opacity(isLoading && !isSelected ? 0.6 : 1.0)
    }

    @ViewBuilder
    private var actionButton: some View {
        if model.preferredFramework == .foundationModels {
            // Foundation Models are built-in
            Button("Use") {
                onSelectModel()
            }
            .font(AppTypography.caption)
            .fontWeight(.semibold)
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primaryAccent)
            .controlSize(.small)
            .disabled(isLoading || isSelected)
        } else if model.localPath == nil {
            // Model needs to be downloaded
            if isDownloading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button {
                    Task {
                        await downloadModel()
                    }
                } label: {
                    HStack(spacing: AppSpacing.xxSmall) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Get")
                    }
                }
                .font(AppTypography.caption)
                .fontWeight(.semibold)
                .buttonStyle(.bordered)
                .tint(AppColors.primaryAccent)
                .controlSize(.small)
                .disabled(isLoading)
            }
        } else {
            // Model is downloaded - ready to use
            Button("Use") {
                onSelectModel()
            }
            .font(AppTypography.caption)
            .fontWeight(.semibold)
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primaryAccent)
            .controlSize(.small)
            .disabled(isLoading || isSelected)
        }
    }

    private func downloadModel() async {
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0.0
        }

        do {
            let progressStream = try await RunAnywhere.downloadModel(model.id)

            for await progress in progressStream {
                await MainActor.run {
                    self.downloadProgress = progress.percentage
                }

                switch progress.state {
                case .completed:
                    await MainActor.run {
                        self.downloadProgress = 1.0
                        self.isDownloading = false
                        onDownloadCompleted()
                    }
                    return

                case .failed:
                    await MainActor.run {
                        self.downloadProgress = 0.0
                        self.isDownloading = false
                    }
                    return

                default:
                    continue
                }
            }
        } catch {
            await MainActor.run {
                downloadProgress = 0.0
                isDownloading = false
            }
        }
    }
}
