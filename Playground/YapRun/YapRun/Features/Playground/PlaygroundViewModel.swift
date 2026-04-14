//
//  PlaygroundViewModel.swift
//  YapRun
//
//  Manages audio recording and on-device transcription for the ASR playground.
//  Shared between iOS and macOS.
//

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

    // MARK: - Auto-Stop (VAD)

    var isAutoStopEnabled = false
    var speechDetected = false

    // MARK: - Private

    private let audioCapture = AudioCaptureManager()
    private var audioBuffer = Foundation.Data()
    private var timerTask: Task<Void, Never>?
    private var vadMonitorTask: Task<Void, Never>?
    private var vadProcessedBytes = 0
    private var silenceStartTime: Date?
    private var hasSpeechBeenDetected = false
    private let autoStopSilenceDuration: TimeInterval = 2.0
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

        // Prevent conflict with active voice keyboard session
        guard !FlowSessionManager.shared.isActive else {
            errorMessage = "Voice keyboard session is active. End it first."
            return
        }

        let permitted = await audioCapture.requestPermission()
        guard permitted else {
            errorMessage = "Microphone access is required."
            return
        }

        audioBuffer = Foundation.Data()
        elapsedSeconds = 0
        errorMessage = nil
        transcription = ""

        do {
            // AudioCaptureManager dispatches this callback on DispatchQueue.main
            try await audioCapture.startRecording { [weak self] data in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.audioBuffer.append(data)
                    self.audioLevel = self.audioCapture.audioLevel
                }
            }
            isRecording = true
            startTimer()
            if isAutoStopEnabled {
                startVADMonitoring()
            }
            logger.info("Recording started (autoStop=\(self.isAutoStopEnabled))")
        } catch {
            errorMessage = "Could not start microphone: \(error.localizedDescription)"
            logger.error("Recording start failed: \(error.localizedDescription)")
        }
    }

    private func stopAndTranscribe() async {
        audioCapture.stopRecording()
        isRecording = false
        audioLevel = 0
        speechDetected = false
        timerTask?.cancel()
        timerTask = nil
        vadMonitorTask?.cancel()
        vadMonitorTask = nil

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
        audioBuffer = Foundation.Data()
        errorMessage = nil
        elapsedSeconds = 0
        speechDetected = false
    }

    // MARK: - VAD Monitoring

    private func startVADMonitoring() {
        vadProcessedBytes = 0
        hasSpeechBeenDetected = false
        silenceStartTime = nil
        speechDetected = false

        vadMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                guard let self, !Task.isCancelled, self.isRecording else { break }
                await self.processVADChunk()
            }
        }
    }

    private func processVADChunk() async {
        let currentSize = audioBuffer.count
        guard currentSize > vadProcessedBytes else { return }

        let newData = audioBuffer.subdata(in: vadProcessedBytes..<currentSize)
        vadProcessedBytes = currentSize

        let samples = convertInt16ToFloat(newData)
        guard !samples.isEmpty else { return }

        do {
            let isSpeech = try await RunAnywhere.detectSpeech(in: samples)
            speechDetected = isSpeech

            if isSpeech {
                hasSpeechBeenDetected = true
                silenceStartTime = nil
            } else if hasSpeechBeenDetected {
                if silenceStartTime == nil {
                    silenceStartTime = Date()
                } else if let start = silenceStartTime,
                          Date().timeIntervalSince(start) >= autoStopSilenceDuration
                {
                    logger.info("Auto-stop: \(self.autoStopSilenceDuration)s silence after speech")
                    await stopAndTranscribe()
                }
            }
        } catch {
            logger.error("VAD error: \(error.localizedDescription)")
        }
    }

    private func convertInt16ToFloat(_ data: Foundation.Data) -> [Float] {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        return data.withUnsafeBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            return (0..<sampleCount).map { Float(int16Buffer[$0]) / 32768.0 }
        }
    }
}
