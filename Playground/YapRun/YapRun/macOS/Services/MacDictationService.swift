#if os(macOS)
//
//  MacDictationService.swift
//  YapRun
//
//  Orchestrates the end-to-end dictation flow on macOS:
//  hotkey down → start mic → record → hotkey up → transcribe → insert text.
//

import Combine
import Foundation
import Observation
import RunAnywhere
import os

@Observable
@MainActor
final class MacDictationService {

    static let shared = MacDictationService()

    // MARK: - Published State

    var phase: DictationPhase = .idle
    var audioLevel: Float = 0
    var elapsedSeconds = 0

    // MARK: - Private

    private let audioCapture = AudioCaptureManager()
    private var audioBuffer = Foundation.Data()
    private var timerTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.runanywhere.yaprun", category: "Dictation")

    private init() {}

    // MARK: - Lifecycle

    func start() {
        let hotkey = MacHotkeyService.shared
        hotkey.install()

        hotkey.hotkeyDown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                Task { await self.beginRecording() }
            }
            .store(in: &cancellables)

        hotkey.hotkeyUp
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                Task { await self.finishRecordingAndTranscribe() }
            }
            .store(in: &cancellables)

        logger.info("MacDictationService started")
    }

    func stop() {
        MacHotkeyService.shared.uninstall()
        cancellables.removeAll()
        cancelRecording()
        logger.info("MacDictationService stopped")
    }

    func toggleFromFlowBar() async {
        switch phase {
        case .idle:
            await beginRecording()
        case .recording:
            await finishRecordingAndTranscribe()
        default:
            break
        }
    }

    // MARK: - Recording

    private func beginRecording() async {
        guard phase == .idle else { return }

        guard await RunAnywhere.currentSTTModel != nil else {
            phase = .error("No STT model loaded")
            resetAfterDelay()
            return
        }

        let permitted = await audioCapture.requestPermission()
        guard permitted else {
            phase = .error("Microphone access required")
            resetAfterDelay()
            return
        }

        audioBuffer = Foundation.Data()
        elapsedSeconds = 0

        do {
            try audioCapture.startRecording { [weak self] data in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.audioBuffer.append(data)
                    self.audioLevel = self.audioCapture.audioLevel
                }
            }
            phase = .recording
            startTimer()
            logger.info("Recording started")
        } catch {
            phase = .error("Mic error: \(error.localizedDescription)")
            resetAfterDelay()
        }
    }

    private func finishRecordingAndTranscribe() async {
        guard phase == .recording else { return }

        audioCapture.stopRecording()
        audioLevel = 0
        timerTask?.cancel()
        timerTask = nil

        guard !audioBuffer.isEmpty else {
            phase = .idle
            return
        }

        phase = .transcribing
        logger.info("Transcribing \(self.audioBuffer.count) bytes")

        do {
            let text = try await RunAnywhere.transcribe(audioBuffer)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                phase = .idle
                return
            }

            phase = .inserting
            MacTextInsertionService.insertText(text)
            DictationHistory.shared.append(text)
            phase = .done(text)
            logger.info("Dictation complete: \(text.prefix(60))")

            resetAfterDelay()
        } catch {
            phase = .error("Transcription failed")
            logger.error("Transcription error: \(error.localizedDescription)")
            resetAfterDelay()
        }
    }

    private func cancelRecording() {
        audioCapture.stopRecording()
        audioLevel = 0
        timerTask?.cancel()
        timerTask = nil
        audioBuffer = Foundation.Data()
        phase = .idle
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

    // MARK: - Helpers

    private func resetAfterDelay() {
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if case .done = phase { phase = .idle }
            if case .error = phase { phase = .idle }
        }
    }
}

#endif
