//
//  DiarizationViewModel.swift
//  RunAnywhereAI
//
//  Standalone speaker diarization over the `RunAnywhere.diarization` facade.
//
//  This view model is pure platform plumbing: it loads a catalog Sortformer
//  model through the SDK lifecycle, captures microphone audio, and calls
//  `RunAnywhere.diarization.diarize`. All inference and model routing live in
//  the SDK / C++ commons.
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
    private(set) var segments: [DiarizedSegment] = []
    private(set) var speakerCount = 0

    /// Wall-clock time of the last run; `DiarizationResult` carries no timing.
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
        Task { [weak self] in
            let loaded = await RunAnywhere.models.state().loaded[.speakerDiarization]
            guard let self else { return }
            self.isModelLoaded = loaded != nil
            if let name = loaded?.name, !name.isEmpty {
                self.loadedModelName = name
            }
        }
    }

    // MARK: - Model supply (catalog Get → Use)

    /// Load a model chosen from `ModelSelectionSheet`.
    func loadModelFromSelection(_ model: RAModelInfo) async {
        isProcessing = true
        error = nil
        statusMessage = "Loading model…"
        defer { isProcessing = false }

        do {
            try await RunAnywhere.models.load(id: model.id)
        } catch {
            self.error = "Model load failed: \(error.localizedDescription)"
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
            let started = Date()
            let result = try await RunAnywhere.diarization.diarize(
                .pcm16(audio, sampleRate: Self.sampleRate)
            )
            processingTimeMs = Int64((Date().timeIntervalSince(started) * 1000).rounded())
            segments = DiarizedSegment.presentable(result.segments)
            speakerCount = result.speakerCount
            statusMessage = "Done — \(result.speakerCount) speakers, " +
                "\(result.segments.count) segments in \(processingTimeMs)ms."
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

// MARK: - Presentation model

/// One speaker turn shaped for the list: the SDK reports a speaker id, and the
/// UI additionally needs a small stable index to pick a chip colour.
struct DiarizedSegment {
    let speakerIndex: Int
    let speakerID: String
    let startMs: Int64
    let endMs: Int64

    /// Sort by start time and assign each distinct speaker id an index in order
    /// of first appearance.
    static func presentable(_ segments: [SpeakerSegment]) -> [DiarizedSegment] {
        var indexBySpeaker: [String: Int] = [:]
        return segments
            .sorted { $0.startMs < $1.startMs }
            .map { segment in
                let index = indexBySpeaker[segment.speakerId] ?? indexBySpeaker.count
                indexBySpeaker[segment.speakerId] = index
                return DiarizedSegment(
                    speakerIndex: index,
                    speakerID: segment.speakerId,
                    startMs: segment.startMs,
                    endMs: segment.endMs
                )
            }
    }
}
