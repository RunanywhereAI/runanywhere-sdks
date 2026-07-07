//
//  ConsumerAdvancedHubView.swift
//  RunAnywhereAI
//
//  Secondary SDK demos and developer-oriented utilities moved out of the main face.
//

import SwiftUI

struct ConsumerAdvancedHubView: View {
    var body: some View {
        List {
            Section("Voice Utilities") {
                NavigationLink(destination: SpeechToTextView()) {
                    AdvancedFeatureRow(
                        icon: "waveform",
                        color: .blue,
                        title: "Transcribe",
                        subtitle: "Speech-to-text utility"
                    )
                }

                NavigationLink(destination: TextToSpeechView()) {
                    AdvancedFeatureRow(
                        icon: "speaker.wave.2",
                        color: .green,
                        title: "Read Aloud",
                        subtitle: "Text-to-speech utility"
                    )
                }

                NavigationLink(destination: VoiceActivityDetectionView()) {
                    AdvancedFeatureRow(
                        icon: "waveform.badge.mic",
                        color: .cyan,
                        title: "Voice Activity",
                        subtitle: "Speech/silence diagnostics"
                    )
                }
            }

            Section {
                NavigationLink(destination: BenchmarkDashboardView()) {
                    AdvancedFeatureRow(
                        icon: "gauge.with.dots.needle.33percent",
                        color: AppColors.statusBlue,
                        title: "Benchmarks",
                        subtitle: "Measure local model performance"
                    )
                }
            } header: {
                Text("Management")
            } footer: {
                Text("Storage and tool calling live in Settings and Manage Models.")
            }
        }
        .navigationTitle("Advanced")
        #if os(iOS)
        .navigationBarTitleDisplayModeCompat(.inline)
        #endif
    }
}

private struct AdvancedFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .cornerRadius(AppSpacing.cornerRadiusRegular)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.subheadlineMedium)
                    .foregroundColor(AppColors.textPrimary)
                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, AppSpacing.small)
    }
}
