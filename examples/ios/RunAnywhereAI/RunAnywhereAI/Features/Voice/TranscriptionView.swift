import SwiftUI
import RunAnywhere
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct TranscriptionView: View {
    @StateObject private var viewModel = TranscriptionViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var copiedToClipboard = false
    @State private var showModelInfo = false

    var body: some View {
        Group {
            #if os(macOS)
            // macOS: Custom layout without NavigationView
            VStack(spacing: 0) {
            // Custom toolbar for macOS
            HStack {
                Button(action: { dismiss() }) {
                    Label("Close", systemImage: "xmark")
                }
                .buttonStyle(.bordered)

                Spacer()

                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isTranscribing ? Color.red : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(viewModel.currentStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Options menu
                Menu {
                    Button(action: { copyToClipboard() }) {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }

                    Button(action: { viewModel.clearTranscripts() }) {
                        Label("Clear", systemImage: "trash")
                    }

                    Divider()

                    Button(action: { withAnimation { showModelInfo.toggle() } }) {
                        Label(showModelInfo ? "Hide Info" : "Show Info", systemImage: "info.circle")
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.finalTranscripts.isEmpty && viewModel.partialTranscript.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Model info section
            if showModelInfo {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text("STT: \(viewModel.whisperModel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(8)

                    // Speaker diarization indicator
                    if viewModel.enableSpeakerDiarization {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Text("Speaker Detection: ON")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if !viewModel.detectedSpeakers.isEmpty {
                                Text("•")
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text("\(viewModel.detectedSpeakers.count) speakers")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Main content area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Final transcripts
                        ForEach(viewModel.finalTranscripts) { segment in
                            CleanTranscriptSegment(
                                text: segment.text,
                                timestamp: segment.timestamp,
                                isFinal: true,
                                speaker: segment.speaker
                            )
                        }

                        // Partial transcript
                        if !viewModel.partialTranscript.isEmpty {
                            CleanTranscriptSegment(
                                text: viewModel.partialTranscript,
                                timestamp: Date(),
                                isFinal: false,
                                speaker: viewModel.currentSpeaker
                            )
                            .id("bottom")
                        }

                        // Empty state
                        if viewModel.finalTranscripts.isEmpty && viewModel.partialTranscript.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "text.quote")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary.opacity(0.3))
                                Text("Click to start transcribing")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 150)
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 800, alignment: .leading)
                }
                .onChange(of: viewModel.partialTranscript) { _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            // Control area
            VStack(spacing: 20) {
                // Error message (if any)
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                // Main mic button
                Button(action: {
                    Task {
                        if viewModel.isTranscribing {
                            await viewModel.stopTranscription()
                        } else {
                            await viewModel.startTranscription()
                        }
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(viewModel.isTranscribing ? Color.red : Color.blue)
                            .frame(width: 72, height: 72)

                        // Pulsing effect when transcribing
                        if viewModel.isTranscribing {
                            Circle()
                                .stroke(Color.white.opacity(0.4), lineWidth: 2)
                                .scaleEffect(viewModel.isTranscribing ? 1.3 : 1.0)
                                .opacity(viewModel.isTranscribing ? 0 : 0.8)
                                .animation(
                                    .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                                    value: viewModel.isTranscribing
                                )
                        }

                        Image(systemName: viewModel.isTranscribing ? "stop.fill" : "mic.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)

                // Subtle instruction
                Text(viewModel.isTranscribing ? "Listening... Click to stop" : "Click to transcribe")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.bottom, 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
            #else
        NavigationView {
            VStack(spacing: 0) {
                // Clean, minimal header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .padding(10)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(Circle())
                    }

                    Spacer()

                    // Minimal status
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.isTranscribing ? Color.red : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(viewModel.currentStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Options menu
                    Menu {
                        Button(action: { copyToClipboard() }) {
                            Label("Copy All", systemImage: "doc.on.doc")
                        }

                        Button(action: { viewModel.clearTranscripts() }) {
                            Label("Clear", systemImage: "trash")
                        }
                        .foregroundColor(.red)

                        Divider()

                        Button(action: { withAnimation { showModelInfo.toggle() } }) {
                            Label(showModelInfo ? "Hide Info" : "Show Info", systemImage: "info.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .padding(10)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(Circle())
                    }
                    .disabled(viewModel.finalTranscripts.isEmpty && viewModel.partialTranscript.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 15)

                // Collapsible model info
                if showModelInfo {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "waveform")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Text("STT: \(viewModel.whisperModel)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.08))
                        .cornerRadius(8)

                        // Speaker diarization indicator
                        if viewModel.enableSpeakerDiarization {
                            HStack {
                                Image(systemName: "person.2.fill")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                Text("Speaker Detection: ON")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if !viewModel.detectedSpeakers.isEmpty {
                                    Text("•")
                                        .foregroundColor(.secondary.opacity(0.5))
                                    Text("\(viewModel.detectedSpeakers.count) speakers")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Main transcription area
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Final transcripts
                            ForEach(viewModel.finalTranscripts) { segment in
                                CleanTranscriptSegment(
                                    text: segment.text,
                                    timestamp: segment.timestamp,
                                    isFinal: true,
                                    speaker: segment.speaker
                                )
                            }

                            // Partial transcript
                            if !viewModel.partialTranscript.isEmpty {
                                CleanTranscriptSegment(
                                    text: viewModel.partialTranscript,
                                    timestamp: Date(),
                                    isFinal: false,
                                    speaker: viewModel.currentSpeaker
                                )
                                .id("bottom")
                            }

                            // Empty state
                            if viewModel.finalTranscripts.isEmpty && viewModel.partialTranscript.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "text.quote")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary.opacity(0.3))
                                    Text("Tap to start transcribing")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 150)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                    }
                    .onChange(of: viewModel.partialTranscript) { _ in
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }

                Spacer()

                // Minimal control area
                VStack(spacing: 20) {
                    // Error message (if any)
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }

                    // Main mic button
                    Button(action: {
                        Task {
                            if viewModel.isTranscribing {
                                await viewModel.stopTranscription()
                            } else {
                                await viewModel.startTranscription()
                            }
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(viewModel.isTranscribing ? Color.red : Color.blue)
                                .frame(width: 72, height: 72)

                            // Pulsing effect when transcribing
                            if viewModel.isTranscribing {
                                Circle()
                                    .stroke(Color.white.opacity(0.4), lineWidth: 2)
                                    .scaleEffect(viewModel.isTranscribing ? 1.3 : 1.0)
                                    .opacity(viewModel.isTranscribing ? 0 : 0.8)
                                    .animation(
                                        .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                                        value: viewModel.isTranscribing
                                    )
                            }

                            Image(systemName: viewModel.isTranscribing ? "stop.fill" : "mic.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                        }
                    }

                    // Subtle instruction
                    Text(viewModel.isTranscribing ? "Listening... Tap to stop" : "Tap to transcribe")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .padding(.bottom, 30)
            }
            .background(Color(.systemBackground))
            .navigationBarHidden(true)
        }
            #endif
        }
        .task {
            await viewModel.initialize()
        }
        .overlay(alignment: .top) {
            if copiedToClipboard {
                ToastView(message: "Copied to clipboard")
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 50)
            }
        }
    }

    // MARK: - Helper Functions

    private func copyToClipboard() {
        let fullText = viewModel.finalTranscripts.map { $0.text }.joined(separator: "\n")

        #if os(iOS) || targetEnvironment(macCatalyst)
        UIPasteboard.general.string = fullText
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fullText, forType: .string)
        #endif

        withAnimation {
            copiedToClipboard = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedToClipboard = false
            }
        }
    }
}

// Clean transcript segment view with speaker support
struct CleanTranscriptSegment: View {
    let text: String
    let timestamp: Date
    let isFinal: Bool
    let speaker: SpeakerInfo?

    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    // Speaker colors - assign colors based on speaker ID
    private func speakerColor(for speakerId: String?) -> Color {
        guard let id = speakerId else { return .gray }
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .indigo, .mint]
        let hash = abs(id.hashValue)
        return colors[hash % colors.count]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Speaker indicator
            if let speaker = speaker {
                VStack(spacing: 4) {
                    Circle()
                        .fill(speakerColor(for: speaker.id))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(String((speaker.name ?? speaker.id).prefix(1)).uppercased())
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        )

                    Text(speaker.name ?? "Speaker")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 50)
            }

            // Transcript content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(formatter.string(from: timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))

                    if speaker != nil {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.5))

                        Text(speaker?.name ?? speaker?.id ?? "Unknown")
                            .font(.caption2)
                            .foregroundColor(speakerColor(for: speaker?.id))
                            .fontWeight(.medium)
                    }
                }

                Text(text)
                    .font(.body)
                    .foregroundColor(isFinal ? .primary : .secondary)
                    .opacity(isFinal ? 1.0 : 0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

// Simple toast view for notifications
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(20)
    }
}

// Preview
struct TranscriptionView_Previews: PreviewProvider {
    static var previews: some View {
        TranscriptionView()
    }
}
