//
//  VoiceAISetupView.swift
//  RunAnywhereAI
//
//  Minimal-friction Voice AI setup: the best-for-device STT + LLM + TTS (+ VAD)
//  trio is pre-selected automatically. One primary button downloads + loads all
//  components with per-component progress. The user only taps "Change" on a
//  component to override the pick.
//

import SwiftUI
import RunAnywhere

/// A single, clean setup card listing the pre-selected voice components and one
/// primary action that gets them all ready.
struct VoiceAISetupCard: View {
    @ObservedObject var viewModel: VoiceAgentViewModel

    let onChangeSTT: () -> Void
    let onChangeLLM: () -> Void
    let onChangeTTS: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xLarge) {
                header
                card
                Spacer(minLength: AppSpacing.large)
                primaryAction
                privacyNote
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.top, AppSpacing.xxLarge)
            .padding(.bottom, AppSpacing.large)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: AppSpacing.smallMedium) {
            Image(systemName: "mic.circle.fill")
                .font(AppTypography.system48)
                .foregroundColor(AppColors.primaryAccent)
            Text("Voice AI")
                .font(AppTypography.title2Semibold)
            Text("We picked the best voice setup for your device. Get it ready in one tap.")
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Component card

    private var card: some View {
        VStack(spacing: 0) {
            componentRow(component: .init(
                title: "Speech recognition",
                subtitle: "Turns your voice into text",
                icon: "waveform",
                color: AppColors.statusGreen,
                name: viewModel.sttModel?.name.modelNameFromID(),
                state: viewModel.sttModelState,
                progress: viewModel.sttDownloadProgress
            ), onChange: onChangeSTT)
            divider
            componentRow(component: .init(
                title: "Assistant",
                subtitle: "Understands and replies",
                icon: "brain",
                color: AppColors.primaryAccent,
                name: viewModel.llmModel?.name.modelNameFromID(),
                state: viewModel.llmModelState,
                progress: viewModel.llmDownloadProgress
            ), onChange: onChangeLLM)
            divider
            componentRow(component: .init(
                title: "Voice",
                subtitle: "Speaks replies aloud",
                icon: "speaker.wave.2",
                color: AppColors.primaryPurple,
                name: viewModel.ttsModel?.name.modelNameFromID(),
                state: viewModel.ttsModelState,
                progress: viewModel.ttsDownloadProgress
            ), onChange: onChangeTTS)
            divider
            vadRow
        }
        .background(AppColors.backgroundSecondary)
        .cornerRadius(AppSpacing.cornerRadiusCard)
    }

    private var divider: some View {
        Divider().padding(.leading, AppSpacing.xxLarge + AppSpacing.mediumLarge)
    }

    /// Value describing one pipeline component's presentation state.
    private struct Component {
        let title: String
        let subtitle: String
        let icon: String
        let color: Color
        let name: String?
        let state: ModelLoadState
        let progress: Double
    }

    private func componentRow(component: Component, onChange: @escaping () -> Void) -> some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            Image(systemName: component.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(component.color)
                .frame(width: AppSpacing.iconMedium, height: AppSpacing.iconMedium)
                .background(component.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge))

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(component.title)
                    .font(AppTypography.subheadlineSemibold)
                    .foregroundColor(AppColors.textPrimary)
                Text(component.name ?? component.subtitle)
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            statusView(
                state: component.state,
                progress: component.progress,
                hasSelection: component.name != nil,
                onChange: onChange
            )
        }
        .padding(AppSpacing.mediumLarge)
    }

    @ViewBuilder
    private func statusView(
        state: ModelLoadState,
        progress: Double,
        hasSelection: Bool,
        onChange: @escaping () -> Void
    ) -> some View {
        switch state {
        case .loaded:
            HStack(spacing: AppSpacing.xxSmall) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(AppColors.statusGreen)
                changeButton(onChange)
            }
        case .loading:
            progressBadge(progress)
        case .error:
            HStack(spacing: AppSpacing.xxSmall) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppColors.statusOrange)
                changeButton(onChange)
            }
        case .notLoaded:
            if viewModel.isSettingUpPipeline, progress > 0, progress < 1 {
                progressBadge(progress)
            } else if hasSelection {
                changeButton(onChange)
            } else {
                Button("Choose", action: onChange)
                    .font(AppTypography.caption)
                    .fontWeight(.semibold)
                    .buttonStyle(.bordered)
                    .tint(AppColors.primaryAccent)
                    .controlSize(.small)
            }
        }
    }

    private func progressBadge(_ progress: Double) -> some View {
        HStack(spacing: AppSpacing.xxSmall) {
            ProgressView().scaleEffect(0.7)
            if progress > 0 {
                Text("\(Int(progress * 100))%")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    private func changeButton(_ onChange: @escaping () -> Void) -> some View {
        Button("Change", action: onChange)
            .font(AppTypography.caption)
            .foregroundColor(AppColors.primaryAccent)
            .buttonStyle(.plain)
            .disabled(viewModel.isSettingUpPipeline)
    }

    private var vadRow: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppColors.statusBlue)
                .frame(width: AppSpacing.iconMedium, height: AppSpacing.iconMedium)
                .background(AppColors.statusBlue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge))

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("Speech detection")
                    .font(AppTypography.subheadlineSemibold)
                    .foregroundColor(AppColors.textPrimary)
                Text("Knows when you start and stop talking")
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text("Automatic")
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(AppSpacing.mediumLarge)
    }

    // MARK: - Primary action

    @ViewBuilder
    private var primaryAction: some View {
        if viewModel.isSettingUpPipeline {
            VStack(spacing: AppSpacing.smallMedium) {
                ProgressView()
                if let status = viewModel.pipelineSetupStatus {
                    Text(status)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.large)
        } else if viewModel.allModelsLoaded {
            readyBadge
        } else {
            Button {
                Task { await viewModel.downloadAndLoadAll() }
            } label: {
                HStack(spacing: AppSpacing.smallMedium) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Set up Voice AI")
                }
                .font(AppTypography.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.large)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primaryAccent)
            .disabled(!canSetup)
        }
    }

    private var readyBadge: some View {
        HStack(spacing: AppSpacing.smallMedium) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(AppColors.statusGreen)
            Text("Ready — tap the mic to talk")
                .font(AppTypography.subheadlineSemibold)
                .foregroundColor(AppColors.statusGreen)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.large)
    }

    private var canSetup: Bool {
        viewModel.sttModel != nil && viewModel.llmModel != nil && viewModel.ttsModel != nil
    }

    private var privacyNote: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "lock.shield.fill")
                .font(AppTypography.caption2)
            Text("100% private · runs on your device")
                .font(AppTypography.caption)
        }
        .foregroundColor(AppColors.textSecondary)
    }
}
