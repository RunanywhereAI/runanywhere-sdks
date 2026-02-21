//
//  VoiceDictationManagementView.swift
//  RunAnywhereAI
//
//  Management screen for the Voice Keyboard feature (accessible from More tab).
//  Lets the user:
//    - Check / request microphone permission
//    - Select and load an on-device STT model
//    - See instructions for enabling the keyboard
//    - View dictation history
//

#if os(iOS)
import SwiftUI
import RunAnywhere

struct VoiceDictationManagementView: View {

    @StateObject private var viewModel = VoiceDictationManagementViewModel()
    @EnvironmentObject private var flowSession: FlowSessionManager

    var body: some View {
        List {
            statusSection
            modelSection
            setupSection
            if !viewModel.dictationHistory.isEmpty {
                historySection
            }
        }
        .navigationTitle("Voice Keyboard")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $viewModel.showModelPicker) {
            ModelSelectionSheet(context: .stt) { model in
                await viewModel.loadModel(model)
                viewModel.showModelPicker = false
            }
        }
        .task { await viewModel.onAppear() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await viewModel.onForeground() }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section("Status") {
            StatusRow(
                icon: viewModel.microphonePermission.systemImage,
                iconColor: permissionColor,
                label: "Microphone",
                value: viewModel.microphonePermission.label,
                action: viewModel.microphonePermission == .unknown ? {
                    Task { await viewModel.requestMicrophonePermission() }
                } : nil,
                actionLabel: "Allow"
            )

            if let phase = sessionPhaseDescription {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.85)
                    Text(phase)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var permissionColor: Color {
        switch viewModel.microphonePermission {
        case .granted: return .green
        case .denied:  return .red
        case .unknown: return .orange
        }
    }

    private var sessionPhaseDescription: String? {
        switch flowSession.sessionPhase {
        case .idle:           return nil
        case .recording:      return "Recording…"
        case .transcribing:   return "Transcribing…"
        case .done(let text): return "Done: \"\(text.prefix(40))\""
        }
    }

    // MARK: - Model Section

    private var modelSection: some View {
        Section {
            if viewModel.isLoadingModel {
                HStack {
                    ProgressView()
                    Text("Loading model…")
                        .foregroundColor(.secondary)
                }
            } else if let name = viewModel.loadedModelName {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text(name)
                        .font(.subheadline)
                    Spacer()
                    Button("Change") { viewModel.showModelPicker = true }
                        .font(.subheadline)
                }
            } else {
                Button {
                    viewModel.showModelPicker = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.accentColor)
                        Text("Select & Download Model")
                    }
                }
            }
        } header: {
            Text("On-Device STT Model")
        } footer: {
            Text("Recommended: Sherpa Whisper Tiny (75 MB). All transcription runs fully on-device.")
        }
    }

    // MARK: - Setup Instructions

    private var setupSection: some View {
        Section("Keyboard Setup") {
            SetupStep(
                number: 1,
                title: "Add the Keyboard",
                detail: "Settings → General → Keyboard → Keyboards → Add New Keyboard → RunAnywhereKeyboard"
            )
            SetupStep(
                number: 2,
                title: "Grant Full Access",
                detail: "Tap RunAnywhereKeyboard → enable 'Allow Full Access' (required for App Group IPC and mic prompt)."
            )
            SetupStep(
                number: 3,
                title: "Use in Any App",
                detail: "Switch to the RunAnywhere keyboard, tap 'Dictate', speak, and text is inserted automatically."
            )
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        Section {
            ForEach(viewModel.dictationHistory.prefix(20)) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.text)
                        .font(.subheadline)
                        .lineLimit(2)
                    Text(entry.date, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            HStack {
                Text("Recent Dictations")
                Spacer()
                Button("Clear", role: .destructive) {
                    viewModel.clearHistory()
                }
                .font(.caption)
            }
        }
    }
}

// MARK: - Supporting Views

private struct StatusRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let action: (() -> Void)?
    let actionLabel: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24)
            Text(label)
            Spacer()
            if let action = action {
                Button(actionLabel, action: action)
                    .font(.subheadline)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct SetupStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(Color.accentColor)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        VoiceDictationManagementView()
            .environmentObject(FlowSessionManager.shared)
    }
}

#endif
