import SwiftUI
import RunAnywhere
import AVFoundation
import os

// Using STTMode from RunAnywhere SDK

/// Dedicated Speech-to-Text view with real-time transcription
struct SpeechToTextView: View {
    @StateObject private var viewModel = STTViewModel()
    @State private var showModelPicker = false

    private var hasModelSelected: Bool {
        viewModel.selectedModelName != nil
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header with title
                HStack {
                    Text("Speech to Text")
                        .font(.title2)
                        .fontWeight(.bold)

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top)

                // Model Status Banner - Always visible
                ModelStatusBanner(
                    framework: viewModel.selectedFramework,
                    modelName: viewModel.selectedModelName,
                    isLoading: viewModel.isProcessing && viewModel.selectedModelName == nil,
                    onSelectModel: { showModelPicker = true }
                )
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Mode selection - Batch vs Live
                if hasModelSelected {
                    Picker("Mode", selection: $viewModel.selectedMode) {
                        Text("Batch").tag(STTMode.batch)
                        Text("Live").tag(STTMode.live)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                    HStack {
                        Image(systemName: viewModel.selectedMode.icon)
                            .foregroundColor(.secondary)
                        Text(viewModel.selectedMode.description)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !viewModel.supportsLiveMode && viewModel.selectedMode == .live {
                            Text("(will use batch)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal)
                }

                Divider()

                // Main content - only enabled when model is selected
                if hasModelSelected {
                    // Transcription display
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if viewModel.transcription.isEmpty && !viewModel.isRecording && !viewModel.isTranscribing {
                                // Ready state
                                VStack(spacing: 16) {
                                    Image(systemName: "mic.circle")
                                        .font(.system(size: 64))
                                        .foregroundColor(.green.opacity(0.5))

                                    Text("Ready to transcribe")
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    Text("Tap the microphone button to start recording")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
                            } else if viewModel.isTranscribing && viewModel.transcription.isEmpty {
                                // Processing state (batch mode)
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .scaleEffect(1.5)

                                    Text("Processing audio...")
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    Text("Transcribing your recording")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 80)
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
                                        Text("RECORDING")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.red)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(4)
                                } else if viewModel.isTranscribing {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                        Text("TRANSCRIBING")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.orange)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.1))
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
                            .fill(viewModel.isRecording ? Color.red : (viewModel.isTranscribing ? Color.orange : Color.blue))
                            .frame(width: 72, height: 72)

                        if viewModel.isProcessing || viewModel.isTranscribing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                        }
                    }
                }
                .disabled(viewModel.selectedModelName == nil || viewModel.isProcessing || viewModel.isTranscribing)

                Text(viewModel.isTranscribing ? "Processing transcription..." : (viewModel.isRecording ? "Tap to stop recording" : "Tap to start recording"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
                .padding()
                .background(Color(.systemBackground))
                } else {
                    // No model selected - show onboarding
                    Spacer()
                }
            }

            // Overlay when no model is selected
            if !hasModelSelected && !viewModel.isProcessing {
                ModelRequiredOverlay(
                    modality: .stt,
                    onSelectModel: { showModelPicker = true }
                )
            }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelSelectionSheet(context: .stt) { model in
                Task {
                    await viewModel.loadModelFromSelection(model)
                }
            }
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

    // MARK: - Published Properties
    @Published var selectedFramework: LLMFramework?
    @Published var selectedModelName: String?
    @Published var selectedModelId: String?
    @Published var transcription: String = ""
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var isTranscribing = false
    @Published var audioLevel: Float = 0.0
    @Published var errorMessage: String?
    @Published var selectedMode: STTMode = .batch

    // MARK: - Computed Properties

    /// Whether the underlying STT service supports true live/streaming transcription
    var supportsLiveMode: Bool {
        sttComponent?.supportsStreaming ?? false
    }

    // MARK: - Private Properties
    private var sttComponent: STTComponent?
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioBuffer = Data()
    private var streamingTask: Task<Void, Never>?
    private var audioContinuation: AsyncStream<Data>.Continuation?
    private var recordedSampleRate: Double = 48000

    // MARK: - Initialization

    func initialize() async {
        logger.info("Initializing STT view model")

        // Request microphone permission
        let status = AVAudioApplication.shared.recordPermission
        if status != .granted {
            await AVAudioApplication.requestRecordPermission()
        }
    }

    // MARK: - Model Loading

