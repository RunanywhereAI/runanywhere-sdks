import SwiftUI
import RunAnywhere
import AVFoundation
import os

/// Dedicated Speech-to-Text view with real-time transcription
struct SpeechToTextView: View {
    @StateObject private var viewModel = STTViewModel()
    @State private var showModelPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    Text("Speech to Text")
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()

                    // Model selector
                    Button(action: { showModelPicker = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .font(.caption)
                            Text(viewModel.selectedModelName ?? "Select Model")
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
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

            // Transcription display
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if viewModel.transcription.isEmpty && !viewModel.isRecording {
                        // Empty state
                        VStack(spacing: 16) {
                            Image(systemName: "mic.circle")
                                .font(.system(size: 64))
                                .foregroundColor(.secondary.opacity(0.3))

                            Text("Tap the microphone to start")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            Text("Your speech will appear here in real-time")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                    } else {
                        // Live transcription
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Transcription")
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Spacer()

                                if viewModel.isRecording {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 8, height: 8)
                                        Text("LIVE")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.red)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(4)
                                }
                            }

                            Text(viewModel.transcription)
                                .font(.body)
                                .foregroundColor(.primary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)

                            // Metadata - TODO: Re-enable when metadata is available
                            // if let metadata = viewModel.metadata {
                            //     VStack(alignment: .leading, spacing: 4) {
                            //         metadataRow(icon: "clock", label: "Processing", value: String(format: "%.0fms", metadata.processingTimeMs))
                            //         metadataRow(icon: "waveform", label: "Audio Duration", value: String(format: "%.1fs", metadata.audioDurationMs / 1000))
                            //         metadataRow(icon: "speedometer", label: "Real-time Factor", value: String(format: "%.2fx", metadata.realTimeFactor))
                            //     }
                            //     .font(.caption)
                            //     .foregroundColor(.secondary)
                            //     .padding()
                            //     .background(Color(.tertiarySystemBackground))
                            //     .cornerRadius(8)
                            // }
                        }
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

                // Audio level indicator
                if viewModel.isRecording {
                    HStack(spacing: 4) {
                        ForEach(0..<10, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(index < Int(viewModel.audioLevel * 10) ? Color.green : Color.gray.opacity(0.3))
                                .frame(width: 25, height: 8)
                        }
                    }
                }

                // Record button
                Button(action: {
                    Task {
                        await viewModel.toggleRecording()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(viewModel.isRecording ? Color.red : Color.blue)
                            .frame(width: 72, height: 72)

                        if viewModel.isProcessing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                        }
                    }
                }
                .disabled(viewModel.selectedModelName == nil || viewModel.isProcessing)

