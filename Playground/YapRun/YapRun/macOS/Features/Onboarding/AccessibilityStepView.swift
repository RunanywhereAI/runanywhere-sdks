#if os(macOS)
//
//  AccessibilityStepView.swift
//  YapRun
//
//  macOS onboarding step 3: Guide user to grant Accessibility permission.
//  Required for global hotkey (CGEvent tap) and text insertion (Cmd+V simulation).
//

import SwiftUI

struct AccessibilityStepView: View {
    let viewModel: MacOnboardingViewModel

    @State private var pollingTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(AppColors.ctaOrange)
                .padding(.bottom, 20)

            Text("Accessibility Permission")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            Text("Required for global hotkey and\ntext insertion into other apps.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            if viewModel.accessibilityGranted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.primaryGreen)
                    Text("Accessibility granted")
                        .foregroundStyle(AppColors.primaryGreen)
                }
                .font(.subheadline.weight(.medium))
                .padding(.top, 24)
            } else {
                // Instructions
                VStack(alignment: .leading, spacing: 10) {
                    instructionRow(number: 1, text: "Click \"Open Settings\" below")
                    instructionRow(number: 2, text: "Find YapRun in the list")
                    instructionRow(number: 3, text: "Toggle it ON")
                }
                .padding(.top, 24)
                .padding(.horizontal, 20)
            }

            Spacer()

            if viewModel.accessibilityGranted {
                Button {
                    viewModel.advance()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.primaryGreen, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    viewModel.openAccessibilitySettings()
                } label: {
                    Text("Open Settings")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.ctaOrange, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Button {
                viewModel.advance()
            } label: {
                Text("Skip for now")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.bottom, 40)
        }
        .padding(.horizontal, 60)
        .onAppear { startPolling() }
        .onDisappear { pollingTask?.cancel() }
    }

    // MARK: - Helpers

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 24, height: 24)
                .background(AppColors.textPrimary, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func startPolling() {
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                viewModel.refreshStatus()
            }
        }
    }
}

#endif
