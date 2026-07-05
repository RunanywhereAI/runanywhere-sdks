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
            Section {
                NavigationLink(destination: DocumentRAGView()) {
                    AdvancedFeatureRow(
                        icon: "doc.text.magnifyingglass",
                        color: .indigo,
                        title: "Document Q&A",
                        subtitle: "Ask questions over imported documents"
                    )
                }

                NavigationLink(destination: VLMCameraView()) {
                    AdvancedFeatureRow(
                        icon: "camera.viewfinder",
                        color: .purple,
                        title: "Vision Workbench",
                        subtitle: "Camera, photo, and live image understanding"
                    )
                }

                NavigationLink(destination: VoiceAssistantView()) {
                    AdvancedFeatureRow(
                        icon: "mic.circle",
                        color: AppColors.primaryAccent,
                        title: "Talk Mode",
                        subtitle: "Full STT + LLM + TTS voice assistant"
                    )
                }
            } header: {
                Text("Assistant Modes")
            } footer: {
                Text("These are the same capabilities available from the home composer, kept here for direct access.")
            }

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
                NavigationLink(destination: StorageView()) {
                    AdvancedFeatureRow(
                        icon: "externaldrive",
                        color: .orange,
                        title: "Storage",
                        subtitle: "Models, cache, and local files"
                    )
                }

                NavigationLink(destination: BenchmarkDashboardView()) {
                    AdvancedFeatureRow(
                        icon: "gauge.with.dots.needle.33percent",
                        color: AppColors.statusBlue,
                        title: "Benchmarks",
                        subtitle: "Measure local model performance"
                    )
                }

                NavigationLink(destination: ToolCallingAdvancedView()) {
                    AdvancedFeatureRow(
                        icon: "wrench.and.screwdriver",
                        color: AppColors.primaryPurple,
                        title: "Tool Calling",
                        subtitle: "Register demo tools for the chat model"
                    )
                }

                #if os(iOS)
                NavigationLink(destination: VoiceDictationManagementView()) {
                    AdvancedFeatureRow(
                        icon: "keyboard",
                        color: .indigo,
                        title: "Voice Keyboard",
                        subtitle: "Private dictation in other apps"
                    )
                }
                #endif
            } header: {
                Text("Management")
            } footer: {
                Text("Advanced tools stay available without competing with the main assistant experience.")
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

private struct ToolCallingAdvancedView: View {
    @StateObject private var viewModel = ToolSettingsViewModel.shared

    var body: some View {
        Form {
            ToolSettingsSection(viewModel: viewModel)
        }
        .navigationTitle("Tool Calling")
        #if os(iOS)
        .navigationBarTitleDisplayModeCompat(.inline)
        #endif
        .task {
            await viewModel.refreshRegisteredTools()
        }
    }
}