    /// Load model from ModelSelectionSheet selection
    func loadModelFromSelection(_ model: ModelInfo) async {
        logger.info("Loading STT model from selection: \(model.name)")
        isProcessing = true
        errorMessage = nil

        do {
            // Create STT component with framework-agnostic configuration
            let config = STTConfiguration(
                modelId: model.id,
                language: "en",
                enablePunctuation: true,
                enableDiarization: false
            )

            let component = STTComponent(configuration: config)
            try await component.initialize()

            sttComponent = component
            selectedFramework = model.preferredFramework
            selectedModelName = model.name
            selectedModelId = model.id
            logger.info("STT model loaded successfully: \(model.name)")
        } catch {
            logger.error("Failed to load STT model: \(error.localizedDescription)")
            errorMessage = "Failed to load model: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    /// Legacy method for STTModelPickerView compatibility
    func loadModel(_ modelInfo: (name: String, id: String)) async {
        logger.info("Loading STT model: \(modelInfo.name) (id: \(modelInfo.id))")
        isProcessing = true
        errorMessage = nil

        do {
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

    // MARK: - Recording

    func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    func startRecording() async {
        logger.info("Starting recording in \(self.selectedMode.rawValue) mode")
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

            // Create audio engine
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            recordedSampleRate = inputFormat.sampleRate

            if selectedMode == .live {
                // Live mode: Create audio stream for real-time transcription
                let audioStream = AsyncStream<Data> { continuation in
                    self.audioContinuation = continuation
                }

                // Install tap for live streaming
                inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                    guard let self = self else { return }
                    if let audioData = self.convertBufferToData(buffer) {
                        Task { @MainActor in
                            self.audioContinuation?.yield(audioData)
                            self.updateAudioLevel(buffer)
                        }
                    }
                }

                // Start streaming transcription task using SDK's liveTranscribe API
                streamingTask = Task { @MainActor in
                    do {
                        // Create options for live transcription
                        let options = STTOptions(
                            language: "en",
                            enablePunctuation: true,
                            audioFormat: .pcm,
                            sampleRate: 16000
                        )

                        // Use the SDK's liveTranscribe API
                        let transcriptionStream = component.liveTranscribe(audioStream, options: options)
                        for try await partialText in transcriptionStream {
                            self.transcription = partialText
                            self.logger.debug("Partial: \(partialText)")
                        }
                    } catch {
                        if !Task.isCancelled {
                            self.logger.error("Streaming failed: \(error.localizedDescription)")
                            self.errorMessage = "Streaming failed: \(error.localizedDescription)"
                        }
                    }
                }
            } else {
                // Batch mode: Just collect audio data
                inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                    guard let self = self else { return }
                    if let audioData = self.convertBufferToData(buffer) {
                        Task { @MainActor in
                            self.audioBuffer.append(audioData)
                            self.updateAudioLevel(buffer)
                        }
                    }
                }
            }

            // Start the audio engine
            try engine.start()

            self.audioEngine = engine
            self.inputNode = inputNode
            isRecording = true

        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    /// Convert AVAudioPCMBuffer to Data (Int16 PCM)
    private func convertBufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let floatData = buffer.floatChannelData else { return nil }

        let frameCount = Int(buffer.frameLength)
        var samples: [Int16] = []
        samples.reserveCapacity(frameCount)

        // Convert float to int16 (mono - use first channel)
        let channelBuffer = floatData[0]
        for frame in 0..<frameCount {
            let sample = channelBuffer[frame]
            let int16Sample = Int16(max(-1.0, min(1.0, sample)) * Float(Int16.max))
            samples.append(int16Sample)
        }

        return Data(bytes: samples, count: samples.count * MemoryLayout<Int16>.size)
    }

    /// Update audio level for visualization
    private func updateAudioLevel(_ buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }
        var sum: Float = 0.0
        for i in 0..<Int(buffer.frameLength) {
            let sample = floatData.pointee[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(buffer.frameLength))
        let dbLevel = 20 * log10(rms + 0.0001)
        audioLevel = max(0, min(1, (dbLevel + 60) / 60))
    }

    func stopRecording() async {
        logger.info("Stopping recording in \(self.selectedMode.rawValue) mode")

        // Stop audio engine first
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil

        isRecording = false
        audioLevel = 0.0

        if selectedMode == .live {
            // Live mode: Finish the audio stream and wait for transcription
            audioContinuation?.finish()
            audioContinuation = nil

            // Wait for streaming task to complete (don't cancel it!)
            if let task = streamingTask {
                _ = await task.result
            }
            streamingTask = nil
        } else {
            // Batch mode: Transcribe the collected audio
            await performBatchTranscription()
        }

        try? AVAudioSession.sharedInstance().setActive(false)
        logger.info("Recording stopped. Transcription: \(self.transcription)")
    }

    /// Perform batch transcription on collected audio
    private func performBatchTranscription() async {
        guard let component = sttComponent else {
            errorMessage = "No STT model loaded"
            return
        }

        guard !self.audioBuffer.isEmpty else {
            errorMessage = "No audio recorded"
            return
        }

        logger.info("Starting batch transcription of \(self.audioBuffer.count) bytes")
        isTranscribing = true
        transcription = ""

        do {
            // Create transcription options using the SDK's STTOptions
            let options = STTOptions(
                language: "en",
                enablePunctuation: true,
                audioFormat: .pcm,
                sampleRate: 16000  // STT models expect 16kHz
            )

            // Use the STT component's transcribe method with options
            let output = try await component.transcribe(audioBuffer, options: options)
            transcription = output.text
            logger.info("Batch transcription complete: \(output.text)")
        } catch {
            logger.error("Batch transcription failed: \(error.localizedDescription)")
            errorMessage = "Transcription failed: \(error.localizedDescription)"
        }

        isTranscribing = false
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
