//
//  DiarizationViewModel.swift
//  RunAnywhereAI
//
//  Standalone speaker diarization over the canonical `RunAnywhere.diarize` facade.
//
//  This view model is pure platform plumbing: it downloads + loads the cataloged
//  Sortformer model through the SDK lifecycle, captures microphone audio, and
//  calls `RunAnywhere.diarize`. All inference and model routing live in the SDK
//  / C++ commons.
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
    private(set) var isPreparingModel = false

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

    /// Cataloged NVIDIA Streaming Sortformer 4-speaker v2.1 FP16 (MLX).
    private static let catalogModelID = "mlx-sortformer-4spk-v2.1-fp16"

    // MARK: - Model status

    func refreshModelStatus() {
        var request = RACurrentModelRequest()
        request.category = .speakerDiarization
        isModelLoaded = RunAnywhere.currentModel(request).found
    }

    // MARK: - Model supply (cataloged, downloaded on demand)

    /// Download (if needed) and load the cataloged Sortformer model under the
    /// `.speakerDiarization` category through the canonical SDK lifecycle.
    func prepareModel() async {
        isPreparingModel = true
        error = nil
        defer { isPreparingModel = false }

        let registry = ModelListViewModel.shared
        await registry.loadModelsFromRegistry()
        guard let model = catalogModel(in: registry) else {
            error = "The Sortformer diarization model is not in the catalog."
            statusMessage = ""
            return
        }

        do {
            if !model.isBuiltIn, model.localPathURL == nil {
                statusMessage = "Downloading model…"
                try await registry.downloadModel(model)
            }

            statusMessage = "Loading model…"
            var loadRequest = RAModelLoadRequest()
            loadRequest.modelID = model.id
            loadRequest.category = .speakerDiarization
            let loadResult = await RunAnywhere.loadModel(loadRequest)
            guard loadResult.success else {
                error = loadResult.errorMessage.isEmpty ? "Model load failed." : loadResult.errorMessage
                statusMessage = ""
                return
            }
            loadedModelName = model.name
            isModelLoaded = true
            statusMessage = "Model loaded: \(model.name)."
        } catch {
            logger.error("Diarization model prepare failed: \(error.localizedDescription)")
            self.error = "Model download/load failed: \(error.localizedDescription)"
            statusMessage = ""
        }
    }

    private func catalogModel(in registry: ModelListViewModel) -> RAModelInfo? {
        registry.availableModels.first { $0.id == Self.catalogModelID }
            ?? registry.availableModels.first { $0.category == .speakerDiarization }
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
            options.sampleRateHz = Int32(Self.sampleRate)
            options.channelCount = 1
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
