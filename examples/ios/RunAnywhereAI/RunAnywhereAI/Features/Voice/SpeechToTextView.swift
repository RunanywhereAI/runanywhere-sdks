import SwiftUI
import RunAnywhere
import AVFoundation
import Combine
import os
#if os(macOS)
import AppKit
#endif

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
                                #if os(iOS)
                                .background(Color(.secondarySystemBackground))
                                #else
                                .background(Color(NSColor.controlBackgroundColor))
                                #endif
                                .cornerRadius(12)
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

                // Audio level indicator - using adaptive sizing
                if viewModel.isRecording {
                    AdaptiveAudioLevelIndicator(level: viewModel.audioLevel)
                }

                // Record button - using adaptive sizing
                AdaptiveMicButton(
                    isActive: viewModel.isRecording,
                    isPulsing: false,
                    isLoading: viewModel.isProcessing || viewModel.isTranscribing,
                    activeColor: .red,
                    inactiveColor: viewModel.isTranscribing ? .orange : .blue,
                    icon: viewModel.isRecording ? "stop.fill" : "mic.fill"
                ) {
                    Task {
                        await viewModel.toggleRecording()
                    }
                }
                .disabled(viewModel.selectedModelName == nil || viewModel.isProcessing || viewModel.isTranscribing)
                .opacity(viewModel.selectedModelName == nil || viewModel.isProcessing || viewModel.isTranscribing ? 0.6 : 1.0)

                Text(viewModel.isTranscribing ? "Processing transcription..." : (viewModel.isRecording ? "Tap to stop recording" : "Tap to start recording"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
                .padding()
                #if os(iOS)
                .background(Color(.systemBackground))
                #else
                .background(Color(NSColor.windowBackgroundColor))
                #endif
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
    private var audioConverter: AVAudioConverter?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    func initialize() async {
        logger.info("Initializing STT view model")

        // Request microphone permission
        #if os(iOS)
        let status = AVAudioApplication.shared.recordPermission
        if status != .granted {
            await AVAudioApplication.requestRecordPermission()
        }
        #endif

        // Subscribe to model lifecycle changes from SDK
        subscribeToModelLifecycle()
    }

    /// Subscribe to SDK's model lifecycle tracker for real-time model state updates
    private func subscribeToModelLifecycle() {
        // Observe changes to loaded models via the SDK's lifecycle tracker
        ModelLifecycleTracker.shared.$modelsByModality
            .receive(on: DispatchQueue.main)
            .sink { [weak self] modelsByModality in
                guard let self = self else { return }

                // Update STT model state from SDK
                if let sttState = modelsByModality[.stt] {
                    if sttState.state.isLoaded {
                        self.selectedFramework = sttState.framework
                        self.selectedModelName = sttState.modelName
                        self.selectedModelId = sttState.modelId
                        self.logger.info("✅ STT model restored from SDK: \(sttState.modelName)")
                    }
                } else {
                    // Only clear if no model is loaded in SDK
                    if self.selectedModelId != nil {
                        self.logger.info("STT model unloaded from SDK")
                        self.selectedFramework = nil
                        self.selectedModelName = nil
                        self.selectedModelId = nil
                        self.sttComponent = nil
                    }
                }
            }
            .store(in: &cancellables)

        // Check initial state immediately
        let modelsByModality = ModelLifecycleTracker.shared.modelsByModality
        if let sttState = modelsByModality[.stt], sttState.state.isLoaded {
            selectedFramework = sttState.framework
            selectedModelName = sttState.modelName
            selectedModelId = sttState.modelId
            logger.info("✅ STT model found on init: \(sttState.modelName)")

            // Recreate component from existing SDK state if needed
            Task {
                await restoreComponentIfNeeded(modelId: sttState.modelId)
            }
        }
    }

    /// Restore the STT component if a model is already loaded in the SDK
    private func restoreComponentIfNeeded(modelId: String) async {
        // Only restore if we don't already have a component
        guard sttComponent == nil else { return }

        logger.info("Restoring STT component for model: \(modelId)")
        do {
            let config = STTConfiguration(
                modelId: modelId,
                language: "en",
                enablePunctuation: true,
                enableDiarization: false
            )

            let component = STTComponent(configuration: config)
            try await component.initialize()
            sttComponent = component
            logger.info("STT component restored successfully")
        } catch {
            logger.error("Failed to restore STT component: \(error.localizedDescription)")
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
            // Configure audio session (iOS only - macOS doesn't use AVAudioSession)
            #if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true)
            #endif

            // Create audio engine
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            // Create 16kHz mono output format (required by STT models)
            guard let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            ) else {
                errorMessage = "Failed to create audio format"
                return
            }

            // Create audio converter if sample rate or channel count differs
            let needsConversion = inputFormat.sampleRate != outputFormat.sampleRate ||
                                inputFormat.channelCount != outputFormat.channelCount
            if needsConversion {
                audioConverter = AVAudioConverter(from: inputFormat, to: outputFormat)
                logger.info("Audio converter created: \(inputFormat.sampleRate)Hz -> 16000Hz")
            } else {
                audioConverter = nil
            }

            if selectedMode == .live {
                // Live mode: Create audio stream for real-time transcription
                let audioStream = AsyncStream<Data> { continuation in
                    self.audioContinuation = continuation
                }

                // Install tap for live streaming with proper resampling
                inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                    guard let self = self else { return }
                    if let audioData = self.convertBufferToData(buffer, outputFormat: outputFormat) {
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
                // Batch mode: Collect audio data with proper resampling
                inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                    guard let self = self else { return }
                    if let audioData = self.convertBufferToData(buffer, outputFormat: outputFormat) {
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

    /// Convert AVAudioPCMBuffer to Data (Int16 PCM at 16kHz)
    /// - Parameters:
    ///   - buffer: Input audio buffer (may be at 48kHz or other sample rate)
    ///   - outputFormat: Target format (16kHz mono)
    /// - Returns: Int16 PCM data at 16kHz
    private func convertBufferToData(_ buffer: AVAudioPCMBuffer, outputFormat: AVAudioFormat) -> Data? {
        var processedBuffer = buffer

        // Resample to 16kHz if converter is available
        if let converter = audioConverter {
            let inputFormat = buffer.format
            let capacity = outputFormat.sampleRate * Double(buffer.frameLength) / inputFormat.sampleRate
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(capacity)
            ) else {
                return nil
            }

            var error: NSError?
            var inputBufferUsed = false
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                if inputBufferUsed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputBufferUsed = true
                outStatus.pointee = .haveData
                return buffer
            }

            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            if error == nil && convertedBuffer.frameLength > 0 {
                processedBuffer = convertedBuffer
            } else {
                return nil
            }
        }

        guard let floatData = processedBuffer.floatChannelData else { return nil }

        let frameCount = Int(processedBuffer.frameLength)
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
        audioConverter = nil

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

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
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
