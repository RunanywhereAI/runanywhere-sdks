//
//  SimplifiedModelsView.swift
//  RunAnywhereAI
//
//  A simplified models view for managing AI models
//

import SwiftUI
import RunAnywhere

struct SimplifiedModelsView: View {
    @StateObject private var viewModel = ModelListViewModel.shared
    @StateObject private var storageViewModel = StorageViewModel.shared
    @StateObject private var deviceInfo = DeviceInfoService.shared

    @State private var selectedModel: RAModelInfo?
    @State private var expandedFramework: InferenceFramework?
    @State private var availableFrameworks: [InferenceFramework] = []
    @State private var showingAddModelSheet = false
    @State private var searchText = ""
    @State private var selectedBackendFilter: ModelBackendFilter = .all
    @State private var selectedGroupFilter: ModelGroupFilter = .all

    private let recommendedModelIds: Set<String> = [
        "mlx-qwen3-0.6b-4bit",
        "mlx-qwen3.5-0.8b-mlx-4bit",
        "mlx-llama-3.2-1b-instruct-4bit",
        "mlx-lfm2-350m",
        "mlx-qwen2-vl-2b-instruct-4bit",
        "mlx-qwen3-asr-0.6b-8bit",
        "mlx-soprano-1.1-80m-5bit",
        "mlx-qwen3-embedding-0.6b-4bit-dwq",
        "qwen3-0.6b-q4_k_m",
        "qwen3.5-0.8b-q4_k_m",
        "lfm2-350m-q4_k_m",
        "lfm2.5-1.2b-instruct-q4_k_m",
        "smolvlm2-256m-video-instruct-q8_0",
        "sherpa-onnx-whisper-tiny.en",
        "vits-piper-en_US-lessac-medium"
    ]

    /// All available models sorted by availability (downloaded first)
    private var sortedModels: [RAModelInfo] {
        viewModel.availableModels.sorted { model1, model2 in
            let m1BuiltIn = model1.framework == .foundationModels
                || model1.framework == .systemTts
                || model1.artifactType == .builtIn
            let m2BuiltIn = model2.framework == .foundationModels
                || model2.framework == .systemTts
                || model2.artifactType == .builtIn
            let m1Priority = m1BuiltIn ? 0 : (model1.localPathURL != nil ? 1 : 2)
            let m2Priority = m2BuiltIn ? 0 : (model2.localPathURL != nil ? 1 : 2)
            if m1Priority != m2Priority {
                return m1Priority < m2Priority
            }
            return model1.name < model2.name
        }
    }

    private var groupedModels: [ConsumerModelGroup: [RAModelInfo]] {
        Dictionary(grouping: catalogModels, by: \.consumerModelGroup)
    }

    private var visibleModelGroups: [ConsumerModelGroup] {
        ConsumerModelGroup.allCases.filter { !(groupedModels[$0] ?? []).isEmpty }
    }

    private var filteredModels: [RAModelInfo] {
        sortedModels.filter { model in
            searchMatches(model)
                && selectedBackendFilter.matches(model)
                && selectedGroupFilter.matches(model)
        }
    }

