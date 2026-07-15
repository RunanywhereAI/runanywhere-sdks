//
//  RecommendedModelViews.swift
//  RunAnywhereAI
//
//  Presentation components for the hardware-aware "Recommended for you" hero
//  section on the Models screen. Kept separate from SimplifiedModelsView so each
//  view has a single, focused responsibility.
//

import SwiftUI
import RunAnywhere

/// Bundled callbacks for model rows/cards so views avoid long parameter lists.
struct ModelActionHandlers {
    /// Load / activate the model.
    let onSelect: (RAModelInfo) -> Void
    /// Reload catalog + storage after a download or delete completes.
    let onChanged: () -> Void
    /// Delete the downloaded model from the device. Nil hides the delete action.
    var onDelete: ((RAModelInfo) -> Void)?

    init(
        onSelect: @escaping (RAModelInfo) -> Void,
        onChanged: @escaping () -> Void,
        onDelete: ((RAModelInfo) -> Void)? = nil
    ) {
        self.onSelect = onSelect
        self.onChanged = onChanged
        self.onDelete = onDelete
    }
}

/// Reusable primary action (Get / Use / Active / Built-in) with inline download
/// progress. Single responsibility: drive a model's readiness action so the
/// recommended card and companion chip never duplicate this logic.
struct ModelPrimaryActionButton: View {
    let model: RAModelInfo
    let availabilityReason: String?
    let isSelected: Bool
    let isLoadingModel: Bool
    let onSelectModel: () -> Void
    let onChanged: () -> Void

    // Download state lives in the shared tracker so it survives navigation, can be
    // cancelled, and can't start twice for the same model.
    private var downloads: ModelDownloadTracker { .shared }

    var body: some View {
        Group {
            if availabilityReason != nil {
                Button("Unavailable") {}
                    .buttonStyle(.bordered)
                    .disabled(true)
            } else if model.isBuiltIn {
                useButton
            } else if model.localPathURL == nil {
                downloadControl
            } else if isSelected {
                activeIndicator
            } else {
                useButton
            }
        }
        .font(AppTypography.caption)
        .fontWeight(.semibold)
        .controlSize(.small)
        .alert("Download Failed", isPresented: Binding(
            get: { downloads.errorMessage(model.id) != nil },
            set: { if !$0 { downloads.clearError(model.id) } }
        ), presenting: downloads.errorMessage(model.id)) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    private var useButton: some View {
        Button("Use") { onSelectModel() }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primaryAccent)
            .disabled((isSelected && model.isBuiltIn) || isLoadingModel)
    }

    @ViewBuilder private var downloadControl: some View {
        if downloads.isDownloading(model.id) {
            HStack(spacing: AppSpacing.xxSmall) {
                ProgressView().scaleEffect(0.7)
                Text("\(Int(downloads.progress(model.id) * 100))%")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
                Button {
                    downloads.cancel(model.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel download")
            }
        } else {
            Button {
                downloads.start(model) { onChanged() }
            } label: {
                HStack(spacing: AppSpacing.xxSmall) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Get")
                }
            }
            .buttonStyle(.bordered)
            .tint(AppColors.primaryAccent)
        }
    }

    private var activeIndicator: some View {
        HStack(spacing: AppSpacing.xxSmall) {
            Image(systemName: "checkmark.circle.fill")
            Text("Active")
        }
        .font(AppTypography.caption2)
        .foregroundColor(AppColors.statusGreen)
    }

}

/// Rich, rounded card for a single recommended model in the hero section.
struct RecommendedModelCard: View {
    let model: RAModelInfo
    let subtitle: String
    let availabilityReason: String?
    let isSelected: Bool
    let isLoadingModel: Bool
    var highlight: String?
    let handlers: ModelActionHandlers

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.mediumLarge) {
            capabilityIcon

            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                if let highlight {
                    Text(highlight.uppercased())
                        .font(AppTypography.caption2Bold)
                        .foregroundColor(AppColors.primaryAccent)
                }

                Text(model.consumerDisplayName)
                    .font(AppTypography.subheadlineSemibold)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: AppSpacing.smallMedium) {
                    Text(subtitle)
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)
                    BackendPill(framework: model.framework)
                }

                tagWrap
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ModelPrimaryActionButton(
                model: model,
                availabilityReason: availabilityReason,
                isSelected: isSelected,
                isLoadingModel: isLoadingModel,
                onSelectModel: { handlers.onSelect(model) },
                onChanged: handlers.onChanged
            )
        }
        .padding(.vertical, AppSpacing.smallMedium)
    }

    private var capabilityIcon: some View {
        Image(systemName: model.category.consumerCapabilityIcon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(AppColors.primaryAccent)
            .frame(width: AppSpacing.iconMedium, height: AppSpacing.iconMedium)
            .background(AppColors.primaryAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge))
    }

    private var tagWrap: some View {
        HStack(spacing: AppSpacing.xSmall) {
            ForEach(model.consumerTags) { badge in
                ConsumerBadge(badge: badge)
            }
        }
    }
}

/// Compact chip for the "Also recommended" companions row (VLM/ASR/TTS/embedding).
struct CompanionModelChip: View {
    let model: RAModelInfo
    let isSelected: Bool
    let isLoadingModel: Bool
    let handlers: ModelActionHandlers

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(spacing: AppSpacing.xSmall) {
                Image(systemName: model.category.consumerCapabilityIcon)
                    .foregroundColor(AppColors.primaryAccent)
                Text(model.category.consumerCapabilityLabel)
                    .font(AppTypography.caption2Medium)
                    .foregroundColor(AppColors.textSecondary)
            }

            Text(model.consumerDisplayName)
                .font(AppTypography.caption2)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(model.consumerSizeLabel)
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.textSecondary)

            Spacer(minLength: 0)

            ModelPrimaryActionButton(
                model: model,
                availabilityReason: nil,
                isSelected: isSelected,
                isLoadingModel: isLoadingModel,
                onSelectModel: { handlers.onSelect(model) },
                onChanged: handlers.onChanged
            )
        }
        .padding(AppSpacing.mediumLarge)
        .frame(width: 180, height: 148, alignment: .leading)
        .background(AppColors.backgroundSecondary)
        .cornerRadius(AppSpacing.cornerRadiusCard)
    }
}
