//
//  ModelFamilyViews.swift
//  RunAnywhereAI
//
//  The family-first browsing experience: a clean row card per model family and
//  a detail view that auto-selects the best variant for the device and hides
//  technical backend/variant details behind an "Advanced" disclosure.
//

import SwiftUI
import RunAnywhere

/// One clean, tappable card representing a whole model family in the browse list.
struct ModelFamilyRow: View {
    let family: ModelFamily

    var body: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            Image(systemName: family.category.consumerCapabilityIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppColors.primaryAccent)
                .frame(width: AppSpacing.iconMedium, height: AppSpacing.iconMedium)
                .background(AppColors.primaryAccent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge))

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(family.displayName)
                    .font(AppTypography.subheadlineSemibold)
                    .foregroundColor(AppColors.textPrimary)

                Text(family.tagline)
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)

                HStack(spacing: AppSpacing.xSmall) {
                    if let tag = family.headlineTag {
                        ConsumerBadge(badge: tag)
                    }
                    if family.hasReadyVariant {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.statusGreen)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: AppSpacing.xxSmall) {
                Text("\(family.optionCount) option\(family.optionCount == 1 ? "" : "s")")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
                Image(systemName: "chevron.right")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary.opacity(0.6))
            }
        }
        .padding(.vertical, AppSpacing.smallMedium)
        .contentShape(Rectangle())
    }
}

/// A disabled, informational family row for a modality that isn't downloadable
/// yet (e.g. Apple CoreML image generation). Matches the family-row styling but
/// carries a "Coming soon" pill and no action.
struct ComingSoonFamilyRow: View {
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

/// Family detail: picks the best-fit variant for the device automatically and
/// only reveals per-variant/backend choices under a subtle "Advanced" section.
struct ModelFamilyDetailView: View {
    let family: ModelFamily
    let tier: HardwareTier
    let selectedModelID: String?
    let isLoadingModel: Bool
    let availabilityReason: (RAModelInfo) -> String?
    let handlers: ModelActionHandlers

    /// Best variant for this device: the largest that fits the tier budget,
    /// else the smallest available. `variants` are pre-sorted small → large and
    /// guaranteed non-empty by `ModelFamilyCatalog`.
    private var bestVariant: RAModelInfo {
        family.variants.last {
            $0.consumerSizeBytes <= tier.memoryBudgetBytes && $0.consumerSizeBytes > 0
        } ?? family.variants[0]
    }

    private var otherVariants: [RAModelInfo] {
        family.variants.filter { $0.id != bestVariant.id }
    }

    var body: some View {
        List {
            Section {
                variantRow(bestVariant, highlight: "Best for this device")
            } header: {
                Text("Recommended")
            } footer: {
                Text(family.tagline)
                    .font(AppTypography.caption)
            }

            if !otherVariants.isEmpty {
                Section {
                    DisclosureGroup("Advanced options") {
                        ForEach(otherVariants, id: \.id) { variant in
                            variantRow(variant, highlight: nil)
                        }
                    }
                    .font(AppTypography.subheadline)
                } footer: {
                    Text("Larger options are smarter but use more memory and storage.")
                        .font(AppTypography.caption)
                }
            }
        }
        .navigationTitle(family.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func variantRow(_ variant: RAModelInfo, highlight: String?) -> some View {
        let position = family.variants.firstIndex { $0.id == variant.id } ?? 0
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(alignment: .top, spacing: AppSpacing.mediumLarge) {
                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    if let highlight {
                        Text(highlight.uppercased())
                            .font(AppTypography.caption2Bold)
                            .foregroundColor(AppColors.primaryAccent)
                    }
                    Text(variant.variantFeelLabel(position: position, count: family.variants.count))
                        .font(AppTypography.subheadlineSemibold)
                        .foregroundColor(AppColors.textPrimary)

                    HStack(spacing: AppSpacing.xSmall) {
                        ForEach(variant.consumerTags) { badge in
                            ConsumerBadge(badge: badge)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                variantActions(variant)
            }
        }
        .padding(.vertical, AppSpacing.xSmall)
    }

    @ViewBuilder
    private func variantActions(_ variant: RAModelInfo) -> some View {
        VStack(alignment: .trailing, spacing: AppSpacing.small) {
            ModelPrimaryActionButton(
                model: variant,
                availabilityReason: availabilityReason(variant),
                isSelected: selectedModelID == variant.id,
                isLoadingModel: isLoadingModel,
                onSelectModel: { handlers.onSelect(variant) },
                onChanged: handlers.onChanged
            )

            if let onDelete = handlers.onDelete,
               !variant.isBuiltIn,
               variant.localPathURL != nil,
               availabilityReason(variant) == nil {
                Button {
                    onDelete(variant)
                } label: {
                    Image(systemName: "trash")
                }
                .font(AppTypography.caption)
                .buttonStyle(.bordered)
                .tint(AppColors.primaryRed)
                .controlSize(.small)
                .accessibilityLabel("Delete \(variant.name)")
            }
        }
    }
}