    private var hasActiveFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedBackendFilter != .all
            || selectedGroupFilter != .all
    }

    private var emptyModelsMessage: String {
        if viewModel.isLoading && sortedModels.isEmpty {
            return "Loading models..."
        }
        if hasActiveFilters {
            return "No models match these filters"
        }
        return "No models available"
    }

    private var recommendedModels: [RAModelInfo] {
        filteredModels.filter { recommendedModelIds.contains($0.id) }
    }

    private var catalogModels: [RAModelInfo] {
        filteredModels.filter { !recommendedModelIds.contains($0.id) }
    }

    var body: some View {
        #if os(macOS)
        mainContentView
        #else
        NavigationView {
            mainContentView
        }
        .navigationViewStyle(.stack)
        #endif
    }

    private var mainContentView: some View {
        List {
            searchAndFilterSection
            deviceStatusSection
            storageSection
            recommendedSection
            modelsListSection
        }
        .navigationTitle("Models")
        .task {
            await loadInitialData()
        }
    }

    private func searchMatches(_ model: RAModelInfo) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        return [
            model.name,
            model.id,
            model.framework.consumerBackendLabel,
            model.framework.consumerBackendDescription,
            model.consumerModelGroup.title,
            model.quantizationLabel,
            model.requiresHfAuth ? "private hf auth hugging face" : ""
        ]
        .joined(separator: " ")
        .lowercased()
        .contains(query)
    }

    private func loadInitialData() async {
        await viewModel.loadModels()
        await storageViewModel.loadData()
        await loadAvailableFrameworks()
    }

    private func loadAvailableFrameworks() async {
        // Get available frameworks from SDK - derived from registered models
        let frameworks = await RunAnywhere.getRegisteredFrameworks()
        await MainActor.run {
            self.availableFrameworks = frameworks
        }
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
            deviceInfoRow(
                label: "Memory",
                systemImage: "memorychip",
                value: ByteCountFormatter.string(fromByteCount: device.totalMemory, countStyle: .memory)
            )

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

    /// Flat list of all models with framework badges
    private var modelsListSection: some View {
        Group {
            if filteredModels.isEmpty {
                Section {
                    VStack(alignment: .center, spacing: AppSpacing.mediumLarge) {
                        Image(systemName: hasActiveFilters ? "magnifyingglass" : "cube")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(AppColors.textSecondary.opacity(0.6))
                        Text(emptyModelsMessage)
                            .font(AppTypography.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.xLarge)
                } header: {
                    Text("Available Models")
                }
            } else {
                ForEach(visibleModelGroups) { group in
                    if let models = groupedModels[group] {
                        Section {
                            ForEach(models, id: \.id) { model in
                                SimplifiedModelRow(
                                    model: model,
                                    availabilityReason: unavailableReason(for: model),
                                    isSelected: selectedModel?.id == model.id,
                                    isLoadingModel: viewModel.isLoadingModel,
                                    onDownloadCompleted: {
                                        Task {
                                            await viewModel.loadModels()
                                            await storageViewModel.refreshData()
                                        }
                                    },
                                    onSelectModel: {
                                        Task {
                                            await selectModel(model)
                                        }
                                    },
                                    onModelUpdated: {
                                        Task {
                                            await viewModel.loadModels()
                                            await storageViewModel.refreshData()
                                        }
                                    },
                                    onDeleteModel: {
                                        Task {
                                            await deleteModel(model)
                                        }
                                    }
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
    }

    private var searchAndFilterSection: some View {
        Section {
            HStack(spacing: AppSpacing.smallMedium) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.textSecondary)
                TextField("Search models, backends, or private access", text: $searchText)
                    .disableAutocorrection(true)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.smallMedium)
            .background(AppColors.backgroundSecondary)
            .cornerRadius(AppSpacing.cornerRadiusRegular)

            filterScrollRow(title: "Backend") {
                ForEach(ModelBackendFilter.allCases) { filter in
                    filterChip(title: filter.title, isSelected: selectedBackendFilter == filter) {
                        selectedBackendFilter = filter
                    }
                }
            }

            filterScrollRow(title: "Modality") {
                ForEach(ModelGroupFilter.allCases) { filter in
                    filterChip(title: filter.title, isSelected: selectedGroupFilter == filter) {
                        selectedGroupFilter = filter
                    }
                }
            }

        } header: {
            Text("Find Models")
        } footer: {
            Text("\(filteredModels.count) of \(sortedModels.count) models shown")
                .font(AppTypography.caption)
        }
    }

    private var recommendedSection: some View {
        Group {
            if !recommendedModels.isEmpty {
                Section {
                    ForEach(recommendedModels, id: \.id) { model in
                        SimplifiedModelRow(
                            model: model,
                            availabilityReason: unavailableReason(for: model),
                            isSelected: selectedModel?.id == model.id,
                            isLoadingModel: viewModel.isLoadingModel,
                            onDownloadCompleted: {
                                Task {
                                    await viewModel.loadModels()
                                    await storageViewModel.refreshData()
                                }
                            },
                            onSelectModel: {
                                Task {
                                    await selectModel(model)
                                }
                            },
                            onModelUpdated: {
                                Task {
                                    await viewModel.loadModels()
                                    await storageViewModel.refreshData()
                                }
                            },
                            onDeleteModel: {
                                Task {
                                    await deleteModel(model)
                                }
                            }
                        )
                    }
                } header: {
                    Text("Recommended")
                } footer: {
                    Text("Consumer-friendly defaults for chat, vision, voice, and documents.")
                        .font(AppTypography.caption)
                }
            }
        }
    }

    private func filterScrollRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.small) {
                    content()
                }
            }
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? AppColors.textWhite : AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.smallMedium)
                .padding(.vertical, AppSpacing.xSmall)
                .background(isSelected ? AppColors.primaryAccent : AppColors.backgroundSecondary)
                .cornerRadius(AppSpacing.cornerRadiusRegular)
        }
        .buttonStyle(.plain)
    }

    private func unavailableReason(for model: RAModelInfo) -> String? {
        guard model.framework == .foundationModels else { return nil }
        return SystemFoundationModels.unavailableReason
    }

    private func selectModel(_ model: RAModelInfo) async {
        selectedModel = model

        // Update the view model state
        await viewModel.selectModel(model)
    }

    private func deleteModel(_ model: RAModelInfo) async {
        do {
            try await viewModel.deleteModel(model)
            await storageViewModel.refreshData()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private var storageSection: some View {
        Section {
            if storageViewModel.isLoading {
                HStack {
                    ProgressView()
                    Text("Loading storage...")
                        .foregroundColor(AppColors.textSecondary)
                }
            } else {
                storageInfoRow(
                    label: "Models Storage",
                    systemImage: "externaldrive",
                    value: ByteCountFormatter.string(
                        fromByteCount: storageViewModel.modelStorageSize,
                        countStyle: .file
                    )
                )

                storageInfoRow(
                    label: "Downloaded Models",
                    systemImage: "number",
                    value: "\(storageViewModel.storedModels.count)"
                )

                HStack {
                    Button {
                        Task { await storageViewModel.clearCache() }
                    } label: {
                        Label("Clear Cache", systemImage: "trash")
                    }
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.primaryRed)

                    Spacer()

                    Button {
                        Task { await storageViewModel.cleanTempFiles() }
                    } label: {
                        Label("Clean Temp", systemImage: "trash")
                    }
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.primaryOrange)
                }

                if let error = storageViewModel.errorMessage {
                    Text(error)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.primaryRed)
                }
            }
        } header: {
            Text("Storage")
        } footer: {
            Text("Downloaded models can be removed from their model row below.")
                .font(AppTypography.caption)
        }
    }

    private func storageInfoRow(label: String, systemImage: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundColor(AppColors.textSecondary)
        }
    }
}

