//
//  ModelDownloadStepView.swift
//  YapRun
//
//  Onboarding step 4: Download the default Whisper Tiny STT model.
//

#if os(iOS)
import SwiftUI

struct ModelDownloadStepView: View {
    let viewModel: OnboardingViewModel
    let onComplete: () -> Void

    @State private var checkmarkVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if viewModel.isModelReady {
                readyContent
            } else if viewModel.isDownloading {
                downloadingContent
            } else {
                initialContent
            }

            Spacer()

            // Bottom action
            if viewModel.isModelReady {
                Button {
                    viewModel.completeOnboarding()
                    onComplete()
                } label: {
                    Text("Start Using YapRun")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.primaryGreen, in: Capsule())
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            } else if !viewModel.isDownloading {
                VStack(spacing: 12) {
                    Button {
                        Task { await viewModel.downloadDefaultModel() }
                    } label: {
                        Text("Download Model")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppColors.textPrimary, in: Capsule())
                    }

                    if viewModel.downloadError != nil {
                        Button {
                            Task { await viewModel.downloadDefaultModel() }
                        } label: {
                            Text("Retry")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppColors.ctaOrange)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            } else {
                Spacer()
                    .frame(height: 100)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isDownloading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isModelReady)
    }

    // MARK: - States

    private var initialContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(AppColors.ctaOrange)

            Text("Download Your Model")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            modelInfoCard

            if let error = viewModel.downloadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AppColors.primaryRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }

    private var downloadingContent: some View {
        VStack(spacing: 24) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(AppColors.cardBorder, lineWidth: 6)
                    .frame(width: 120, height: 120)
                Circle()
                    .trim(from: 0, to: viewModel.downloadProgress)
                    .stroke(AppColors.ctaOrange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))

                Text("\(Int(viewModel.downloadProgress * 100))%")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
            }

            Text(viewModel.downloadStage)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)

            modelInfoCard
        }
    }

    private var readyContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(AppColors.primaryGreen)
                .scaleEffect(checkmarkVisible ? 1.0 : 0.3)
                .opacity(checkmarkVisible ? 1.0 : 0)
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        checkmarkVisible = true
                    }
                }

            Text("You're All Set!")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            Text("Whisper Tiny is ready for on-device transcription.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Components

    private var modelInfoCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundStyle(AppColors.ctaOrange)
                .frame(width: 44, height: 44)
                .background(AppColors.ctaOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Whisper Tiny")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text("English · 75 MB · On-device")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()
        }
        .padding(14)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }
}

#endif
