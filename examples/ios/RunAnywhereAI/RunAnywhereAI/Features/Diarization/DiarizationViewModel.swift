//
//  DiarizationViewModel.swift
//  RunAnywhereAI
//
//  Standalone speaker diarization over the canonical `RunAnywhere.diarize` facade.
//
//  This view model is pure platform plumbing: it loads a catalog Sortformer
//  model through the SDK lifecycle, captures microphone audio, and calls
//  `RunAnywhere.diarize`. All inference and model routing live in the SDK /
//  C++ commons.
//

import Combine
import Foundation
import Observation
import RunAnywhere
import os.log

@MainActor
@Observable
final class DiarizationViewModel {
    // Model lifecycle
    private(set) var isModelLoaded = false
    private(set) var loadedModelName: String?
    private(set) var isProcessing = false

    // Audio capture
    private(set) var isRecording = false
    var audioLevel: Float = 0.0

    // Diarization output
    private(set) var isDiarizing = false
    private(set) var segments: [RADiarizationSegment] = []
    private(set) var speakerCount: Int32 = 0
    private(set) var audioDurationMs: Int64 = 0
    private(set) var processingTimeMs: Int64 = 0

    private(set) var statusMessage = ""
    private(set) var error: String?

    @ObservationIgnored private let audioCapture = AudioCaptureManager()
    @ObservationIgnored private var audioBuffer = Data()
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var hasSubscribedToAudioLevel = false

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "Diarization")

    // MARK: - Model status

    func refreshModelStatus() {
        var request = RACurrentModelRequest()
        request.category = .speakerDiarization
        let current = RunAnywhere.currentModel(request)
        isModelLoaded = current.found
        if current.found, !current.model.name.isEmpty {
            loadedModelName = current.model.name
        }
    }

    // MARK: - Model supply (catalog Get → Use)

    /// Load a model chosen from `ModelSelectionSheet`.
    func loadModelFromSelection(_ model: RAModelInfo) async {
        isProcessing = true
        error = nil
        statusMessage = "Loading model…"
        defer { isProcessing = false }

        var loadRequest = RAModelLoadRequest()
        loadRequest.modelID = model.id
        loadRequest.category = .speakerDiarization
        let loadResult = await RunAnywhere.loadModel(loadRequest)
        guard loadResult.success else {
            error = loadResult.errorMessage.isEmpty ? "Model load failed." : loadResult.errorMessage
            statusMessage = ""
            return
        }
        loadedModelName = model.name.isEmpty ? model.id : model.name
        isModelLoaded = true
        statusMessage = "Model loaded: \(loadedModelName ?? model.id)."
    }

    // MARK: - Audio capture

    func toggleRecording() async {
        if isRecording {
            await stopAndDiarize()
        } else {
            await startRecording()
        }
    }

    private func startRecording() async {
        guard isModelLoaded else { error = "Load a diarization model first."; return }

        let granted = await audioCapture.requestPermission()
        guard granted else {
            error = "Microphone permission denied. Enable it in Settings to diarize audio."
            return
        }

        error = nil
        segments = []
        speakerCount = 0
        audioDurationMs = 0
        processingTimeMs = 0
        audioBuffer = Data()
        subscribeToAudioLevel()

        do {
            try await AudioCapturePump.startRecording(with: audioCapture) { [weak self] audioData in
                self?.audioBuffer.append(audioData)
            }
            isRecording = true
            statusMessage = "Recording…"
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            self.error = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopAndDiarize() async {
        audioCapture.stopRecording()
        isRecording = false
        audioLevel = 0.0

        guard audioBuffer.count >= Self.minBytes else {
            error = "Recording too short — hold a little longer."
            statusMessage = ""
            return
        }
        await runDiarization(on: audioBuffer)
    }

    // MARK: - Diarization

    private func runDiarization(on audio: Data) async {
        isDiarizing = true
        error = nil
        statusMessage = "Running diarization…"
        defer { isDiarizing = false }

        do {
            var options = RADiarizationOptions()
            options.sampleRate = Int32(Self.sampleRate)
            options.channels = 1
            options.encoding = .pcmS16Le

            let result = try await RunAnywhere.diarize(audioData: audio, options: options)
            segments = result.segments.sorted { $0.startMs < $1.startMs }
            speakerCount = result.speakerCount
            audioDurationMs = result.audioDurationMs
            processingTimeMs = result.processingTimeMs
            statusMessage = "Done — \(result.speakerCount) speakers, " +
                "\(result.segments.count) segments in \(result.processingTimeMs)ms."
        } catch {
            logger.error("Diarization failed: \(error.localizedDescription)")
            self.error = "Diarization failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Cleanup

    /// Release the microphone. Call from the view's `onDisappear`.
    func cleanup() {
        audioCapture.stopRecording()
        isRecording = false
        audioLevel = 0.0
        cancellables.removeAll()
        hasSubscribedToAudioLevel = false
    }

    private func subscribeToAudioLevel() {
        guard !hasSubscribedToAudioLevel else { return }
        hasSubscribedToAudioLevel = true
        audioCapture.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                Task { @MainActor in self?.audioLevel = level }
            }
            .store(in: &cancellables)
    }

    private static let minBytes = 16_000
    private static let sampleRate = 16_000
}
