//
//  OnboardingView.swift
//  YapRun
//
//  Paged onboarding container shown on first launch.
//  Steps: Welcome → Mic Permission → Keyboard Setup → Model Download.
//  Shows a persistent status bar with mic/keyboard/model indicators.
//

#if os(iOS)
import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            AppColors.backgroundPrimaryDark.ignoresSafeArea()

            VStack(spacing: 0) {
                // Status indicators (visible after welcome step)
                if viewModel.currentStep != .welcome {
                    statusBar
                        .padding(.top, 8)
                        .padding(.horizontal, 24)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                TabView(selection: $viewModel.currentStep) {
                    WelcomeStepView(viewModel: viewModel)
                        .tag(OnboardingViewModel.Step.welcome)

                    MicPermissionStepView(viewModel: viewModel)
                        .tag(OnboardingViewModel.Step.micPermission)

                    KeyboardSetupStepView(viewModel: viewModel)
                        .tag(OnboardingViewModel.Step.keyboardSetup)

                    ModelDownloadStepView(viewModel: viewModel, onComplete: onComplete)
                        .tag(OnboardingViewModel.Step.modelDownload)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)
            }

            // Page indicator
            VStack {
                Spacer()
                PageDotIndicator(current: viewModel.currentStep)
                    .padding(.bottom, 16)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.currentStep)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            viewModel.refreshStatus()
        }
        .onAppear {
            viewModel.refreshStatus()
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            statusPill(
                icon: viewModel.micGranted ? "mic.fill" : "mic.slash",
                label: "Mic",
                isReady: viewModel.micGranted
            )

            statusPill(
                icon: "keyboard",
                label: "Keyboard",
                isReady: viewModel.keyboardReady
            )

            statusPill(
                icon: "waveform",
                label: "Model",
                isReady: viewModel.isModelReady
            )
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
}

// MARK: - Page Indicator

private struct PageDotIndicator: View {
    let current: OnboardingViewModel.Step

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingViewModel.Step.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step == current ? Color.white : Color.white.opacity(0.25))
                    .frame(width: step == current ? 24 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: current)
            }
        }
    }
}

#endif