                Text(viewModel.isRecording ? "Tap to stop recording" : "Tap to start recording")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .sheet(isPresented: $showModelPicker) {
            STTModelPickerView(
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
        if viewModel.isRecording {
            return .red
        } else if viewModel.isProcessing {
            return .orange
        } else if viewModel.selectedModelName != nil {
            return .green
        } else {
            return .gray
        }
    }

    private var statusText: String {
        if viewModel.isRecording {
            return "Recording..."
        } else if viewModel.isProcessing {
            return "Processing..."
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
}

// MARK: - View Model

@MainActor
class STTViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere", category: "STT")

    @Published var selectedModelName: String?
    @Published var selectedModelId: String?
    @Published var transcription: String = ""
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var audioLevel: Float = 0.0
    @Published var errorMessage: String?

    private var sttComponent: STTComponent?
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioBuffer = Data()
    private var streamingTask: Task<Void, Never>?
    private var audioContinuation: AsyncStream<Data>.Continuation?

    func initialize() async {
        logger.info("Initializing STT view model")

        // Request microphone permission
        let status = AVAudioApplication.shared.recordPermission
        if status != .granted {
            await AVAudioApplication.requestRecordPermission()
        }
    }

    func loadModel(_ modelInfo: (name: String, id: String)) async {
        logger.info("Loading STT model: \(modelInfo.name) (id: \(modelInfo.id))")
        isProcessing = true
        errorMessage = nil

        do {
            // Create STT component with framework-agnostic configuration
            let config = STTConfiguration(
                modelId: modelInfo.id,
                language: "en",
                enablePunctuation: true,
                enableDiarization: false
            )

            let component = STTComponent(configuration: config)
            try await component.initialize()

            sttComponent = component
            selectedModelName = modelInfo.name
            selectedModelId = modelInfo.id
            logger.info("STT model loaded successfully")
        } catch {
            logger.error("Failed to load STT model: \(error.localizedDescription)")
            errorMessage = "Failed to load model: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    func startRecording() async {
        logger.info("Starting recording")
        errorMessage = nil
        audioBuffer = Data()
        transcription = ""

        guard let component = sttComponent else {
            errorMessage = "No STT model loaded"
            return
        }

        do {
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true)

            // Create audio engine FIRST
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            print("[AUDIO-ENGINE] Input format: sampleRate=\(inputFormat.sampleRate), channels=\(inputFormat.channelCount), isInterleaved=\(inputFormat.isInterleaved)")

            // Create audio stream for real-time transcription
            let audioStream = AsyncStream<Data> { continuation in
                self.audioContinuation = continuation
            }

            // Install tap to capture audio and send to stream
            print("[AUDIO-ENGINE] Installing tap on input node...")
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                print("[AUDIO-TAP] Callback invoked! frameLength=\(buffer.frameLength)")
                guard let self = self else {
                    print("[AUDIO-TAP] self is nil, returning")
                    return
                }

                // Convert buffer to Data - check if we have float or int16 data
                let data: Data?
                if let floatData = buffer.floatChannelData {
                    // Float format
                    let frameCount = Int(buffer.frameLength)
                    let channelCount = Int(buffer.format.channelCount)
                    var samples: [Int16] = []
                    samples.reserveCapacity(frameCount * channelCount)

                    // Convert float to int16
                    for channel in 0..<channelCount {
                        let channelBuffer = floatData[channel]
                        for frame in 0..<frameCount {
                            let sample = channelBuffer[frame]
                            let int16Sample = Int16(max(-1.0, min(1.0, sample)) * Float(Int16.max))
                            samples.append(int16Sample)
                        }
                    }

                    data = Data(bytes: samples, count: samples.count * MemoryLayout<Int16>.size)
                    print("[AUDIO-TAP] Converted float to int16, data size: \(data?.count ?? 0) bytes")
                } else if let int16Data = buffer.int16ChannelData {
                    // Int16 format (already what we need)
                    let dataSize = Int(buffer.frameLength * buffer.format.streamDescription.pointee.mBytesPerFrame)
                    data = Data(bytes: int16Data.pointee, count: dataSize)
                    print("[AUDIO-TAP] Already int16, data size: \(data?.count ?? 0) bytes")
                } else {
                    print("[AUDIO-TAP] ERROR: No audio data available!")
                    data = nil
                }

                if let audioData = data {
                    Task { @MainActor in
                        // Send audio chunk to streaming transcription
                        print("[AUDIO-TAP] Yielding audio chunk: \(audioData.count) bytes")
                        self.audioContinuation?.yield(audioData)

                        self.audioBuffer.append(audioData)

                        // Calculate audio level for visualization
                        if let floatData = buffer.floatChannelData {
                            var sum: Float = 0.0
                            for i in 0..<Int(buffer.frameLength) {
                                let sample = floatData.pointee[i]
                                sum += sample * sample
                            }
                            let rms = sqrt(sum / Float(buffer.frameLength))
                            let dbLevel = 20 * log10(rms + 0.0001)
                            self.audioLevel = max(0, min(1, (dbLevel + 60) / 60))
                        }
                    }
                }
            }
            print("[AUDIO-ENGINE] Tap installed successfully")

            // Start the audio engine
            print("[AUDIO-ENGINE] Starting audio engine...")
            try engine.start()
            print("[AUDIO-ENGINE] Audio engine started successfully, isRunning=\(engine.isRunning)")

            self.audioEngine = engine
            self.inputNode = inputNode
            isRecording = true

            // NOW start streaming transcription task (AFTER audio engine is running)
            streamingTask = Task { @MainActor in
                do {
                    print("[STREAMING-TASK] Starting transcription stream consumption")
                    let transcriptionStream = component.streamTranscribe(audioStream, language: "en")

                    for try await partialText in transcriptionStream {
                        // Update transcription in real-time
                        self.transcription = partialText
                        self.logger.debug("Partial transcription: \(partialText)")
                    }
                    print("[STREAMING-TASK] Transcription stream completed")
                } catch {
                    self.logger.error("Streaming transcription failed: \(error.localizedDescription)")
                    self.errorMessage = "Streaming failed: \(error.localizedDescription)"
                }
            }

        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() async {
        logger.info("Stopping recording")

        // Stop audio engine
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil

        // Finish the audio stream
        audioContinuation?.finish()
        audioContinuation = nil

        // Cancel streaming task
        streamingTask?.cancel()
        streamingTask = nil

        try? AVAudioSession.sharedInstance().setActive(false)

        isRecording = false
        audioLevel = 0.0

        logger.info("Recording stopped. Transcription: \(self.transcription)")
    }
}

// MARK: - Model Picker

struct STTModelPickerView: View {
    @Binding var selectedModelId: String?
    let onSelect: ((name: String, id: String)) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var availableModels: [ModelInfo] = []
    @State private var isLoading = true
    @State private var downloadingModels: Set<String> = []
    @State private var errorMessage: String?
    @State private var selectedFramework: LLMFramework = .whisperKit  // Default to WhisperKit (working)

    var filteredModels: [ModelInfo] {
        availableModels.filter { $0.preferredFramework == selectedFramework }
    }

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
                        Text("No STT models available")
                            .font(.headline)
                        Text("No models registered in SDK")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        // Framework selector
                        Section {
                            Picker("Framework", selection: $selectedFramework) {
                                Text("ONNX Runtime").tag(LLMFramework.onnx)
                                Text("WhisperKit").tag(LLMFramework.whisperKit)
                            }
                            .pickerStyle(.segmented)

                            if selectedFramework == .onnx {
                                Text("⚠️ ONNX STT requires sherpa-onnx integration (coming soon). Use WhisperKit for now.")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        } header: {
                            Text("Select Framework")
                        }

                        if let error = errorMessage {
                            Section {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }

                        Section {
                            ForEach(filteredModels, id: \.id) { model in
                                STTModelRow(
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
            .navigationTitle("Select STT Model")
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
        do {
            // Query ALL models from SDK registry filtered by speech recognition category
            // Show both downloaded and available-to-download models
            let allModels = try await RunAnywhere.availableModels()
            availableModels = allModels.filter { $0.category == .speechRecognition }
            isLoading = false
        } catch {
            print("Failed to load STT models: \(error)")
            availableModels = []
            isLoading = false
        }
    }
}

// MARK: - Model Row Component

private struct STTModelRow: View {
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
                        .foregroundColor(.blue)
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
            .foregroundColor(.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }
}
