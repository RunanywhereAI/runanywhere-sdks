//
//  ModelsSupportingSections.swift
//  RunAnywhereAI
//
//  Standalone sections for the Models screen (device summary + storage), split
//  out to keep `SimplifiedModelsView` focused on layout composition.
//

import SwiftUI
import RunAnywhere

/// Modality filter for the family browse list.
enum ModelModalityFilter: String, CaseIterable, Identifiable {
    case all
    case chat
    case vision
    case voice
    case documents
    case images

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .chat: return "Chat"
        case .vision: return "Vision"
        case .voice: return "Voice"
        case .documents: return "Documents"
        case .images: return "Images"
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
        case .images:
            return model.consumerModelGroup == .imageGenerationModels
        }
    }

    /// Whether the "Image Generation (coming soon)" placeholder row should show
    /// under this filter. Shown on All + Images.
    var showsImageGenerationPlaceholder: Bool {
        self == .all || self == .images
    }
}

/// Search field + modality chips for the family browse list.
struct ModelSearchBar: View {
    @Binding var searchText: String
    @Binding var selectedModality: ModelModalityFilter

    var body: some View {
        Group {
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
                }
            }
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.smallMedium)
            .background(AppColors.backgroundSecondary)
            .cornerRadius(AppSpacing.cornerRadiusRegular)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.small) {
                    ForEach(ModelModalityFilter.allCases) { filter in
                        chip(filter)
                    }
                }
            }
        }
    }

    private func chip(_ filter: ModelModalityFilter) -> some View {
        let isSelected = selectedModality == filter
        return Button {
            selectedModality = filter
        } label: {
            Text(filter.title)
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
}

/// Device summary: hardware tier headline plus model/chip/memory/Neural Engine.
struct DeviceSummarySection: View {
    let tier: HardwareTier
    let device: SystemDeviceInfo?

    var body: some View {
        Section {
            if let device {
                header
                infoRow(label: "Model", systemImage: "iphone", value: device.modelName)
                infoRow(label: "Chip", systemImage: "cpu", value: device.chipName)
                infoRow(
                    label: "Memory",
                    systemImage: "memorychip",
                    value: ByteCountFormatter.string(fromByteCount: device.totalMemory, countStyle: .memory)
                )
                if device.neuralEngineAvailable {
                    neuralEngineRow
                }
            } else {
                loadingRow
            }
        } header: {
            Text("Your Device")
        }
    }

    private var header: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            Image(systemName: tier.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(AppColors.primaryAccent)
                .frame(width: AppSpacing.iconLarge, height: AppSpacing.iconLarge)
                .background(AppColors.primaryAccent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusXLarge))

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(tier.displayName)
                    .font(AppTypography.headlineSemibold)
                    .foregroundColor(AppColors.textPrimary)
                Text(tier.tagline)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, AppSpacing.xSmall)
    }

    private func infoRow(label: String, systemImage: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer()
            Text(value).foregroundColor(AppColors.textSecondary)
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

    private var loadingRow: some View {
        HStack {
            ProgressView()
            Text("Loading device info...")
                .foregroundColor(AppColors.textSecondary)
        }
    }
}

/// Storage usage summary + cache maintenance actions.
struct ModelStorageSection: View {
    @ObservedObject var storageViewModel: StorageViewModel

    var body: some View {
        Section {
            if storageViewModel.isLoading {
                HStack {
                    ProgressView()
                    Text("Loading storage...")
                        .foregroundColor(AppColors.textSecondary)
                }
            } else {
                infoRow(
                    label: "Models Storage",
                    systemImage: "externaldrive",
                    value: ByteCountFormatter.string(
                        fromByteCount: storageViewModel.modelStorageSize,
                        countStyle: .file
                    )
                )
                infoRow(
                    label: "Downloaded Models",
                    systemImage: "number",
                    value: "\(storageViewModel.storedModels.count)"
                )
                maintenanceButtons

                if let error = storageViewModel.errorMessage {
                    Text(error)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.primaryRed)
                }
            }
        } header: {
            Text("Storage")
        } footer: {
            Text("Downloaded models can be removed from a model's family detail.")
                .font(AppTypography.caption)
        }
    }

    private var maintenanceButtons: some View {
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
    }

    private func infoRow(label: String, systemImage: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer()
            Text(value).foregroundColor(AppColors.textSecondary)
        }
    }
}
