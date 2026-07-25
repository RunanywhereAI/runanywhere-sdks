//
//  ModelOrgViews.swift
//  RunAnywhereAI
//
//  Organisation-first browsing: one card per publisher (NVIDIA, Meta, …)
//  and a detail list of every model that org ships in the current modality.
//

import SwiftUI
import RunAnywhere

/// One clean, tappable card representing an organisation in the browse list.
struct ModelOrgRow: View {
    let group: ModelOrgGroup

    var body: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            Image(systemName: group.org.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppColors.primaryAccent)
                .frame(width: AppSpacing.iconMedium, height: AppSpacing.iconMedium)
                .background(AppColors.primaryAccent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge))

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(group.displayName)
                    .font(AppTypography.subheadlineSemibold)
                    .foregroundColor(AppColors.textPrimary)

                HStack(spacing: AppSpacing.xSmall) {
                    if group.hasNpuVariant {
                        Text("NPU")
                            .font(AppTypography.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(AppColors.primaryAccent)
                            .padding(.horizontal, AppSpacing.small)
                            .padding(.vertical, AppSpacing.xxSmall)
                            .background(AppColors.primaryAccent.opacity(0.12))
                            .cornerRadius(AppSpacing.cornerRadiusSmall)
                    }
                    if group.hasReadyVariant {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.statusGreen)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(group.optionCount) model\(group.optionCount == 1 ? "" : "s")")
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.vertical, AppSpacing.smallMedium)
        .contentShape(Rectangle())
    }
}

/// Informational row for a modality that isn't downloadable yet.
struct ComingSoonOrgRow: View {
    let title: String
    let tagline: String
    let systemImage: String

    var body: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppColors.textSecondary)
                .frame(width: AppSpacing.iconMedium, height: AppSpacing.iconMedium)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge))

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(title)
                    .font(AppTypography.subheadlineSemibold)
                    .foregroundColor(AppColors.textPrimary)
                Text(tagline)
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Coming soon")
                .font(AppTypography.caption2)
                .fontWeight(.medium)
                .foregroundColor(AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.small)
                .padding(.vertical, AppSpacing.xxSmall)
                .background(AppColors.backgroundSecondary)
                .cornerRadius(AppSpacing.cornerRadiusSmall)
        }
        .padding(.vertical, AppSpacing.smallMedium)
        .opacity(0.85)
    }
}

/// One model of an organisation: clean human name, download size, subtle
/// backend pill, ≤2 consumer tags, and the feel descriptor as secondary text.
struct ModelVariantRow: View {
    let variant: RAModelInfo
    var feelDescriptor: String?
    var highlight: String?
    let availabilityReason: String?
    let isSelected: Bool
    let isLoadingModel: Bool
    let handlers: ModelActionHandlers

    private var displayTags: [ModelCapabilityBadge] {
        feelDescriptor != nil ? variant.consumerCapabilityTags : variant.consumerTags
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.mediumLarge) {
            VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                if let highlight {
                    Text(highlight.uppercased())
                        .font(AppTypography.caption2Bold)
                        .foregroundColor(AppColors.primaryAccent)
                }

                Text(variant.consumerDisplayName)
                    .font(AppTypography.subheadlineSemibold)
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: AppSpacing.smallMedium) {
                    Text(variant.consumerSizeLabel)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                    BackendPill(framework: variant.framework)
                    if let feelDescriptor {
                        Text(feelDescriptor)
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                if !displayTags.isEmpty {
                    HStack(spacing: AppSpacing.xSmall) {
                        ForEach(displayTags) { badge in
                            ConsumerBadge(badge: badge)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions
        }
        .padding(.vertical, AppSpacing.smallMedium)
    }

    @ViewBuilder private var actions: some View {
        VStack(alignment: .trailing, spacing: AppSpacing.small) {
            ModelPrimaryActionButton(
                model: variant,
                availabilityReason: availabilityReason,
                isSelected: isSelected,
                isLoadingModel: isLoadingModel,
                onSelectModel: { handlers.onSelect(variant) },
                onChanged: handlers.onChanged
            )

            if let onDelete = handlers.onDelete,
               !variant.isBuiltIn,
               variant.localPathURL != nil,
               availabilityReason == nil {
                Button {
                    onDelete(variant)
                } label: {
                    Image(systemName: "trash")
                }
                .font(AppTypography.caption)
                .buttonStyle(.bordered)
                .tint(AppColors.primaryRed)
                .controlSize(.small)
                .accessibilityLabel("Delete \(variant.consumerDisplayName)")
            }
        }
    }
}

/// Org detail: recommended best-fit up top, every other model below.
struct ModelOrgDetailView: View {
    let group: ModelOrgGroup
    let tier: HardwareTier
    let selectedModelID: String?
    let isLoadingModel: Bool
    let availabilityReason: (RAModelInfo) -> String?
    let handlers: ModelActionHandlers

    private var bestVariant: RAModelInfo {
        group.models.last {
            $0.consumerSizeBytes <= tier.memoryBudgetBytes && $0.consumerSizeBytes > 0
        } ?? group.models[0]
    }

    private var otherVariants: [RAModelInfo] {
        group.models.filter { $0.id != bestVariant.id }
    }

    var body: some View {
        List {
            Section {
                row(for: bestVariant, highlight: "Best for this device")
            } header: {
                Text("Recommended")
            } footer: {
                Text("Models from \(group.displayName)")
                    .font(AppTypography.caption)
            }

            if !otherVariants.isEmpty {
                Section {
                    ForEach(otherVariants, id: \.id) { variant in
                        row(for: variant, highlight: nil)
                    }
                } header: {
                    Text("All models")
                } footer: {
                    Text("Larger options are smarter but use more memory and storage.")
                        .font(AppTypography.caption)
                }
            }
        }
        .navigationTitle(group.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func row(for variant: RAModelInfo, highlight: String?) -> some View {
        let position = group.models.firstIndex { $0.id == variant.id } ?? 0
        return ModelVariantRow(
            variant: variant,
            feelDescriptor: group.models.count > 1
                ? variant.variantFeelLabel(position: position, count: group.models.count)
                : nil,
            highlight: highlight,
            availabilityReason: availabilityReason(variant),
            isSelected: selectedModelID == variant.id,
            isLoadingModel: isLoadingModel,
            handlers: handlers
        )
    }
}
