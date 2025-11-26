import SwiftUI
import RunAnywhere
import AVFoundation
import os

/// Dedicated Text-to-Speech view with text input and playback
struct TextToSpeechView: View {
    @StateObject private var viewModel = TTSViewModel()
    @State private var showModelPicker = false
    @State private var inputText: String = "Hello! This is a text to speech test."

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    Text("Text to Speech")
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()

                    // Model selector
                    Button(action: { showModelPicker = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "speaker.wave.2")
                                .font(.caption)
                            Text(viewModel.selectedModelName ?? "Select Model")
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.purple.opacity(0.1))
                        .foregroundColor(.purple)
                        .cornerRadius(8)
                    }
                }

                // Status indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemBackground))

            Divider()

            // Input and output area
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Text input section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Enter Text")
                            .font(.headline)
                            .foregroundColor(.primary)

                        TextEditor(text: $inputText)
                            .font(.body)
                            .padding(12)
                            .frame(minHeight: 120)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )

                        Text("\(inputText.count) characters")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Voice settings
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Voice Settings")
                            .font(.headline)
                            .foregroundColor(.primary)

                        // Speech rate
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Speed")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.1fx", viewModel.speechRate))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $viewModel.speechRate, in: 0.5...2.0, step: 0.1)
                                .tint(.blue)
                        }

                        // Pitch
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Pitch")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.1fx", viewModel.pitch))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $viewModel.pitch, in: 0.5...2.0, step: 0.1)
                                .tint(.purple)
                        }
                    }
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(12)

                    // Generated audio info
                    if let metadata = viewModel.metadata {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Audio Info")
                                .font(.headline)
                                .foregroundColor(.primary)

                            VStack(alignment: .leading, spacing: 4) {
                                metadataRow(icon: "waveform", label: "Duration", value: String(format: "%.2fs", metadata.durationMs / 1000))
                                metadataRow(icon: "doc.text", label: "Size", value: formatBytes(metadata.audioSize))
                                metadataRow(icon: "speaker.wave.2", label: "Sample Rate", value: "\(metadata.sampleRate) Hz")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }

            Divider()

            // Controls
            VStack(spacing: 16) {
                // Error message
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Playback progress
                if viewModel.isPlaying {
                    HStack {
                        Text(formatTime(viewModel.currentTime))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ProgressView(value: viewModel.playbackProgress)
                            .tint(.purple)

                        Text(formatTime(viewModel.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 40)
                }

                // Action buttons
                HStack(spacing: 20) {
                    // Generate button
                    Button(action: {
                        Task {
                            await viewModel.generateSpeech(text: inputText)
                        }
                    }) {
                        HStack {
                            if viewModel.isGenerating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "waveform.circle.fill")
                                    .font(.system(size: 20))
                            }
                            Text("Generate")
                                .fontWeight(.semibold)
                        }
                        .frame(width: 140, height: 50)
                        .background(inputText.isEmpty || viewModel.selectedModelName == nil ? Color.gray : Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(25)
                    }
                    .disabled(inputText.isEmpty || viewModel.selectedModelName == nil || viewModel.isGenerating)

                    // Play/Stop button
                    Button(action: {
                        Task {
                            await viewModel.togglePlayback()
                        }
                    }) {
                        HStack {
                            Image(systemName: viewModel.isPlaying ? "stop.fill" : "play.fill")
                                .font(.system(size: 20))
                            Text(viewModel.isPlaying ? "Stop" : "Play")
                                .fontWeight(.semibold)
                        }
                        .frame(width: 140, height: 50)
                        .background(viewModel.hasGeneratedAudio ? Color.green : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(25)
                    }
                    .disabled(!viewModel.hasGeneratedAudio)
                }

                Text(viewModel.isGenerating ? "Generating speech..." : viewModel.isPlaying ? "Playing..." : "Ready")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .sheet(isPresented: $showModelPicker) {
            TTSModelPickerView(
                selectedModelId: $viewModel.selectedModelId,
                onSelect: { modelInfo in
                    Task {
                        await viewModel.loadModel(modelInfo)
                    }
                }
            )
        }
        .onAppear {
            Task {
                await viewModel.initialize()
            }
        }
    }

    private var statusColor: Color {
        if viewModel.isGenerating {
            return .orange
        } else if viewModel.isPlaying {
            return .green
        } else if viewModel.selectedModelName != nil {
            return .green
        } else {
            return .gray
        }
    }

    private var statusText: String {
        if viewModel.isGenerating {
            return "Generating..."
        } else if viewModel.isPlaying {
            return "Playing"
        } else if viewModel.selectedModelName != nil {
            return "Ready"
        } else {
            return "No model selected"
        }
    }

    @ViewBuilder
    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 16)
            Text(label + ":")
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024.0
        if kb < 1024 {
            return String(format: "%.1f KB", kb)
        } else {
            return String(format: "%.1f MB", kb / 1024.0)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - View Model

@MainActor
class TTSViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere", category: "TTS")

    @Published var selectedModelName: String?
    @Published var selectedModelId: String?
    @Published var isGenerating = false
    @Published var isPlaying = false
    @Published var hasGeneratedAudio = false
    @Published var errorMessage: String?
    @Published var metadata: TTSMetadata?
    @Published var speechRate: Double = 1.0
    @Published var pitch: Double = 1.0
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 0.0
    @Published var playbackProgress: Double = 0.0

    private var ttsComponent: TTSComponent?
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?

    func initialize() async {
        logger.info("Initializing TTS view model")

        // Configure audio session for playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    func loadModel(_ modelInfo: (name: String, id: String)) async {
        self.logger.info("Loading TTS model: \(modelInfo.name) (id: \(modelInfo.id))")
        isGenerating = true
        errorMessage = nil

        do {
            // Create TTS component with the selected Piper model
            // Use the model ID as the voice identifier for Piper models
            let config = TTSConfiguration(
                voice: modelInfo.id,  // Piper model ID
                language: "en-US",
                speakingRate: Float(speechRate),
                pitch: Float(pitch),
                volume: 1.0
            )

            let component = TTSComponent(configuration: config)
            try await component.initialize()

            ttsComponent = component
            selectedModelName = modelInfo.name
            selectedModelId = modelInfo.id
            self.logger.info("TTS model loaded successfully: \(modelInfo.name)")
        } catch {
            self.logger.error("Failed to load TTS model: \(error.localizedDescription)")
            errorMessage = "Failed to load model: \(error.localizedDescription)"
        }

        isGenerating = false
    }

    func generateSpeech(text: String) async {
        logger.info("Generating speech for text: \(text)")
        isGenerating = true
        errorMessage = nil
        hasGeneratedAudio = false

        do {
            guard let component = ttsComponent else {
                throw NSError(domain: "TTS", code: -1, userInfo: [NSLocalizedDescriptionKey: "No TTS component loaded"])
            }

            // Use framework-agnostic TTSComponent
            let output = try await component.synthesize(text, language: "en-US")

            // Create audio player from generated audio
            try await createAudioPlayer(from: output.audioData)

            // Set metadata
            metadata = TTSMetadata(
                durationMs: output.duration * 1000,
                audioSize: output.audioData.count,
                sampleRate: 22050
            )

            hasGeneratedAudio = true
            duration = output.duration
            logger.info("Speech generation complete")
        } catch {
            logger.error("Speech generation failed: \(error.localizedDescription)")
            errorMessage = "Generation failed: \(error.localizedDescription)"
        }

        isGenerating = false
    }

    func togglePlayback() async {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard let player = audioPlayer else { return }

        player.play()
        isPlaying = true

        // Start playback timer
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer else { return }

            Task { @MainActor in
                self.currentTime = player.currentTime
                self.playbackProgress = player.currentTime / player.duration
            }

            if !player.isPlaying {
                Task { @MainActor in
                    self.stopPlayback()
                }
            }
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentTime = 0
        playbackProgress = 0

        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func createAudioPlayer(from audioData: Data) async throws {
        // Stop current playback
        stopPlayback()

        // Create audio player
        audioPlayer = try AVAudioPlayer(data: audioData)
        audioPlayer?.prepareToPlay()
    }
}

// MARK: - Supporting Types

struct TTSMetadata {
    let durationMs: Double
    let audioSize: Int
    let sampleRate: Int
}

// MARK: - TTS Model Picker

struct TTSModelPickerView: View {
    @Binding var selectedModelId: String?
    let onSelect: ((name: String, id: String)) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var availableModels: [ModelInfo] = []
    @State private var isLoading = true
    @State private var downloadingModels: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading models...")
                } else if availableModels.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tray")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No TTS models available")
                            .font(.headline)
                        Text("No models registered in SDK")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        if let error = errorMessage {
                            Section {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }

                        Section {
                            ForEach(availableModels, id: \.id) { model in
                                TTSModelRow(
                                    model: model,
                                    isSelected: selectedModelId == model.id,
                                    isDownloading: downloadingModels.contains(model.id),
                                    onTap: {
                                        if model.isDownloaded {
                                            onSelect((name: model.name, id: model.id))
                                            dismiss()
                                        } else {
                                            Task {
                                                await downloadModel(model)
                                            }
                                        }
                                    }
                                )
                            }
                        } header: {
                            Text("Available Models")
                        } footer: {
                            Text("Tap to download. Once downloaded, tap again to select.")
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Select TTS Model")
            .navigationBarItems(trailing: Button("Cancel") { dismiss() })
        }
        .onAppear {
            Task {
                await loadModels()
            }
        }
    }

    private func downloadModel(_ model: ModelInfo) async {
        downloadingModels.insert(model.id)
        errorMessage = nil

        do {
            try await RunAnywhere.downloadModel(model.id)
            // Refresh models list after download
            await loadModels()
            downloadingModels.remove(model.id)
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
            downloadingModels.remove(model.id)
        }
    }

    private func loadModels() async {
        // Load downloadable Piper TTS models from SDK registry
        do {
            let allModels = try await RunAnywhere.availableModels()
            // Filter for TTS models (Piper ONNX models)
            availableModels = allModels.filter { $0.category == .speechSynthesis }
            print("Loaded \(availableModels.count) TTS models")
        } catch {
            print("Failed to load TTS models: \(error)")
            availableModels = []
        }
        isLoading = false
    }
}

// MARK: - TTS Model Row Component

private struct TTSModelRow: View {
    let model: ModelInfo
    let isSelected: Bool
    let isDownloading: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        if let size = model.downloadSize {
                            Label(
                                ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                                systemImage: "arrow.down.circle"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }

                        // Status badge
                        statusBadge
                    }
                }

                Spacer()

                if isSelected && model.isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.purple)
                        .font(.title3)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDownloading)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if model.isDownloaded {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                Text("Downloaded")
            }
            .font(.caption)
            .foregroundColor(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
        } else if isDownloading {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Downloading...")
            }
            .font(.caption)
            .foregroundColor(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        } else {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                    .font(.caption)
                Text("Tap to Download")
            }
            .font(.caption)
            .foregroundColor(.purple)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.1))
            .cornerRadius(8)
        }
    }
}
