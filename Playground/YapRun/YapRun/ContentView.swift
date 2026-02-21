//
//  ContentView.swift
//  YapRun
//
//  Home screen: model download, keyboard setup instructions, dictation history.
//

#if os(iOS)
import SwiftUI
import RunAnywhere
import AVFoundation
import os

struct ContentView: View {
    @EnvironmentObject private var flowSession: FlowSessionManager

    @State private var micPermission: MicPermission = .unknown
    @State private var modelState: ModelState = .notDownloaded
    @State private var dictationHistory: [DictationEntry] = []
    @State private var errorMessage: String?

    private let logger = Logger(subsystem: "com.runanywhere.yaprun", category: "Home")

    var body: some View {
        NavigationStack {
            List {
                statusSection
                modelSection
                setupSection
                if !dictationHistory.isEmpty {
                    historySection
                }
                poweredBySection
            }
            .navigationTitle("YapRun")
            .navigationBarTitleDisplayMode(.large)
            .task { await refresh() }
            .refreshable { await refresh() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                Task { await refresh() }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section("Status") {
            HStack(spacing: 12) {
                Image(systemName: micPermission.icon)
                    .foregroundColor(micPermission.color)
                    .frame(width: 24)
                Text("Microphone")
                Spacer()
                if micPermission == .unknown {
                    Button("Allow") {
                        Task { await requestMicPermission() }
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Text(micPermission.label)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if let phase = sessionPhaseLabel {
                HStack(spacing: 12) {
                    ProgressView().scaleEffect(0.85)
                    Text(phase)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var sessionPhaseLabel: String? {
        switch flowSession.sessionPhase {
        case .idle:           return nil
        case .activating:     return "Starting microphone..."
        case .ready:          return "Mic ready — tap mic icon to dictate"
        case .listening:      return "Listening..."
        case .transcribing:   return "Transcribing..."
        case .done(let text): return "Done: \"\(text.prefix(40))\""
        }
    }

    // MARK: - Model Section

    private var modelSection: some View {
        Section {
            switch modelState {
            case .notDownloaded:
                Button {
                    Task { await downloadAndLoadModel() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.accentColor)
                        Text("Download Whisper Tiny (75 MB)")
                    }
                }

            case .downloading:
                HStack {
                    ProgressView()
                    Text("Downloading model...")
                        .foregroundColor(.secondary)
                }

            case .loading:
                HStack {
                    ProgressView()
                    Text("Loading model...")
                        .foregroundColor(.secondary)
                }

            case .ready(let name):
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text(name)
                        .font(.subheadline)
                    Spacer()
                }
            }
        } header: {
            Text("On-Device STT Model")
        } footer: {
            Text("Sherpa Whisper Tiny — all transcription runs fully on-device, no data leaves your phone.")
        }
    }

    // MARK: - Setup Section

    private var setupSection: some View {
        Section("Keyboard Setup") {
            setupStep(1, title: "Add the Keyboard",
                      detail: "Settings → General → Keyboard → Keyboards → Add New Keyboard → YapRunKeyboard")
            setupStep(2, title: "Grant Full Access",
                      detail: "Tap YapRunKeyboard → enable 'Allow Full Access' (required for mic and App Group IPC).")
            setupStep(3, title: "Use in Any App",
                      detail: "Switch to the YapRun keyboard, tap 'Yap', speak, and text is inserted automatically.")
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        Section {
            ForEach(dictationHistory.prefix(20)) { entry in
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
                Button("Clear", role: .destructive) { clearHistory() }
                    .font(.caption)
            }
        }
    }

    // MARK: - Powered By

    private static let sdkURL = URL(string: "https://github.com/RunanywhereAI/runanywhere-sdks")!

    private var poweredBySection: some View {
        Section {
            Link(destination: Self.sdkURL) {
                HStack(spacing: 10) {
                    Image("runanywhere_logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Powered by RunAnywhere SDKs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("github.com/RunanywhereAI")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Helpers

    private func setupStep(_ number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(Color(.systemGray))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func refresh() async {
        await checkMicPermission()
        await checkModel()
        loadHistory()
    }

    private func checkMicPermission() async {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:      micPermission = .granted
        case .denied:       micPermission = .denied
        case .undetermined: micPermission = .unknown
        @unknown default:   micPermission = .unknown
        }
    }

    private func requestMicPermission() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        micPermission = granted ? .granted : .denied
    }

    private func checkModel() async {
        if let model = await RunAnywhere.currentSTTModel {
            modelState = .ready(model.name)
        } else if SharedDataBridge.shared.preferredSTTModelId != nil {
            modelState = .notDownloaded
        }
    }

    private func downloadAndLoadModel() async {
        let modelId = "sherpa-onnx-whisper-tiny.en"
        modelState = .downloading

        do {
            modelState = .loading
            try await RunAnywhere.loadSTTModel(modelId)
            SharedDataBridge.shared.preferredSTTModelId = modelId
            if let model = await RunAnywhere.currentSTTModel {
                modelState = .ready(model.name)
            }
            logger.info("STT model loaded successfully")
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            logger.error("Model load failed: \(error.localizedDescription)")
            modelState = .notDownloaded
        }
    }

    private func loadHistory() {
        guard let defaults = SharedDataBridge.shared.defaults,
              let data = defaults.data(forKey: SharedConstants.Keys.dictationHistory),
              let entries = try? JSONDecoder().decode([DictationEntry].self, from: data) else {
            dictationHistory = []
            return
        }
        dictationHistory = entries
    }

    private func clearHistory() {
        SharedDataBridge.shared.defaults?.removeObject(forKey: SharedConstants.Keys.dictationHistory)
        dictationHistory = []
    }
}

// MARK: - Supporting Types

private enum MicPermission {
    case unknown, granted, denied

    var label: String {
        switch self {
        case .unknown: return "Not determined"
        case .granted: return "Granted"
        case .denied:  return "Denied"
        }
    }

    var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .granted: return "checkmark.circle.fill"
        case .denied:  return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .unknown: return .orange
        case .granted: return .green
        case .denied:  return .red
        }
    }
}

private enum ModelState {
    case notDownloaded
    case downloading
    case loading
    case ready(String)
}

#endif
