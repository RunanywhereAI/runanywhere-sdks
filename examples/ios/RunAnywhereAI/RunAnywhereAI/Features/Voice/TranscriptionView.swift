import SwiftUI
import RunAnywhereSDK

struct TranscriptionView: View {
    @StateObject private var viewModel = TranscriptionViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var isExporting = false
    @State private var copiedToClipboard = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerView

                // Transcription Display
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            // Final transcripts
                            ForEach(viewModel.finalTranscripts) { segment in
                                TranscriptSegmentView(
                                    text: segment.text,
                                    timestamp: segment.timestamp,
                                    isFinal: true
                                )
                            }

                            // Partial transcript
                            if !viewModel.partialTranscript.isEmpty {
                                TranscriptSegmentView(
                                    text: viewModel.partialTranscript,
                                    timestamp: Date(),
                                    isFinal: false
                                )
                                .id("bottom")
                            }

                            // Empty state
                            if viewModel.finalTranscripts.isEmpty && viewModel.partialTranscript.isEmpty {
                                emptyStateView
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.partialTranscript) { _ in
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .background(Color(.systemGray6))

                // Control Panel
                controlPanel
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { copyToClipboard() }) {
                            Label("Copy All", systemImage: "doc.on.doc")
                        }

                        Button(action: { exportTranscription() }) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }

                        Button(action: { viewModel.clearTranscripts() }) {
                            Label("Clear", systemImage: "trash")
                        }
                        .foregroundColor(.red)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(viewModel.finalTranscripts.isEmpty && viewModel.partialTranscript.isEmpty)
                }
            }
        }
        .task {
            await viewModel.initialize()
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .overlay(alignment: .top) {
            if copiedToClipboard {
                ToastView(message: "Copied to clipboard")
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(spacing: 8) {
            Text("Transcription Mode")
                .font(.headline)

            HStack {
                Image(systemName: "mic.fill")
                    .foregroundColor(viewModel.isTranscribing ? .green : .gray)
                    .symbolEffect(.pulse, value: viewModel.isTranscribing)

                Text(viewModel.currentStatus)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text(viewModel.whisperModel)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .cornerRadius(6)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No transcription yet")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Tap the microphone button to start transcribing")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Control Panel

    private var controlPanel: some View {
        VStack(spacing: 0) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator))

            HStack(spacing: 32) {
                // Clear button
                Button(action: {
                    viewModel.clearTranscripts()
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 24))
                        Text("Clear")
                            .font(.caption)
                    }
                }
                .foregroundColor(.secondary)
                .disabled(viewModel.finalTranscripts.isEmpty && viewModel.partialTranscript.isEmpty)

                // Main transcribe button
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

                        Image(systemName: viewModel.isTranscribing ? "stop.fill" : "mic.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                    }
                }
                .disabled(!viewModel.isInitialized)

                // Copy button
                Button(action: {
                    copyToClipboard()
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 24))
                        Text("Copy")
                            .font(.caption)
                    }
                }
                .foregroundColor(.secondary)
                .disabled(viewModel.finalTranscripts.isEmpty && viewModel.partialTranscript.isEmpty)
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Actions

    private func copyToClipboard() {
        viewModel.copyToClipboard()

        withAnimation {
            copiedToClipboard = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedToClipboard = false
            }
        }
    }

    private func exportTranscription() {
        let text = viewModel.exportTranscripts()

        #if os(iOS)
        let activityController = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityController, animated: true)
        }
        #endif
    }
}

// MARK: - Transcript Segment View

struct TranscriptSegmentView: View {
    let text: String
    let timestamp: Date
    let isFinal: Bool

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(timeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if !isFinal {
                    Image(systemName: "ellipsis")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .symbolEffect(.pulse)
                }

                Spacer()
            }

            Text(text)
                .font(.body)
                .foregroundColor(isFinal ? .primary : .secondary)
                .opacity(isFinal ? 1.0 : 0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFinal ? Color.clear : Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Toast View

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.8))
            .cornerRadius(20)
            .padding(.top, 50)
    }
}

// MARK: - Preview

struct TranscriptionView_Previews: PreviewProvider {
    static var previews: some View {
        TranscriptionView()
    }
}
