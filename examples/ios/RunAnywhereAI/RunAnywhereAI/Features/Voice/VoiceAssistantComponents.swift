//
//  VoiceAssistantComponents.swift
//  RunAnywhereAI
//
//  Reusable UI components for VoiceAssistantView
//

import SwiftUI
import RunAnywhere

// MARK: - VoiceModelChip

/// The toolbar "which model is loaded" chip for the three single-component
/// voice screens (STT / TTS / VAD).
///
/// ## Why this exists
///
/// All three screens had a byte-for-byte identical `modelButton`, and each
/// carried its *own* private `frameworkIcon(for:)` / `frameworkColor(for:)`
/// pair — which disagreed with each other and with the app:
///
/// | framework | STT screen said | TTS screen said | VAD screen said |
/// | --- | --- | --- | --- |
/// | ONNX | `square.stack.3d.up`, purple | `cube`, grey | `cube`, grey |
/// | Sherpa | `cube`, grey | `cube`, grey | `cube`, grey |
///
/// So the *same* Whisper model showed a purple stack on Transcribe and a grey
/// cube on Speak, and `square.stack.3d.up` — the app's "Models" destination
/// glyph, used in the Mac sidebar, the Settings tab bar and the Advanced hub —
/// was being reused to mean "ONNX". That breaks one-glyph-one-meaning twice
/// over: one concept drawn three ways, and one glyph carrying two concepts.
///
/// Worse, on VAD the framework row was hardcoded to `cube` while the row above
/// it *also* fell back to `cube` for "no model chosen" — the same symbol on two
/// adjacent rows meaning two different things.
///
/// The app already had exactly one right answer for this:
/// `InferenceFramework.consumerBackendIcon` / `.consumerBackendColor` in
/// `ModelPresentation.swift`, which every Models-tab surface uses. The three
/// private copies were shadowing it. This chip deletes them and delegates, so a
/// backend looks the same everywhere in the app and a new framework case only
/// has to be described once.
struct VoiceModelChip: View {
    let modelName: String?
    let framework: InferenceFramework?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let modelName {
                loadedChip(modelName: modelName)
            } else {
                Text("Select Model")
                    .appType(.meta)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Choose a different model")
    }

    private func loadedChip(modelName: String) -> some View {
        HStack(spacing: Space.sm) {
            Image(getModelLogo(for: modelName))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Self.logoSize, height: Self.logoSize)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(modelName.shortModelName())
                    .appType(.meta)
                    .lineLimit(1)

                if let framework {
                    Label {
                        Text(framework.consumerBackendBadgeLabel)
                    } icon: {
                        Image(systemName: framework.consumerBackendIcon)
                    }
                    .appType(.overline)
                    .labelStyle(.titleAndIcon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(framework.consumerBackendColor)
                    .lineLimit(1)
                }
            }
        }
    }

    private var accessibilityLabel: String {
        guard let modelName else { return "Select a model" }
        guard let framework else { return modelName }
        return "\(modelName), \(framework.consumerBackendBadgeLabel)"
    }

    private static let logoSize: CGFloat = 32
}

// MARK: - PartialSpeechBadge

/// Marks a transcript that is still a guess.
///
/// Speech recognition emits a hypothesis long before it emits a result, and the
/// words in it visibly change as more audio arrives. Drawn identically to the
/// settled transcript that reads as the app malfunctioning, so the two are
/// distinguished — by a label, not by colour alone, and the transcript itself
/// also renders in a lighter, italic style.
struct PartialSpeechBadge: View {
    var body: some View {
        Text("Still hearing you")
            .appType(.chip)
            .foregroundStyle(AppColors.primaryAccent)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .background(Capsule().fill(AppColors.primaryAccent.opacity(0.12)))
            .accessibilityLabel("Partial transcript, still being recognised")
    }
}

// MARK: - ConversationBubble

struct ConversationBubble: View {
    let speaker: String
    let message: String
    let isUser: Bool
    /// True when `message` is state copy standing in for content that has not
    /// arrived, so it is set apart instead of reading as something the user or
    /// the model actually said.
    var isPlaceholder = false
    /// True while a user transcript is a revisable hypothesis.
    var isPartial = false

    private var fill: Color {
        isUser ? AppColors.backgroundSecondary : AppColors.primaryAccent.opacity(0.08)
    }

    var body: some View {
        Text(message)
            .appType(.body)
            .italic(isPartial || isPlaceholder)
            .foregroundStyle(isPlaceholder ? AppColors.textSecondary : AppColors.textPrimary)
            .textSelection(.enabled)
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(fill)
            )
            // The label names who is talking, which the visual layout carries
            // for a sighted reader and nothing else carries otherwise.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(speaker): \(message)")
    }
}

// MARK: - ModelBadge

struct ModelBadge: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: AdaptiveSizing.badgeFontSize))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: AdaptiveSizing.badgeFontSize - 1))
                    .foregroundColor(.secondary)
                Text(value.shortModelName(maxLength: 15))
                    .font(.system(size: AdaptiveSizing.badgeFontSize))
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, AdaptiveSizing.badgePaddingH)
        .padding(.vertical, AdaptiveSizing.badgePaddingV)
        .background(color.opacity(0.1))
        .cornerRadius(AppSpacing.cornerRadiusMedium)
    }
}
