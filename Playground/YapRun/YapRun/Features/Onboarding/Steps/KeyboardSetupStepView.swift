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

    private var headerColor: Color {
        viewModel.keyboardReady ? AppColors.primaryGreen : AppColors.ctaOrange
    }

    private var headerTitle: String {
        if viewModel.keyboardReady {
            return "Keyboard Ready!"
        } else if viewModel.keyboardEnabled {
            return "Almost There"
        } else {
            return "Add the Keyboard"
        }
    }

    private var headerSubtitle: String {
        if viewModel.keyboardReady {
            return "YapRun keyboard is installed with Full Access."
        } else if viewModel.keyboardEnabled {
            return "Enable Full Access so YapRun can use the microphone."
        } else {
            return "Two quick steps to start dictating anywhere."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Header icon
            ZStack {
                Circle()
                    .fill(headerColor.opacity(0.15))
                    .frame(width: 100, height: 100)
                Image(systemName: viewModel.keyboardReady ? "checkmark.circle.fill" : "keyboard.badge.ellipsis")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(headerColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.bottom, 24)

            Text(headerTitle)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.bottom, 8)

            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 32)

            if !viewModel.keyboardReady {
                // Granular steps card with live checkmarks
                VStack(spacing: 0) {
                    // Step 1: Add Keyboard
                    stepRow(
                        number: 1,
                        icon: "keyboard",
                        title: "Add YapRun Keyboard",
                        detail: "Settings → General → Keyboard → Keyboards → Add New Keyboard → YapRun.",
                        isComplete: viewModel.keyboardEnabled
                    )

                    Divider().background(AppColors.cardBorder)

                    // Step 2: Enable Full Access
                    stepRow(
                        number: 2,
                        icon: "lock.open",
                        title: "Enable Full Access",
                        detail: "Settings → General → Keyboard → Keyboards → YapRun → Allow Full Access.",
                        isComplete: viewModel.keyboardFullAccess
                    )
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
                            .background(AppColors.ctaOrange, in: Capsule())
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
        .animation(.easeInOut(duration: 0.3), value: viewModel.keyboardEnabled)
        .animation(.easeInOut(duration: 0.3), value: viewModel.keyboardFullAccess)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            viewModel.checkKeyboardStatus()
        }
    }

    // MARK: - Step Row

    private func stepRow(
        number: Int,
        icon: String,
        title: String,
        detail: String,
        isComplete: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(AppColors.primaryGreen)
                    .frame(width: 26, height: 26)
            } else {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 26, height: 26)
                    .background(AppColors.ctaOrange, in: Circle())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isComplete ? AppColors.textTertiary : AppColors.textPrimary)
                    .strikethrough(isComplete)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()
        }
        .padding(.vertical, 12)
    }
}

#endif
