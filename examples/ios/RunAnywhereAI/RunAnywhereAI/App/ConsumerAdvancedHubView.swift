//
//  ConsumerAdvancedHubView.swift
//  RunAnywhereAI
//
//  Secondary voice, performance, and model utilities.
//

import SwiftUI

/// Secondary utilities and agents.
///
/// Every subtitle says what the reader gets, never which model does it. They used to read like
/// release notes — "(NVIDIA Sortformer)", "(SegFormer)", "Fara1.5 reads a screenshot" — and a
/// parenthesised codename is the one thing a reader deciding whether to tap cannot use. The
/// model names live on the screens themselves, where a curious reader has already opted in.
/// Android's `MoreScreen` and the web hub carry the same rewritten copy, so a row means the same
/// thing whichever app it is read in.
struct ConsumerAdvancedHubView: View {
    var body: some View {
        List {
            #if os(macOS)
            Section("Connect") {
                NavigationLink(destination: ConnectHostManagementView()) {
                    AdvancedFeatureRow(
                        icon: "macbook.and.iphone",
                        color: AppColors.primaryAccent,
                        title: "Host this Mac",
                        subtitle: "Share a selected language model with your devices"
                    )
                }
            }
            #endif

            Section("Voice Utilities") {
                NavigationLink(destination: SpeechToTextView()) {
                    AdvancedFeatureRow(
                        icon: "waveform",
                        color: AppColors.primaryBlue,
                        title: "Transcribe",
                        subtitle: "Turn a recording into text"
                    )
                }

                NavigationLink(destination: TextToSpeechView()) {
                    AdvancedFeatureRow(
                        icon: "speaker.wave.2",
                        color: AppColors.statusGreen,
                        title: "Read Aloud",
                        subtitle: "Hear any text spoken on this device"
                    )
                }

                NavigationLink(destination: VoiceActivityDetectionView()) {
                    AdvancedFeatureRow(
                        icon: "waveform.badge.mic",
                        color: .cyan,
                        title: "Voice Activity",
                        subtitle: "See when speech starts and stops"
                    )
                }

                #if canImport(UIKit)
                NavigationLink(destination: DiarizationView()) {
                    AdvancedFeatureRow(
                        icon: "person.2.wave.2",
                        color: AppColors.primaryAccent,
                        title: "Diarization",
                        subtitle: "See who spoke when in a recording"
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
                        subtitle: "Split a photo into labelled regions"
                    )
                }
            }
            #endif

            Section("Agents") {
                NavigationLink(destination: VoiceAssistantView()) {
                    AdvancedFeatureRow(
                        icon: "mic.circle",
                        color: AppColors.primaryAccent,
                        // "Talk", the one name this feature has. Android's drawer row and
                        // the web app's nav row both call it that; this row said "Voice
                        // Assistant" and the web app said "Talk Mode", so one screen had
                        // three names and no reader could tell they were the same thing.
                        title: "Talk",
                        subtitle: "Hands-free voice conversation, all on this device"
                    )
                }

                NavigationLink(destination: ComputerUseAgentView()) {
                    AdvancedFeatureRow(
                        icon: "cursorarrow.rays",
                        color: AppColors.primaryAccent,
                        title: "Computer Use",
                        subtitle: "Let the model read your screen and act on it"
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
                .symbolRenderingMode(.hierarchical)
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
