//
//  KeyboardSetupStepView.swift
//  YapRun
//
//  Onboarding step 3: Guide user to add the YapRun keyboard.
//  Detects Full Access via App Group UserDefaults and auto-advances.
//

#if os(iOS)
import SwiftUI

struct KeyboardSetupStepView: View {
    let viewModel: OnboardingViewModel

    private let steps: [(icon: String, title: String, detail: String)] = [
        ("gear", "Open Settings", "Tap the button below to open Settings."),
        ("keyboard", "Add YapRun Keyboard", "General → Keyboard → Keyboards → Add New Keyboard → YapRun."),
        ("lock.open", "Grant Full Access", "Tap YapRun → enable 'Allow Full Access' for mic and App Group IPC.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Header icon
            ZStack {
                Circle()
                    .fill((viewModel.keyboardReady ? AppColors.primaryGreen : AppColors.ctaOrange).opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: viewModel.keyboardReady ? "checkmark.circle.fill" : "keyboard.badge.ellipsis")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(viewModel.keyboardReady ? AppColors.primaryGreen : AppColors.ctaOrange)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.bottom, 24)

            Text(viewModel.keyboardReady ? "Keyboard Ready!" : "Add the Keyboard")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.bottom, 8)

            Text(viewModel.keyboardReady
                 ? "YapRun keyboard is installed with Full Access."
                 : "Three quick steps to start dictating anywhere.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 32)

            if !viewModel.keyboardReady {
                // Steps card
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.black)
                                .frame(width: 26, height: 26)
                                .background(AppColors.ctaOrange, in: Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                Text(step.detail)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textTertiary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 12)

                        if index < steps.count - 1 {
                            Divider()
                                .background(AppColors.cardBorder)
                        }
                    }
                }
                .padding(16)
                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.cardBorder, lineWidth: 1)
                )
                .padding(.horizontal, 24)
            }

            Spacer()

            // Actions
            VStack(spacing: 12) {
                if viewModel.keyboardReady {
                    Button {
                        viewModel.advance()
                    } label: {
                        Label("Continue", systemImage: "arrow.right")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppColors.primaryGreen, in: Capsule())
                    }
                } else {
                    Button {
                        viewModel.openKeyboardSettings()
                    } label: {
                        Label("Open Settings", systemImage: "arrow.up.forward.app")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppColors.textPrimary, in: Capsule())
                    }

                    Button {
                        viewModel.advance()
                    } label: {
                        Text("I've done this — Continue")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.keyboardReady)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            viewModel.checkKeyboardStatus()
        }
    }
}

#endif
