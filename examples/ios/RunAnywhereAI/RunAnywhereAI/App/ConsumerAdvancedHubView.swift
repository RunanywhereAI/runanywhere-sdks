//
//  ConsumerAdvancedHubView.swift
//  RunAnywhereAI
//
//  Secondary voice, performance, and model utilities.
//

import SwiftUI

struct ConsumerAdvancedHubView: View {
    var body: some View {
        List {
            Section("Voice Utilities") {
                NavigationLink(destination: SpeechToTextView()) {
                    AdvancedFeatureRow(
                        icon: "waveform",
                        color: AppColors.primaryBlue,
                        title: "Transcribe",
                        subtitle: "Speech-to-text utility"
                    )
                }

                NavigationLink(destination: TextToSpeechView()) {
                    AdvancedFeatureRow(
                        icon: "speaker.wave.2",
                        color: AppColors.statusGreen,
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

                #if canImport(UIKit)
                NavigationLink(destination: DiarizationView()) {
                    AdvancedFeatureRow(
                        icon: "person.2.wave.2",
                        color: AppColors.primaryAccent,
                        title: "Diarization",
                        subtitle: "Who spoke when (NVIDIA Sortformer)"
                    )
                }
                #endif
            }

            #if canImport(UIKit)
            Section("Vision Utilities") {
                NavigationLink(destination: SegmentationView()) {
                    AdvancedFeatureRow(
                        icon: "square.stack.3d.up",
                        color: AppColors.primaryAccent,
                        title: "Segmentation",
                        subtitle: "Semantic image segmentation (SegFormer)"
                    )
                }
            }
            #endif

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