// MARK: - Supporting Views

private enum ModelBackendFilter: String, CaseIterable, Identifiable {
    case all
    case mlx
    case llamaCpp
    case onnx
    case sherpa
    case apple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .mlx: return "MLX"
        case .llamaCpp: return "Llama CPP"
        case .onnx: return "ONNX"
        case .sherpa: return "Sherpa"
        case .apple: return "Apple"
        }
    }

    func matches(_ model: RAModelInfo) -> Bool {
        switch self {
        case .all:
            return true
        case .mlx:
            return model.framework == .mlx
        case .llamaCpp:
            return model.framework == .llamaCpp
        case .onnx:
            return model.framework == .onnx
        case .sherpa:
            return model.framework == .sherpa
        case .apple:
            return model.framework == .foundationModels || model.framework == .systemTts
        }
    }
}

private enum ModelGroupFilter: String, CaseIterable, Identifiable {
    case all
    case chat
    case vision
    case voice
    case documents
    case adapters

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .chat: return "Chat"
        case .vision: return "Vision"
        case .voice: return "Voice"
        case .documents: return "Documents"
        case .adapters: return "Adapters"
        }
    }

    func matches(_ model: RAModelInfo) -> Bool {
        switch self {
        case .all:
            return true
        case .chat:
            return model.consumerModelGroup == .chatModels || model.consumerModelGroup == .appleBuiltIn
        case .vision:
            return model.consumerModelGroup == .visionModels
        case .voice:
            return model.consumerModelGroup == .voiceModels
        case .documents:
            return model.consumerModelGroup == .documentModels
        case .adapters:
            return model.consumerModelGroup == .modelAdapters
        }
    }
}

/// Simplified model row with framework badge for flat list display
private struct SimplifiedModelRow: View {
    let model: RAModelInfo
    let availabilityReason: String?
    let isSelected: Bool
    let isLoadingModel: Bool
    let onDownloadCompleted: () -> Void
    let onSelectModel: () -> Void
    let onModelUpdated: () -> Void
    let onDeleteModel: () async -> Void

    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0
    @State private var downloadStage: RADownloadStage = .downloading
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false

    private var frameworkColor: Color {
        model.framework.consumerBackendColor
    }

    private var frameworkName: String {
        model.framework.consumerBackendLabel
    }

    private var isReady: Bool {
        availabilityReason == nil && (model.isBuiltIn || model.localPathURL != nil)
    }

    private var isDeletable: Bool {
        availabilityReason == nil && !model.isBuiltIn && model.localPathURL != nil
    }

    private var statusIcon: String {
        if availabilityReason != nil {
            return "exclamationmark.triangle.fill"
        }
        return isReady ? "checkmark.circle.fill" : "arrow.down.circle"
    }

    private var statusColor: Color {
        if availabilityReason != nil {
            return AppColors.statusOrange
        }
        return isReady ? AppColors.statusGreen : AppColors.primaryAccent
    }

    private var statusText: String {
        if let availabilityReason {
            return availabilityReason
        }
        if model.isBuiltIn {
            return "Built-in"
        }
        return model.localPathURL != nil ? "Ready" : "Download"
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.mediumLarge) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                Text(model.name)
                    .font(AppTypography.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                backendBadge

                Text(model.framework.consumerBackendDescription)
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)

