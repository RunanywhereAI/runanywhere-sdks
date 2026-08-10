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
            Text(headerSubtitle)
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    /// This card is also the Talk screen's Models sheet, which can be opened
    /// mid-conversation. It was written for the pre-setup state only, so during
    /// a live session it invited the user to "get it ready in one tap" while the
    /// status pill behind it read "Listening" — telling them to start something
    /// that was already running. The copy branches on the session, not just on
    /// which models happen to be resident.
    private var headerSubtitle: String {
        if viewModel.isActive {
            return "This conversation is live. Change a component below to swap it for the next one."
        }
        return "We picked the best voice setup for your device. "
            + "Get it ready in one \(VoiceAgentViewModel.pressVerb.lowercased())."
    }

    // MARK: - Component card

    /// The four pipeline slots.
    ///
    /// Titles and glyphs are the ones the Android voice screen and the web voice view use, so a
    /// reader who learned the pipeline on one platform recognises it on another. Each glyph is
    /// `RAModelCategory.consumerCapabilityIcon`'s value for that slot's category — this card used
    /// to hardcode `brain` for the language model while the rest of the app drew `message` for
    /// it, and Android drew a brain for *speech recognition*, i.e. the same picture meant two
    /// opposite ends of one pipeline. Brain is reasoning only now, in all three apps.
    private var card: some View {
        VStack(spacing: 0) {
            componentRow(component: .init(
                title: "Speech-to-text",
                subtitle: "Turns your voice into text",
                spokenSlot: "speech-to-text",
                icon: RAModelCategory.speechRecognition.consumerCapabilityIcon,
                color: AppColors.statusGreen,
                name: viewModel.sttModel?.name.modelNameFromID(),
                state: viewModel.sttModelState,
                progress: viewModel.sttDownloadProgress
            ), onChange: onChangeSTT)
            divider
            componentRow(component: .init(
                title: "Chat model",
                subtitle: "Understands and replies",
                spokenSlot: "chat",
                icon: RAModelCategory.language.consumerCapabilityIcon,
                color: AppColors.primaryAccent,
                name: viewModel.llmModel?.name.modelNameFromID(),
                state: viewModel.llmModelState,
                progress: viewModel.llmDownloadProgress
            ), onChange: onChangeLLM)
            divider
            componentRow(component: .init(
                title: "Text-to-speech",
                subtitle: "Speaks replies aloud",
                spokenSlot: "text-to-speech",
                icon: RAModelCategory.speechSynthesis.consumerCapabilityIcon,
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
        /// What the row's controls call this slot when they are read aloud.
        /// Separate from `title` because the announcement is a phrase, not a
        /// heading: composing it from the title produced "Change chat model
        /// model" for the row headed "Chat model".
        let spokenSlot: String
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
                slot: component.spokenSlot,
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
        slot: String,
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
                    .accessibilityLabel("Ready")
                changeButton(slot: slot, onChange)
            }
        case .loading:
            progressBadge(progress)
        case .error:
            HStack(spacing: AppSpacing.xxSmall) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppColors.statusOrange)
                    .accessibilityLabel("Failed")
                changeButton(slot: slot, onChange)
            }
        case .notLoaded:
            if viewModel.isSettingUpPipeline, progress > 0, progress < 1 {
                progressBadge(progress)
            } else if hasSelection {
                changeButton(slot: slot, onChange)
            } else {
                Button("Choose", action: onChange)
                    .font(AppTypography.caption)
                    .fontWeight(.semibold)
                    .buttonStyle(.bordered)
                    .tint(AppColors.primaryAccent)
                    .controlSize(.small)
                    .accessibilityLabel("Choose \(slot) model")
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

    /// The only way to override a pipeline slot.
    ///
    /// It was `Button("Change").buttonStyle(.plain)` with caption typography and
    /// no padding, so the hit area was the glyph box — the Mac's accessibility
    /// tree measured all three at 37x13 pt, roughly half the 24 pt minimum and a
    /// third of the 44 pt a pointer needs. The padding below is what the target
    /// is made of, and `contentShape` makes the padded rect hit-test rather than
    /// just the text.
    private func changeButton(slot: String, _ onChange: @escaping () -> Void) -> some View {
        Button(action: onChange) {
            Text("Change")
                .font(AppTypography.caption)
                // Derived, not fixed: `.plain` hands the label its color
                // verbatim and does not dim it for `.disabled`, so during setup
                // three accent-orange buttons looked tappable and did nothing.
                .foregroundColor(viewModel.isSettingUpPipeline
                    ? AppColors.textSecondary
                    : AppColors.primaryAccent)
                .padding(.horizontal, AppSpacing.smallMedium)
                // The padding lives inside the label on purpose: a Button
                // hit-tests its label, so padding applied outside the Button
                // would have moved the button without growing its target.
                .frame(minWidth: Self.minimumHitTarget, minHeight: Self.minimumHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Three identically-titled buttons in one card; the slot is the only
        // thing that tells them apart.
        .accessibilityLabel("Change \(slot) model")
        .disabled(viewModel.isSettingUpPipeline)
    }

    /// 44 pt: the coarse-pointer minimum, which also satisfies the 24 pt floor.
    /// Both platforms get it — a trackpad is a coarse pointer too.
    private static let minimumHitTarget: CGFloat = 44

    private var vadRow: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            Image(systemName: RAModelCategory.voiceActivityDetection.consumerCapabilityIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppColors.statusBlue)
                .frame(width: AppSpacing.iconMedium, height: AppSpacing.iconMedium)
                .background(AppColors.statusBlue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge))

            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text("Voice detection")
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

    /// The one primary action, and — while it runs — a way out of it.
    ///
    /// The running state used to be a lone `ProgressView` with no step text
    /// (`pipelineSetupStatus` was only set after the first step began), no
    /// per-component percentage and nothing to press. A first attempt that
    /// stalled sat like that for eleven measured minutes with no way to retry or
    /// abandon it. Every branch below now names what is happening and, while
    /// work is in flight, offers Cancel.
    @ViewBuilder private var primaryAction: some View {
        if viewModel.isSettingUpPipeline {
            VStack(spacing: AppSpacing.smallMedium) {
                ProgressView()
                Text(viewModel.pipelineSetupStatus ?? "Getting started…")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Cancel") { viewModel.cancelPipelineSetup() }
                    .font(AppTypography.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Cancel Voice AI setup")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.large)
        } else if viewModel.allModelsLoaded {
            readyBadge
        } else {
            VStack(spacing: AppSpacing.smallMedium) {
                if viewModel.didCancelSetup {
                    // A cancelled setup is neither a failure nor an untouched
                    // card, and saying so is what tells the user their press
                    // registered and that resuming will not start over.
                    Text("Setup cancelled. What already downloaded is kept.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                Button {
                    viewModel.startPipelineSetup()
                } label: {
                    HStack(spacing: AppSpacing.smallMedium) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text(viewModel.didCancelSetup ? "Resume setup" : "Set up Voice AI")
                    }
                    .font(AppTypography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.large)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.primaryAccent)
                .disabled(!canSetup)
                .accessibilityLabel(viewModel.didCancelSetup
                    ? "Resume Voice AI setup"
                    : "Set up Voice AI")
            }
        }
    }

    private var readyBadge: some View {
        HStack(spacing: AppSpacing.smallMedium) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(AppColors.statusGreen)
            // A live session is not "ready to start" — it is running. Same
            // reason as `headerSubtitle`: this card doubles as the mid-session
            // Models sheet.
            Text(viewModel.isActive
                 ? "Conversation running"
                 : "Ready — \(VoiceAgentViewModel.pressVerb.lowercased()) the mic to talk")
                .font(AppTypography.subheadlineSemibold)
                .foregroundColor(AppColors.statusGreen)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.large)
        .accessibilityElement(children: .combine)
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
