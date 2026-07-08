//
//  ModelSelectionRows.swift
//  RunAnywhereAI
//
//  Shared overlay for the model selection sheet. Row rendering now uses the
//  family-first components (ModelFamilyRow / ModelVariantRow).
//

import SwiftUI
import RunAnywhere

// MARK: - Loading Model Overlay

struct LoadingModelOverlay: View {
    let loadingProgress: String

    var body: some View {
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
}
