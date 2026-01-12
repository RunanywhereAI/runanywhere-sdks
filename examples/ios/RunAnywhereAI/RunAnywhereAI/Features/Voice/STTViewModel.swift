//
//  STTViewModel.swift
//  RunAnywhereAI
//
//  ViewModel for Speech-to-Text functionality
//  Handles all business logic for STT including recording, transcription, and model management
//

import Foundation
import RunAnywhere
import Combine
import os

/// ViewModel for Speech-to-Text view
/// Manages recording, transcription, model selection, and microphone permissions
@MainActor
class STTViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.runanywhere", category: "STT")
    private let audioCapture = AudioCaptureManager()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Published Properties (UI State)

    @Published var selectedFramework: InferenceFramework?
    @Published var selectedModelName: String?
    @Published var selectedModelId: String?
    @Published var transcription: String = ""
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var isTranscribing = false
    @Published var audioLevel: Float = 0.0
    @Published var errorMessage: String?
    @Published var selectedMode: STTMode = .batch {
        didSet {
            // Stop any active recording/transcription when mode changes
            if oldValue != selectedMode {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if self.isRecording {
                        let msg = "Mode changed from \(oldValue.rawValue) to \(self.selectedMode.rawValue)"
                        self.logger.info("\(msg) - stopping active recording")
                        await self.stopRecording()
                    }
                    // Also clean up any lingering live transcription resources
                    if oldValue == .live {
                        await self.stopLiveTranscription()
                    }
                }
            }
        }
    }

    // MARK: - Private Properties

    private var audioBuffer = Data()

    /// For live mode: VAD-based transcription
    private var lastSpeechTime: Date?
    private var isSpeechActive = false
    private var silenceCheckTask: Task<Void, Never>?
    private let speechThreshold: Float = 0.02  // Audio level threshold for speech detection
    private let silenceDuration: TimeInterval = 1.5  // Seconds of silence before transcribing

    // MARK: - Initialization State (for idempotency)

    private var isInitialized = false
    private var hasSubscribedToAudioLevel = false
    private var hasSubscribedToSDKEvents = false

    // MARK: - Initialization

    init() {
        logger.debug("STTViewModel initialized")
    }

    // MARK: - Public Methods

    /// Initialize the ViewModel - request permissions and setup subscriptions
    /// This method is idempotent - calling it multiple times is safe
    func initialize() async {
        guard !isInitialized else {
            logger.debug("STT view model already initialized, skipping")
            return
        }
        isInitialized = true

        logger.info("Initializing STT view model")

        // Request microphone permission
        let hasPermission = await requestMicrophonePermission()
        if !hasPermission {
            errorMessage = "Microphone permission denied"
            logger.error("Microphone permission denied")
            return
        }

        // Subscribe to audio level updates (for batch mode)
        subscribeToAudioLevelUpdates()

        // Subscribe to SDK events for STT model state
        subscribeToSDKEvents()

        // Check initial STT model state
        await checkInitialModelState()
    }

    /// Load model from ModelSelectionSheet selection
    func loadModelFromSelection(_ model: ModelInfo) async {
        logger.info("Loading STT model from selection: \(model.name)")
        isProcessing = true
        errorMessage = nil

        do {
            try await RunAnywhere.loadSTTModel(model.id)
            selectedFramework = model.framework
            selectedModelName = model.name
            selectedModelId = model.id
            logger.info("STT model loaded successfully: \(model.name)")
        } catch {
            logger.error("Failed to load STT model: \(error.localizedDescription)")
            errorMessage = "Failed to load model: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    /// Toggle recording state (start/stop)
    func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    // MARK: - Private Methods - Permissions

    private func requestMicrophonePermission() async -> Bool {
        await audioCapture.requestPermission()
    }

    // MARK: - Private Methods - Subscriptions

    private func subscribeToAudioLevelUpdates() {
        guard !hasSubscribedToAudioLevel else {
            logger.debug("Already subscribed to audio level updates, skipping")
            return
        }
        hasSubscribedToAudioLevel = true

        audioCapture.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                // Defer state modifications to avoid "Publishing changes within view updates" warning
                Task { @MainActor in
                    self?.audioLevel = level
                }
            }
            .store(in: &cancellables)
    }

    private func subscribeToSDKEvents() {
        guard !hasSubscribedToSDKEvents else {
            logger.debug("Already subscribed to SDK events, skipping")
            return
        }
        hasSubscribedToSDKEvents = true

        RunAnywhere.events.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                // Defer state modifications to avoid "Publishing changes within view updates" warning
                Task { @MainActor in
                    self?.handleSDKEvent(event)
                }
            }
            .store(in: &cancellables)
    }

    private func handleSDKEvent(_ event: any SDKEvent) {
        // Events now come from C++ via generic BridgedEvent
        guard event.category == .stt else { return }

        switch event.type {
        case "stt_model_load_completed":
            let modelId = event.properties["model_id"] ?? ""
            selectedModelId = modelId
            // Look up the model name from available models
            if let matchingModel = ModelListViewModel.shared.availableModels.first(where: { $0.id == modelId }) {
                selectedModelName = matchingModel.name
                selectedFramework = matchingModel.framework
            } else {
                selectedModelName = modelId // Fallback to ID if model not found
            }
            logger.info("STT model loaded: \(modelId)")
        case "stt_model_unloaded":
            selectedModelId = nil
            selectedModelName = nil
            selectedFramework = nil
            logger.info("STT model unloaded")
        default:
            break
        }
    }

    private func checkInitialModelState() async {
        if let model = await RunAnywhere.currentSTTModel {
            selectedModelId = model.id
            selectedModelName = model.name
            selectedFramework = model.framework
            logger.info("STT model already loaded: \(model.name)")
        }
    }

    // MARK: - Private Methods - Recording

    private func startRecording() async {
        logger.info("Starting recording in \(self.selectedMode.rawValue) mode")
        errorMessage = nil
        audioBuffer = Data()
        transcription = ""
        lastSpeechTime = nil
        isSpeechActive = false

        guard selectedModelId != nil else {
            errorMessage = "No STT model loaded"
            return
        }

        do {
            // Both modes use audio capture - live mode adds VAD-based auto-transcription
            try audioCapture.startRecording { [weak self] audioData in
                Task { @MainActor in
                    self?.audioBuffer.append(audioData)
                }
            }
            
            isRecording = true
            
            if selectedMode == .live {
                // Live mode: Start VAD monitoring for auto-transcription
                startVADMonitoring()
            }
            
            logger.info("Recording started in \(self.selectedMode.rawValue) mode")
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopRecording() async {
        logger.info("Stopping recording")

        // Stop VAD monitoring if active
        silenceCheckTask?.cancel()
        silenceCheckTask = nil
        
        // Stop audio capture
        audioCapture.stopRecording()
        
        // Perform final transcription if we have audio
        if !audioBuffer.isEmpty {
            await performBatchTranscription()
        }

        isRecording = false
        audioLevel = 0.0
        isSpeechActive = false
        lastSpeechTime = nil
    }

    // MARK: - Private Methods - Transcription

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

    /// Start VAD monitoring for live mode
    /// Automatically transcribes when silence is detected after speech
    private func startVADMonitoring() {
        logger.info("Starting VAD monitoring for live transcription")
        
        silenceCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, await self.isRecording else { break }
                
                let level = await self.audioLevel
                await self.checkSpeechState(level: level)
                
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
        }
    }
    
    /// Check speech state and auto-transcribe on silence
    private func checkSpeechState(level: Float) async {
        guard isRecording, selectedMode == .live else { return }
        
        if level > speechThreshold {
            // Speech detected
            if !isSpeechActive {
                logger.debug("Speech started")
                isSpeechActive = true
            }
            lastSpeechTime = Date()
        } else if isSpeechActive {
            // Check for silence duration
            if let lastSpeech = lastSpeechTime, 
               Date().timeIntervalSince(lastSpeech) > silenceDuration {
                logger.debug("Silence detected - auto-transcribing")
                isSpeechActive = false
                
                // Only transcribe if we have enough audio (~0.5s at 16kHz)
                if audioBuffer.count > 16000 {
                    await performLiveTranscription()
                } else {
                    audioBuffer = Data()
                }
            }
        }
    }
    
    /// Perform transcription for live mode (keeps recording going)
    private func performLiveTranscription() async {
        let audio = audioBuffer
        audioBuffer = Data()  // Clear buffer for next utterance
        
        guard !audio.isEmpty else { return }
        
        logger.info("Live transcription of \(audio.count) bytes")
        isTranscribing = true
        
        do {
            let result = try await RunAnywhere.transcribe(audio)
            // Append to existing transcription with newline
            if !transcription.isEmpty {
                transcription += "\n"
            }
            transcription += result
            logger.info("Live transcription result: \(result)")
        } catch {
            logger.error("Live transcription failed: \(error.localizedDescription)")
            errorMessage = "Transcription failed: \(error.localizedDescription)"
        }
        
        isTranscribing = false
    }

    /// Stop live transcription (called when mode changes)
    private func stopLiveTranscription() async {
        logger.info("Stopping live transcription")
        silenceCheckTask?.cancel()
        silenceCheckTask = nil
        isSpeechActive = false
        lastSpeechTime = nil
    }

    // MARK: - Cleanup

    /// Clean up resources - call from view's onDisappear
    /// This replaces deinit cleanup to comply with Swift 6 concurrency
    func cleanup() {
        audioCapture.stopRecording()

        // Clean up VAD monitoring
        silenceCheckTask?.cancel()
        silenceCheckTask = nil

        cancellables.removeAll()

        // Reset initialization flags to allow re-initialization if needed
        isInitialized = false
        hasSubscribedToAudioLevel = false
        hasSubscribedToSDKEvents = false
    }
}

// MARK: - Supporting Types

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
        case .live: return "Auto-transcribe on silence"
        }
    }
}
