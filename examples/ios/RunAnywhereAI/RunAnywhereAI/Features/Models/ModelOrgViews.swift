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

                // A size and a backend name are single tokens, so they hold their
                // width; the feel descriptor is the one part that may truncate.
                // Left to wrap, a download in progress squeezes this row and
                // SwiftUI hyphenates mid-word — "762.9 / MB" — which reads as
                // broken rather than as a compact row.
                HStack(spacing: AppSpacing.smallMedium) {
                    Text(variant.consumerSizeLabel)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: true, vertical: false)
                    BackendPill(framework: variant.framework)
                    if let feelDescriptor {
                        Text(feelDescriptor)
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
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
///
/// Takes the org and the set of model ids the browse list decided to show —
/// never a captured `ModelOrgGroup`. A `ModelOrgGroup` holds `RAModelInfo`
/// *values*, and a value captured when the link was pushed still says
/// `localPathURL == nil` after the download it started has finished, so every
/// row kept offering "Get" for a model already fully on disk. The membership is
/// stable (a download does not change a model's id) so it is safe to snapshot,
/// while the readiness of each model is re-read from the live registry on every
/// body evaluation.
struct ModelOrgDetailView: View {
    let org: ModelOrg
    /// Ids the caller's filters admitted, snapshotted at push time.
    let visibleModelIDs: Set<String>
    /// Commons `can_run` by model id when the SDK returned a verdict; absent
    /// ids are not filtered by a local size budget.
    var canRunByModelID: [String: Bool] = [:]
    /// The model the *caller's* picker considers active. Each picker scopes this
    /// differently (chat model, vision model, embedding model), so it stays a
    /// caller decision rather than being read from the registry here.
    let selectedModelID: String?
    let isLoadingModel: Bool
    let availabilityReason: (RAModelInfo) -> String?
    let handlers: ModelActionHandlers

    @ObservedObject private var models = ModelListViewModel.shared

    /// The org's models as the registry has them *now*.
    private var variants: [RAModelInfo] {
        ModelOrgCatalog.groups(
            from: models.availableModels.filter { visibleModelIDs.contains($0.id) }
        )
        .first { $0.org == org }?.models ?? []
    }

    private func bestVariant(in variants: [RAModelInfo]) -> RAModelInfo? {
        if !canRunByModelID.isEmpty {
            return variants.last { canRunByModelID[$0.id] == true } ?? variants.first
        }
        // No typed compatibility map — do not invent a local byte budget.
        return variants.first
    }

    private var recommendedHighlight: String? {
        canRunByModelID.isEmpty ? nil : "Compatible with this device"
    }

    var body: some View {
        let variants = variants
        let best = bestVariant(in: variants)
        let others = variants.filter { $0.id != best?.id }

        List {
            if let best {
                Section {
                    row(for: best, in: variants, highlight: recommendedHighlight)
                } header: {
                    Text("Recommended")
                } footer: {
                    Text("Models from \(org.displayName)")
                        .font(AppTypography.caption)
                }
            }

            if !others.isEmpty {
                Section {
                    ForEach(others, id: \.id) { variant in
                        row(for: variant, in: variants, highlight: nil)
                    }
                } header: {
                    Text("All models")
                } footer: {
                    Text("Larger options are smarter but use more memory and storage.")
                        .font(AppTypography.caption)
                }
            }

            // Every model this org shipped has been deleted while the page was
            // open. Saying so beats an empty list that reads as a load failure.
            if variants.isEmpty {
                Section {
                    Text("No \(org.displayName) models are available any more.")
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .navigationTitle(org.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func row(
        for variant: RAModelInfo,
        in variants: [RAModelInfo],
        highlight: String?
    ) -> some View {
        let position = variants.firstIndex { $0.id == variant.id } ?? 0
        return ModelVariantRow(
            variant: variant,
            feelDescriptor: variants.count > 1
                ? variant.variantFeelLabel(position: position, count: variants.count)
                : nil,
            highlight: highlight,
            availabilityReason: availabilityReason(variant),
            isSelected: selectedModelID == variant.id,
            isLoadingModel: isLoadingModel,
            handlers: handlers
        )
    }
}
