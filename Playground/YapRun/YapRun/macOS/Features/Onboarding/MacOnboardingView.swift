#if os(macOS)
//
//  MacOnboardingView.swift
//  YapRun
//
//  macOS onboarding: Welcome → Mic → Accessibility → Model Download.
//

import SwiftUI

struct MacOnboardingView: View {
    @State private var viewModel = MacOnboardingViewModel()
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            AppColors.backgroundPrimaryDark.ignoresSafeArea()

            VStack(spacing: 0) {
                // Status indicators (visible after welcome step)
                if viewModel.currentStep != .welcome {
                    statusBar
                        .padding(.top, 12)
                        .padding(.horizontal, 24)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Content
                Group {
                    switch viewModel.currentStep {
                    case .welcome:
                        MacWelcomeStepView(viewModel: viewModel)
                    case .micPermission:
                        MacMicPermissionStepView(viewModel: viewModel)
                    case .accessibility:
                        AccessibilityStepView(viewModel: viewModel)
                    case .modelDownload:
                        MacModelDownloadStepView(viewModel: viewModel, onComplete: onComplete)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)

                // Page indicator
                pageDots
                    .padding(.bottom, 16)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.currentStep)
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.refreshStatus()
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            statusPill(icon: viewModel.micGranted ? "mic.fill" : "mic.slash", label: "Mic", isReady: viewModel.micGranted)
            statusPill(icon: "lock.shield", label: "Access", isReady: viewModel.accessibilityGranted)
            statusPill(icon: "waveform", label: "Model", isReady: viewModel.isModelReady)
        }
    }

    private func statusPill(icon: String, label: String, isReady: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: isReady ? "checkmark.circle.fill" : icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isReady ? AppColors.primaryGreen : AppColors.textTertiary)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isReady ? AppColors.primaryGreen : AppColors.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            (isReady ? AppColors.primaryGreen : Color.white).opacity(0.08),
            in: Capsule()
        )
    }

    // MARK: - Page Dots

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(MacOnboardingViewModel.Step.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step == viewModel.currentStep ? Color.white : Color.white.opacity(0.25))
                    .frame(width: step == viewModel.currentStep ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.currentStep)
            }
        }
    }
}

#endif
