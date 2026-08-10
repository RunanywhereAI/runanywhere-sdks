//
//  ModelStatusComponents.swift
//  RunAnywhereAI
//
//  The "you need a model first" screen, shared by seven surfaces (chat, STT,
//  TTS, VAD, VLM, diarization, segmentation).
//
//  This is the most-seen empty state in the app — it is what a first launch
//  looks like — so it is built on the shared `EmptyStateView`/`EmptyStateMark`
//  rather than on a bespoke hero. Previously it hand-rolled a 30pt rounded
//  title, three blurred circles drifting on an 8-second ease, and a 2.2s halo:
//  five durations, none of them in the spec, and three parallel background
//  systems (`Color(.systemBackground)`, a raw `NSColor`, and blurred tinted
//  circles). One figure, one background, four tiers.
//
//  `ModelStatusBanner` and `CompactModelIndicator` lived here with zero call
//  sites and their own font/color/radius vocabulary; they are gone. The live
//  status surface is `ChatInterfaceView`'s `navigationSubtitle` on Mac and its
//  header on iOS.
//

import SwiftUI
import RunAnywhere

// MARK: - Model Load State (Local UI type)

/// Simple enum to track model loading state in the UI
enum ModelLoadState: Equatable {
    case notLoaded
    case loading
    case loaded
    case error(String)

    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

// MARK: - Model Required Overlay

/// Full-surface first-run state: what this modality does, and the one button
/// that starts it.
struct ModelRequiredOverlay: View {
    let modality: ModelSelectionContext
    let onSelectModel: () -> Void

    var body: some View {
        EmptyStateView(
            systemImage: modality.emptyStateGlyph,
            title: modality.emptyStateTitle,
            message: modality.emptyStateMessage,
            tint: modality.accent
        ) {
            VStack(spacing: Space.lg) {
                Button(action: onSelectModel) {
                    // The label names the destination. "Get Started" could open
                    // anything; "Choose a model" says what the tap does, which
                    // is what makes the button safe to press.
                    Label(modality.emptyStateActionTitle, systemImage: "square.stack.3d.up")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(RAProminentButtonStyle(radius: Radius.md))
                .keyboardShortcut(.defaultAction)

                privacyNote
            }
        }
        // A real background, not a transparent overlay: this covers the surface
        // completely, and a see-through empty state over a half-built screen is
        // how the old build ended up with text on text.
        .background(AppColors.background)
    }

    /// The one claim worth making on a first run, and the only one this app can
    /// make that a cloud assistant cannot.
    private var privacyNote: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "lock.shield")
                .symbolRenderingMode(.hierarchical)
                .appType(.caption)

            Text("Runs on this device. Nothing is uploaded.")
                .appType(.caption)
        }
        .foregroundStyle(AppColors.textTertiary)
    }
}

// MARK: - Per-modality copy

/// Empty-state vocabulary lives on the context, not in the view, so a new
/// modality cannot be added without deciding what its first run says.
private extension ModelSelectionContext {
    /// One glyph, one meaning, app-wide (DESIGN_GUIDELINE §7): a microphone is
    /// always capture, a waveform is always audio content, a document is always
    /// a corpus file.
    var emptyStateGlyph: String {
        switch self {
        case .llm: return "bubble.left.and.bubble.right"
        case .stt: return "waveform"
        case .tts: return "speaker.wave.2"
        case .vad: return "waveform.badge.mic"
        case .voice: return "mic"
        case .vlm: return "camera.viewfinder"
        case .ragEmbedding: return "doc.text.magnifyingglass"
        case .ragLLM: return "text.bubble"
        case .diarization: return "person.2.wave.2"
        case .segmentation: return "square.3.layers.3d.down.right"
        }
    }

    var accent: Color {
        switch self {
        case .llm, .voice, .vlm, .ragLLM: return AppColors.brand
        case .stt, .diarization: return AppColors.statusGreen
        case .tts, .segmentation: return AppColors.primaryPurple
        case .vad: return AppColors.primaryBlue
        case .ragEmbedding: return AppColors.primaryBlue
        }
    }

    /// Titles name the capability, not the app's excitement about it. "Welcome!"
    /// told a first-run reader nothing about what the screen would do.
    var emptyStateTitle: String {
        switch self {
        case .llm: return "Start a conversation"
        case .stt: return "Voice to text"
        case .tts: return "Read text aloud"
        case .vad: return "Detect speech"
        case .voice: return "Talk with your assistant"
        case .vlm: return "Understand what it sees"
        case .ragEmbedding: return "Index your documents"
        case .ragLLM: return "Answer from your documents"
        case .diarization: return "Identify who spoke"
        case .segmentation: return "Segment an image"
        }
    }

    var emptyStateMessage: String {
        switch self {
        case .llm:
            return "Choose a language model and chat with it. It runs entirely on this device."
        case .stt:
            return "Transcribe speech with on-device recognition — no network, no upload."
        case .tts:
            return "Turn any text into natural-sounding speech, generated locally."
        case .vad:
            return "Find where speech starts and stops in live audio, frame by frame."
        case .voice:
            return "A full spoken conversation: it listens, thinks, and replies out loud."
        case .vlm:
            return "Point the camera at anything, or pick a photo, and ask about it."
        case .ragEmbedding:
            return "An embedding model turns your documents into vectors this app can search."
        case .ragLLM:
            return "A language model writes the answers, grounded in the documents you added."
        case .diarization:
            return "Separate a recording by speaker and see who said what, on-device."
        case .segmentation:
            return "Outline the objects in an image and label them class by class."
        }
    }

    /// The two-model surfaces say *which* model, because "Choose a model" on the
    /// RAG screen is ambiguous — it has two slots to fill.
    var emptyStateActionTitle: String {
        switch self {
        case .ragEmbedding: return "Choose an embedding model"
        case .ragLLM: return "Choose a language model"
        default: return "Choose a model"
        }
    }
}

// MARK: - Previews

#Preview("Chat") {
    ModelRequiredOverlay(modality: .llm) {}
}

#Preview("Speech to text") {
    ModelRequiredOverlay(modality: .stt) {}
}

#Preview("RAG embedding") {
    ModelRequiredOverlay(modality: .ragEmbedding) {}
}
