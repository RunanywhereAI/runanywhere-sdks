//
//  BenchmarkShareCardView.swift
//  RunAnywhereAI
//
//  Branded, shareable benchmark result card + the share sheet that rasterizes it
//  (via ImageRenderer) and hands it to Instagram / X / the system share sheet on
//  iOS, or NSSharingServicePicker-backed ShareLink on macOS. Mirrors the Android
//  share card for visual parity.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Card

/// The branded card. Fixed 9:16 (Stories-friendly) so the captured PNG drops
/// cleanly into Instagram / X without awkward cropping.
struct BenchmarkShareCardView: View {
    let data: ShareCardData

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.shareCardStackSpacing) {
            header
            Spacer(minLength: AppSpacing.shareCardHeaderToHero)
            hero
            Spacer(minLength: AppSpacing.shareCardHeroToRows)
            rows
            Spacer(minLength: AppSpacing.shareCardRowsToFooter)
            footer
        }
        .padding(.horizontal, AppSpacing.shareCardHorizontalPadding)
        .padding(.vertical, AppSpacing.shareCardVerticalPadding)
        .frame(
            width: AdaptiveSizing.shareCardWidth,
            height: AdaptiveSizing.shareCardWidth / AppLayout.shareCardAspectRatio,
            alignment: .topLeading
        )
        .background(
            LinearGradient(
                colors: [AppColors.shareCardBackgroundTop, AppColors.shareCardBackgroundBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.shareCardCornerRadius))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.shareCardHeaderSpacing) {
            HStack(spacing: AppSpacing.shareCardBrandSpacing) {
                Image("runanywhere_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: AppLayout.shareCardLogoSize, height: AppLayout.shareCardLogoSize)
                Text("RunAnywhere")
                    .font(AppTypography.shareCardBrand)
                    .foregroundColor(AppColors.shareCardTextPrimary)
            }
            Text(data.modalityLabel)
                .font(AppTypography.shareCardModality)
                .tracking(AppTypography.shareCardModalityTracking)
                .foregroundColor(AppColors.shareCardAccent)
        }
    }

    @ViewBuilder private var hero: some View {
        if let hero = data.hero {
            VStack(alignment: .leading, spacing: AppSpacing.shareCardHeroSpacing) {
                HStack(alignment: .bottom, spacing: AppSpacing.shareCardHeroMetricSpacing) {
                    Text(hero.value)
                        .font(AppTypography.shareCardHeroValue)
                        .foregroundColor(AppColors.shareCardAccent)
                    Text(hero.label)
                        .font(AppTypography.shareCardHeroLabel)
                        .foregroundColor(AppColors.shareCardTextSecondary)
                        .padding(.bottom, AppSpacing.shareCardHeroMetricSpacing)
                }
                if !data.heroCaption.isEmpty {
                    Text(data.heroCaption)
                        .font(AppTypography.shareCardHeroCaption)
                        .foregroundColor(AppColors.shareCardTextPrimary)
                        .lineLimit(AppLayout.shareCardSingleLineLimit)
                }
                if let secondary = data.heroSecondary {
                    Text("\(secondary.value) \(secondary.label)")
                        .font(AppTypography.shareCardSupporting)
                        .foregroundColor(AppColors.shareCardTextSecondary)
                }
            }
        }
    }

    @ViewBuilder private var rows: some View {
        // Only additional models (beyond the hero) appear here — never a duplicate.
        if !data.rows.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.shareCardRowsSpacing) {
                Text("ALSO TESTED")
                    .font(AppTypography.shareCardSection)
                    .tracking(AppTypography.shareCardSectionTracking)
                    .foregroundColor(AppColors.shareCardTextSecondary)
                ForEach(data.rows) { row in
                    ShareRowView(row: row)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: AppSpacing.shareCardFooterSpacing) {
            Text(data.deviceLine)
                .font(AppTypography.shareCardHeroCaption)
                .foregroundColor(AppColors.shareCardTextPrimary)
                .lineLimit(AppLayout.shareCardSingleLineLimit)
            HStack {
                Text("runanywhere.ai")
                    .font(AppTypography.shareCardModality)
                    .foregroundColor(AppColors.shareCardAccent)
                Spacer()
                Text(data.dateLine)
                    .font(AppTypography.shareCardSupporting)
                    .foregroundColor(AppColors.shareCardTextSecondary)
            }
        }
    }
}

private struct ShareRowView: View {
    let row: ShareCardRow

