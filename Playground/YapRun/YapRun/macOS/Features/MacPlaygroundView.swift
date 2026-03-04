#if os(macOS)
//
//  MacPlaygroundView.swift
//  YapRun
//
//  macOS ASR testing playground — record audio and transcribe on-device.
//

import SwiftUI

struct MacPlaygroundView: View {
    @State private var viewModel = PlaygroundViewModel()

    var body: some View {
        ZStack {
            AppColors.backgroundPrimaryDark.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, 16)
                    .padding(.horizontal, 24)

                Spacer()

                centerContent

                Spacer()

                resultSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }

            if viewModel.modelName == nil && !viewModel.isRecording && !viewModel.isTranscribing {
                noModelOverlay
            }
        }
        .task { await viewModel.checkModelStatus() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Text("ASR Playground")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            if let name = viewModel.modelName {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.primaryGreen)
                    Text(name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColors.primaryGreen)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppColors.primaryGreen.opacity(0.1), in: Capsule())
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text("No model loaded")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1), in: Capsule())
            }
        }
    }

    // MARK: - Center

    private var centerContent: some View {
        VStack(spacing: 24) {
            if viewModel.isTranscribing {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(AppColors.ctaOrange)
                        .scaleEffect(1.5)
                    Text("Transcribing...")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
            } else {
                // Mic button
                Button {
                    Task { await viewModel.toggleRecording() }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(
                                viewModel.isRecording ? Color.red.opacity(0.3) : Color.primary.opacity(0.15),
                                lineWidth: 3
                            )
                            .frame(width: 100, height: 100)

                        Circle()
                            .fill(viewModel.isRecording ? Color.red : Color.primary.opacity(0.08))
                            .frame(width: 88, height: 88)

                        Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(viewModel.isRecording ? .white : AppColors.textPrimary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.modelName == nil)

                if viewModel.isRecording {
                    VStack(spacing: 12) {
                        Text(formatTime(viewModel.elapsedSeconds))
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.red)

                        MacWaveformBars(level: viewModel.audioLevel)
                    }
                } else {
                    Text(viewModel.transcription.isEmpty ? "Click to record" : "Click to record again")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
    }

    // MARK: - Result

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !viewModel.transcription.isEmpty {
                HStack {
                    Text("Result")
                        .font(.headline)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    Button {
                        ClipboardService.copyText(viewModel.transcription)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.clear()
                    } label: {
                        Label("Clear", systemImage: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    Text(viewModel.transcription)
                        .font(.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(14)
                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.cardBorder, lineWidth: 1)
                )
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AppColors.primaryRed)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - No Model Overlay

    private var noModelOverlay: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(AppColors.textTertiary)
            Text("No STT model loaded")
                .font(.headline)
                .foregroundStyle(AppColors.textSecondary)
            Text("Download and load a model from the Home tab to start testing.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimaryDark.opacity(0.85))
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Waveform Bars

private struct MacWaveformBars: View {
    let level: Float

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red.opacity(0.8))
                    .frame(width: 4, height: barHeight(for: index))
                    .animation(.easeInOut(duration: 0.1), value: level)
            }
        }
        .frame(height: 40)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let center = 3.0
        let distance = abs(Double(index) - center)
        let base: CGFloat = 6
        let scale = CGFloat(max(0.2, Double(level) * (1.0 - distance * 0.15)))
        return base + scale * 34
    }
}

#endif