                statusRowView
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingActions
        }
        .padding(.vertical, AppSpacing.smallMedium)
        .alert("Delete Model", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    isDeleting = true
                    await onDeleteModel()
                    isDeleting = false
                }
            }
        } message: {
            Text("Delete \(model.name) from this device? You can download it again later.")
        }
    }

    @ViewBuilder private var trailingActions: some View {
        VStack(alignment: .trailing, spacing: AppSpacing.small) {
            primaryAction

            if isDeletable {
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(AppColors.primaryRed)
                }
                .font(AppTypography.caption)
                .buttonStyle(.bordered)
                .tint(AppColors.primaryRed)
                .controlSize(.small)
                .disabled(isDeleting)
                .accessibilityLabel("Delete \(model.name)")
            }
        }
    }

    @ViewBuilder private var primaryAction: some View {
        if availabilityReason != nil {
            Button("Unavailable") {}
                .font(AppTypography.caption)
                .fontWeight(.semibold)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(true)
        } else if model.isBuiltIn {
            Button("Use") {
                onSelectModel()
            }
            .font(AppTypography.caption)
            .fontWeight(.semibold)
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primaryAccent)
            .controlSize(.small)
            .disabled(isSelected || isLoadingModel)
        } else if model.localPathURL == nil {
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
            }
        } else if isSelected {
            HStack(spacing: AppSpacing.xxSmall) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppColors.statusGreen)
                Text("Active")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.statusGreen)
            }
        } else {
            Button("Use") {
                onSelectModel()
            }
            .font(AppTypography.caption)
            .fontWeight(.semibold)
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primaryAccent)
            .controlSize(.small)
            .disabled(isLoadingModel)
        }
    }

    private var statusRowView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(spacing: AppSpacing.smallMedium) {
                Label(model.consumerSizeLabel, systemImage: "memorychip")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)

                statusIndicator
            }

            if availabilityReason == nil {
                capabilityBadgeRows
            }
        }
    }

    @ViewBuilder private var capabilityBadgeRows: some View {
        let badges = model.consumerCapabilityBadges
        let showQuantization = model.quantizationLabel != "Default"
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.smallMedium) {
                if showQuantization {
                    quantizationPill
                }
                ForEach(badges) { badge in
                    ConsumerBadge(badge: badge)
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                HStack(spacing: AppSpacing.smallMedium) {
                    if showQuantization {
                        quantizationPill
                    }
                    ForEach(Array(badges.prefix(2))) { badge in
                        ConsumerBadge(badge: badge)
                    }
                }

                if badges.count > 2 {
                    HStack(spacing: AppSpacing.smallMedium) {
                        ForEach(Array(badges.dropFirst(2).prefix(2))) { badge in
                            ConsumerBadge(badge: badge)
                        }
                        if badges.count > 4 {
                            Text("+\(badges.count - 4)")
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private var quantizationPill: some View {
        Text(model.quantizationLabel)
            .font(AppTypography.caption2)
            .fontWeight(.medium)
            .foregroundColor(AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.xSmall)
            .padding(.vertical, 2)
            .background(AppColors.backgroundSecondary)
            .cornerRadius(AppSpacing.cornerRadiusSmall)
    }

    @ViewBuilder private var statusIndicator: some View {
        if isDownloading {
            HStack(spacing: AppSpacing.xSmall) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("\(downloadStage.displayName)… \(Int(downloadProgress * 100))%")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxSmall) {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .font(AppTypography.caption2)
                Text(statusText)
                    .font(AppTypography.caption2)
                    .foregroundColor(statusColor)
                    .lineLimit(availabilityReason == nil ? 1 : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var backendBadge: some View {
        HStack(spacing: AppSpacing.xxSmall) {
            Image(systemName: model.framework.consumerBackendIcon)
            Text(frameworkName)
        }
        .font(AppTypography.caption2)
        .fontWeight(.medium)
        .padding(.horizontal, AppSpacing.small)
        .padding(.vertical, AppSpacing.xxSmall)
        .background(frameworkColor.opacity(0.15))
        .foregroundColor(frameworkColor)
        .cornerRadius(AppSpacing.cornerRadiusSmall)
    }

    private func downloadModel() async {
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0.0
            downloadStage = .downloading
        }

        do {
            try await RunAnywhere.downloadModel(model) { progress in
                await MainActor.run {
                    self.downloadProgress = Double(progress.overallProgress)
                    self.downloadStage = progress.stage
                }
            }

            await MainActor.run {
                self.downloadProgress = 1.0
                self.isDownloading = false
                self.downloadStage = .downloading
                onDownloadCompleted()
            }
        } catch {
            await MainActor.run {
                downloadProgress = 0.0
                isDownloading = false
                downloadStage = .downloading
            }
        }
    }
}

#Preview {
    SimplifiedModelsView()
}
