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
    private var modelLoadTask: Task<Void, Never>?
    private var hotkeyIsDown = false
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
                self.hotkeyIsDown = true
                Task { await self.beginRecording() }
            }
            .store(in: &cancellables)

        hotkey.hotkeyUp
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.hotkeyIsDown = false
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
            hotkeyIsDown = true
            await beginRecording()
        case .recording:
            hotkeyIsDown = false
            await finishRecordingAndTranscribe()
        case .loadingModel:
            cancelModelLoad()
        default:
            break
        }
    }

    // MARK: - Recording

    private func beginRecording() async {
        guard phase == .idle else { return }

        // If no model loaded, auto-download/load the default
        if await RunAnywhere.currentSTTModel == nil {
            await ensureModelLoaded()
            // If model load failed or user released the key, stop here
            guard phase == .loadingModel else { return }
            // Model is now loaded — continue to recording
        }

        await startMicAndRecord()
    }

    /// Downloads (if needed) and loads the preferred STT model.
    /// Sets phase to `.loadingModel` during the process.
    private func ensureModelLoaded() async {
        phase = .loadingModel
        logger.info("No STT model loaded — auto-loading default")

        let modelId = UserDefaults.standard.string(forKey: "preferredSTTModelId")
            ?? ModelRegistry.defaultModelId

        do {
            let allModels = try await RunAnywhere.availableModels()
            guard let model = allModels.first(where: { $0.id == modelId }) else {
                phase = .error("Model not found")
                resetAfterDelay()
                return
            }

            // Download if not already on disk
            if model.localPath == nil {
                logger.info("Downloading model: \(modelId)")
                let stream = try await RunAnywhere.downloadModel(modelId)
                for await progress in stream {
                    // Bail out if user released hotkey during download
                    guard phase == .loadingModel else { return }
                    if progress.stage == .completed { break }
                }
            }

            // Bail out if user released hotkey during download
            guard phase == .loadingModel else { return }

            // Load the model
            logger.info("Loading model: \(modelId)")
            try await RunAnywhere.loadSTTModel(modelId)
            UserDefaults.standard.set(modelId, forKey: "preferredSTTModelId")
            logger.info("Model \(modelId) auto-loaded successfully")
        } catch {
            guard phase == .loadingModel else { return }
            phase = .error("Model load failed")
            logger.error("Auto-load failed: \(error.localizedDescription)")
            resetAfterDelay()
        }
    }

    /// Starts the microphone and transitions to the recording phase.
    private func startMicAndRecord() async {
        let permitted = await audioCapture.requestPermission()
        guard permitted else {
            phase = .error("Microphone access required")
            resetAfterDelay()
            return
        }

        // Check if user released key while we were requesting permission
        guard hotkeyIsDown || phase == .loadingModel else {
            phase = .idle
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
        // If still loading model, cancel the load and go idle
        if phase == .loadingModel {
            cancelModelLoad()
            return
        }

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

    private func cancelModelLoad() {
        modelLoadTask?.cancel()
        modelLoadTask = nil
        phase = .idle
        logger.info("Model load cancelled")
    }

    private func cancelRecording() {
        audioCapture.stopRecording()
        audioLevel = 0
        timerTask?.cancel()
        timerTask = nil
        modelLoadTask?.cancel()
        modelLoadTask = nil
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
