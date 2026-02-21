#if os(macOS)
//
//  MacMicPermissionStepView.swift
//  YapRun
//
//  macOS onboarding step 2: Request microphone permission via AVCaptureDevice.
//

import SwiftUI

struct MacMicPermissionStepView: View {
    let viewModel: MacOnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(AppColors.ctaOrange)
                .padding(.bottom, 20)

            Text("Microphone Access")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            Text("YapRun needs your microphone for\non-device voice dictation.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            if viewModel.micGranted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.primaryGreen)
                    Text("Microphone access granted")
                        .foregroundStyle(AppColors.primaryGreen)
                }
                .font(.subheadline.weight(.medium))
                .padding(.top, 24)
            }

            Spacer()

            if viewModel.micGranted {
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
                    Task { await viewModel.requestMicPermission() }
                } label: {
                    Text("Allow Microphone")
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
    }
}

#endif
