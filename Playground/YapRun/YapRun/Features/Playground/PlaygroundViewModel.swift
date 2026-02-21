//
//  PlaygroundViewModel.swift
//  YapRun
//
//  Manages audio recording and on-device transcription for the ASR playground.
//

#if os(iOS)
import Foundation
import Observation
import RunAnywhere
import os

@Observable
@MainActor
final class PlaygroundViewModel {

    // MARK: - State

    var isRecording = false
    var isTranscribing = false
    var audioLevel: Float = 0
    var transcription = ""
    var elapsedSeconds = 0
    var errorMessage: String?
    var modelName: String?

    // MARK: - Private

    private let audioCapture = AudioCaptureManager()
    private var audioBuffer = Foundation.Data()
    private var timerTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.runanywhere.yaprun", category: "Playground")

    // MARK: - Model Check

    func checkModelStatus() async {
        if let model = await RunAnywhere.currentSTTModel {
            modelName = model.name
        } else {
            modelName = nil
        }
    }

    // MARK: - Recording

    func toggleRecording() async {
        if isRecording {
            await stopAndTranscribe()
        } else {
            await startRecording()
        }
    }

    private func startRecording() async {
        guard modelName != nil else {
            errorMessage = "No STT model loaded. Download one from the Home tab."
            return
        }

        let permitted = await audioCapture.requestPermission()
        guard permitted else {
            errorMessage = "Microphone access is required."
            return
        }

        audioBuffer = Data()
        elapsedSeconds = 0
        errorMessage = nil
        transcription = ""

        do {
            try audioCapture.startRecording { [weak self] data in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.audioBuffer.append(data)
                    self.audioLevel = self.audioCapture.audioLevel
                }
            }
            isRecording = true
            startTimer()
            logger.info("Recording started")
        } catch {
            errorMessage = "Could not start microphone: \(error.localizedDescription)"
            logger.error("Recording start failed: \(error.localizedDescription)")
        }
    }

    private func stopAndTranscribe() async {
        audioCapture.stopRecording()
        isRecording = false
        audioLevel = 0
        timerTask?.cancel()
        timerTask = nil

        guard !audioBuffer.isEmpty else {
            errorMessage = "No audio was captured."
            return
        }

        isTranscribing = true
        logger.info("Transcribing \(self.audioBuffer.count) bytes")

        do {
            let text = try await RunAnywhere.transcribe(audioBuffer)
            transcription = text
            logger.info("Transcription complete: \(text.prefix(80))")
        } catch {
            errorMessage = "Transcription failed: \(error.localizedDescription)"
            logger.error("Transcription error: \(error.localizedDescription)")
        }

        isTranscribing = false
    }

    // MARK: - Timer

    private func startTimer() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { break }
                self.elapsedSeconds += 1
            }
        }
    }

    // MARK: - Actions

    func clear() {
        transcription = ""
        audioBuffer = Data()
        errorMessage = nil
        elapsedSeconds = 0
    }
}

#endif