    var body: some View {
        HStack(spacing: AppSpacing.shareCardRowContentSpacing) {
            VStack(alignment: .leading, spacing: AppSpacing.shareCardRowTextSpacing) {
                Text(row.model)
                    .font(AppTypography.shareCardRowTitle)
                    .foregroundColor(AppColors.shareCardTextPrimary)
                    .lineLimit(AppLayout.shareCardSingleLineLimit)
                Text(row.framework)
                    .font(AppTypography.shareCardRowSubtitle)
                    .foregroundColor(AppColors.shareCardTextSecondary)
                    .lineLimit(AppLayout.shareCardSingleLineLimit)
            }
            Spacer(minLength: AppSpacing.shareCardRowMetricSpacing)
            ForEach(row.metrics) { metric in
                VStack(alignment: .trailing, spacing: AppSpacing.shareCardRowTextSpacing) {
                    Text(metric.value)
                        .font(AppTypography.shareCardMetricValue)
                        .foregroundColor(AppColors.shareCardTextPrimary)
                    Text(metric.label)
                        .font(AppTypography.shareCardMetricLabel)
                        .foregroundColor(AppColors.shareCardTextSecondary)
                }
            }
        }
        .padding(.horizontal, AppSpacing.shareCardRowHorizontalPadding)
        .padding(.vertical, AppSpacing.shareCardRowVerticalPadding)
        .background(AppColors.shareCardRowBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppSpacing.shareCardRowCornerRadius))
    }
}

// MARK: - Share Sheet

/// Presents the card preview and shares it as a PNG. What the user sees is exactly
/// what gets shared (the same card view is both previewed and rasterized).
struct BenchmarkShareSheet: View {
    let run: BenchmarkRun

    @Environment(\.dismiss)
    private var dismiss
    @State private var shareModel = BenchmarkShareViewModel()

    var body: some View {
        VStack(spacing: 20) {
            if let data = shareModel.data {
                // Modality selector — only when the run spans more than one modality.
                if shareModel.modalities.count > 1 {
                    Picker("Modality", selection: Binding(
                        get: { shareModel.selectedCategory ?? shareModel.modalities[0] },
                        set: shareModel.selectCategory
                    )) {
                        ForEach(shareModel.modalities) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                BenchmarkShareCardView(data: data)
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 8)

                targets
            } else {
                Text("No successful benchmarks to share yet. Run a benchmark first.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 40)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .task { shareModel.prepare(run: run) }
        .alert(
            "Unable to Share",
            isPresented: Binding(
                get: { shareModel.error != nil },
                set: { if !$0 { shareModel.dismissError() } }
            )
        ) {
            Button("OK") { shareModel.dismissError() }
        } message: {
            if let error = shareModel.error {
                Text(error.message)
            }
        }
    }

    @ViewBuilder private var targets: some View {
        switch shareModel.renderState {
        case .idle:
            EmptyView()
        case .rendering:
            ProgressView("Preparing share image…")
        case let .failed(error):
            VStack(spacing: AppSpacing.smallMedium) {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.statusOrange)
                    .multilineTextAlignment(.center)
                Button("Retry") { shareModel.retryRendering() }
            }
        case .ready:
            readyTargets
        }
    }

    @ViewBuilder private var readyTargets: some View {
        #if canImport(UIKit)
        HStack(spacing: 12) {
            if shareModel.availability(for: .instagram) == .available {
                directShareButton(.instagram, systemImage: "camera.circle")
            }
            if shareModel.availability(for: .x) == .available {
                directShareButton(.x, systemImage: "at.circle")
            }
            if let image = shareModel.renderedImage {
                ShareLink(
                    item: Image(uiImage: image),
                    message: Text(shareModel.caption),
                    preview: SharePreview("RunAnywhere Benchmark", image: Image(uiImage: image))
                ) {
                    labelPill("More", systemImage: "square.and.arrow.up")
                }
            }
        }
        #elseif canImport(AppKit)
        if let image = shareModel.renderedImage {
            ShareLink(
                item: Image(nsImage: image),
                message: Text(shareModel.caption),
                preview: SharePreview("RunAnywhere Benchmark", image: Image(nsImage: image))
            ) {
                labelPill("Share…", systemImage: "square.and.arrow.up")
            }
        }
        #endif
    }

    #if canImport(UIKit)
    private func directShareButton(_ target: BenchmarkShareTarget, systemImage: String) -> some View {
        Button {
            shareModel.share(to: target)
        } label: {
            if shareModel.activeTarget == target {
                ProgressView()
            } else {
                labelPill(target.displayName, systemImage: systemImage)
            }
        }
            .buttonStyle(.plain)
            .disabled(shareModel.activeTarget != nil)
    }
    #endif

    private func labelPill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
    }
}
