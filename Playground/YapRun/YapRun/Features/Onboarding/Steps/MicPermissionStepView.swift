//
//  MicPermissionStepView.swift
//  YapRun
//
//  Onboarding step 2: Request microphone permission.
//

#if os(iOS)
import SwiftUI

struct MicPermissionStepView: View {
    let viewModel: OnboardingViewModel

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(AppColors.ctaOrange.opacity(0.15))
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(AppColors.ctaOrange.opacity(0.08))
                    .frame(width: 160, height: 160)
                Image(systemName: viewModel.micGranted ? "checkmark.circle.fill" : "mic.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(viewModel.micGranted ? AppColors.primaryGreen : AppColors.ctaOrange)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.bottom, 32)

            Text("Microphone Access")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.bottom, 12)

            Text("YapRun transcribes your voice entirely on-device.\nNo audio ever leaves your phone.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            // Action
            if viewModel.micGranted {
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
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                VStack(spacing: 12) {
                    Button {
                        Task { await viewModel.requestMicPermission() }
                    } label: {
                        Text("Allow Microphone")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppColors.ctaOrange, in: Capsule())
                    }

                    Button {
                        viewModel.advance()
                    } label: {
                        Text("Skip for now")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.micGranted)
        .onAppear {
            appeared = true
            viewModel.refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            viewModel.refreshStatus()
        }
    }
}

#endif
