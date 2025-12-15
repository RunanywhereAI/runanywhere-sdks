import SwiftUI
import RunAnywhere
import AVFoundation
import Combine
import os
#if os(macOS)
import AppKit
#endif

// MARK: - Local UI Types

/// STT Mode for UI selection
enum STTMode: String {
    case batch
    case live

    var icon: String {
        switch self {
        case .batch: return "square.stack.3d.up"
        case .live: return "waveform"
        }
    }

    var description: String {
        switch self {
        case .batch: return "Record first, then transcribe"
        case .live: return "Real-time transcription"
        }
    }
}

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
                                // Transcription display
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

                        // Audio level indicator
                        if viewModel.isRecording {
                            AdaptiveAudioLevelIndicator(level: viewModel.audioLevel)
                        }

                        // Record button
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
}

// MARK: - View Model

@MainActor
class STTViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere", category: "STT")
    private let audioCapture = AudioCaptureManager()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Published Properties
    @Published var selectedFramework: InferenceFramework?
    @Published var selectedModelName: String?
    @Published var selectedModelId: String?
    @Published var transcription: String = ""
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var isTranscribing = false
    @Published var audioLevel: Float = 0.0
    @Published var errorMessage: String?
    @Published var selectedMode: STTMode = .batch

    // MARK: - Private Properties
    private var audioBuffer = Data()

    // MARK: - Initialization

    func initialize() async {
        logger.info("Initializing STT view model")

        // Request microphone permission
        let hasPermission = await audioCapture.requestPermission()
        if !hasPermission {
            errorMessage = "Microphone permission denied"
            logger.error("Microphone permission denied")
            return
        }

        // Subscribe to audio level updates
        audioCapture.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.audioLevel = level
            }
            .store(in: &cancellables)

        // Subscribe to SDK events for STT model state
        subscribeToSDKEvents()

        // Check initial STT model state
        if let model = await RunAnywhere.currentSTTModel {
            selectedModelId = model.id
            selectedModelName = model.name
            selectedFramework = model.preferredFramework
            logger.info("STT model already loaded: \(model.name)")
        }
    }

    /// Subscribe to SDK events for STT model state updates
    private func subscribeToSDKEvents() {
        RunAnywhere.events.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleSDKEvent(event)
            }
            .store(in: &cancellables)
    }

    private func handleSDKEvent(_ event: any SDKEvent) {
        if let sttEvent = event as? STTEvent {
            switch sttEvent {
            case .modelLoadCompleted(let modelId, _, _):
                selectedModelId = modelId
                selectedModelName = modelId
                logger.info("STT model loaded: \(modelId)")
            case .modelUnloaded:
                selectedModelId = nil
                selectedModelName = nil
                selectedFramework = nil
                logger.info("STT model unloaded")
            default:
                break
            }
        }
    }

    // MARK: - Model Loading

    /// Load model from ModelSelectionSheet selection
    func loadModelFromSelection(_ model: ModelInfo) async {
        logger.info("Loading STT model from selection: \(model.name)")
        isProcessing = true
        errorMessage = nil

        do {
            try await RunAnywhere.loadSTTModel(model.id)
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

        guard selectedModelId != nil else {
            errorMessage = "No STT model loaded"
            return
        }

        do {
            try audioCapture.startRecording { [weak self] audioData in
                Task { @MainActor in
                    self?.audioBuffer.append(audioData)
                }
            }
            isRecording = true
            logger.info("Recording started")
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() async {
        logger.info("Stopping recording")

        // Stop audio capture
        audioCapture.stopRecording()
        isRecording = false
        audioLevel = 0.0

        // Perform batch transcription
        await performBatchTranscription()
    }

    /// Perform batch transcription on collected audio
    private func performBatchTranscription() async {
        guard !audioBuffer.isEmpty else {
            errorMessage = "No audio recorded"
            return
        }

        logger.info("Starting batch transcription of \(self.audioBuffer.count) bytes")
        isTranscribing = true
        transcription = ""

        do {
            let result = try await RunAnywhere.transcribe(audioBuffer)
            transcription = result
            logger.info("Batch transcription complete: \(result)")
        } catch {
            logger.error("Batch transcription failed: \(error.localizedDescription)")
            errorMessage = "Transcription failed: \(error.localizedDescription)"
        }

        isTranscribing = false
    }
}
