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
    @StateObject private var deviceInfo = DeviceInfoService.shared

    @State private var selectedModel: RAModelInfo?
    @State private var expandedFramework: InferenceFramework?
    @State private var availableFrameworks: [InferenceFramework] = []
    @State private var showingAddModelSheet = false

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
        Dictionary(grouping: sortedModels, by: \.consumerModelGroup)
    }

    private var visibleModelGroups: [ConsumerModelGroup] {
        ConsumerModelGroup.allCases.filter { !(groupedModels[$0] ?? []).isEmpty }
    }

    var body: some View {
        NavigationView {
            mainContentView
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
    }

    private var mainContentView: some View {
        List {
            deviceStatusSection
            modelsListSection
        }
        .navigationTitle("Models")
        .task {
            await loadInitialData()
        }
    }

    private func loadInitialData() async {
        await viewModel.loadModels()
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
            if sortedModels.isEmpty {
                Section {
                    VStack(alignment: .center, spacing: AppSpacing.mediumLarge) {
                        ProgressView()
                        Text("Loading models...")
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

    private func unavailableReason(for model: RAModelInfo) -> String? {
        guard model.framework == .foundationModels else { return nil }
        return SystemFoundationModels.unavailableReason
    }

    private func selectModel(_ model: RAModelInfo) async {
        selectedModel = model

        // Update the view model state
        await viewModel.selectModel(model)
    }
}

// MARK: - Supporting Views

/// Simplified model row with framework badge for flat list display
private struct SimplifiedModelRow: View {
    let model: RAModelInfo
    let availabilityReason: String?
    let isSelected: Bool
    let isLoadingModel: Bool
    let onDownloadCompleted: () -> Void
    let onSelectModel: () -> Void
    let onModelUpdated: () -> Void

    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0.0
    @State private var downloadStage: RADownloadStage = .downloading

    private var frameworkColor: Color {
        model.framework.consumerBackendColor
    }

    private var frameworkName: String {
        model.framework.consumerBackendLabel
    }

    private var isReady: Bool {
        availabilityReason == nil && (model.isBuiltIn || model.localPathURL != nil)
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

            // Action button
            if availabilityReason != nil {
                Button("Unavailable") {}
                    .font(AppTypography.caption)
                    .fontWeight(.semibold)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(true)
            } else if model.isBuiltIn {
                // Built-in models (Foundation Models, System TTS) - always ready
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
            } else {
                if isSelected {
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
        }
        .padding(.vertical, AppSpacing.smallMedium)
    }

    private var statusRowView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(spacing: AppSpacing.smallMedium) {
                let size = model.downloadSizeBytes
                if size > 0 {
                    Label(
                        ByteCountFormatter.string(fromByteCount: size, countStyle: .memory),
                        systemImage: "memorychip"
                    )
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
                }

                statusIndicator

                if availabilityReason == nil {
                    ForEach(model.consumerCapabilityBadges) { badge in
                        ConsumerBadge(badge: badge)
                    }
                }
            }
        }
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
