//
//  OnboardingViewModel.swift
//  YapRun
//
//  State management for the first-launch onboarding flow.
//

#if os(iOS)
import AVFoundation
import Observation
import RunAnywhere
import UIKit
import os

@Observable
@MainActor
final class OnboardingViewModel {

    // MARK: - Step Enum

    enum Step: Int, CaseIterable {
        case welcome = 0
        case micPermission = 1
        case keyboardSetup = 2
        case modelDownload = 3
    }

    // MARK: - State

    var currentStep: Step = .welcome
    var micGranted = false
    var keyboardEnabled = false
    var keyboardFullAccess = false
    var keyboardReady: Bool { keyboardEnabled && keyboardFullAccess }
    var downloadProgress: Double = 0
    var downloadStage: String = ""
    var isDownloading = false
    var isModelReady = false
    var downloadError: String?

    // MARK: - Private

    private let logger = Logger(subsystem: "com.runanywhere.yaprun", category: "Onboarding")

    // MARK: - Navigation

    func advance() {
        guard let next = Step(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    // MARK: - Status Refresh (called on foreground return)

    func refreshStatus() {
        // Mic
        let status = AVAudioApplication.shared.recordPermission
        micGranted = (status == .granted)

        // Keyboard + Full Access: App Group UserDefaults accessible = Full Access granted
        checkKeyboardStatus()

        // Model
        if SharedDataBridge.shared.preferredSTTModelId != nil && isModelReady {
            // Already ready from this session
        }
    }

    func checkKeyboardStatus() {
        // 1. Check if the keyboard is in the system's enabled keyboard list
        let keyboards = UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String] ?? []
        keyboardEnabled = keyboards.contains(SharedConstants.keyboardExtensionBundleId)

        // 2. Check full-access proxy flag written by the keyboard extension on each viewDidLoad.
        //    If the keyboard isn't even enabled, full access is implicitly false.
        if keyboardEnabled {
            SharedDataBridge.shared.defaults?.synchronize()
            keyboardFullAccess = SharedDataBridge.shared.defaults?.bool(
                forKey: SharedConstants.Keys.keyboardFullAccessGranted
            ) ?? false
        } else {
            keyboardFullAccess = false
        }
    }

    // MARK: - Microphone

    func requestMicPermission() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        micGranted = granted
        logger.info("Microphone permission: \(granted ? "granted" : "denied")")
    }

    // MARK: - Keyboard Settings

    func openKeyboardSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Model Download

    func downloadDefaultModel() async {
        guard !isDownloading else { return }
        isDownloading = true
        downloadError = nil
        downloadProgress = 0
        downloadStage = "Preparing…"

        do {
            let modelId = ModelRegistry.defaultModelId
            let stream = try await RunAnywhere.downloadModel(modelId)
            for await progress in stream {
                downloadProgress = progress.overallProgress
                switch progress.stage {
                case .downloading:  downloadStage = "Downloading…"
                case .extracting:   downloadStage = "Extracting…"
                case .validating:   downloadStage = "Validating…"
                case .completed:    downloadStage = "Complete"
                @unknown default:   downloadStage = "Processing…"
                }
                if progress.stage == .completed { break }
            }

            logger.info("Model downloaded — loading into memory")
            try await RunAnywhere.loadSTTModel(modelId)
            SharedDataBridge.shared.preferredSTTModelId = modelId

            isModelReady = true
            logger.info("Model loaded — onboarding model step complete")
        } catch {
            downloadError = error.localizedDescription
            logger.error("Model download/load failed: \(error.localizedDescription)")
        }

        isDownloading = false
    }

    // MARK: - Completion

    func completeOnboarding() {
        SharedDataBridge.shared.defaults?.set(true, forKey: SharedConstants.Keys.hasCompletedOnboarding)
        SharedDataBridge.shared.defaults?.synchronize()
        logger.info("Onboarding marked complete")
    }
}

#endif
