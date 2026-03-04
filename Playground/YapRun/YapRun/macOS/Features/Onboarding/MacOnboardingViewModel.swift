#if os(macOS)
//
//  MacOnboardingViewModel.swift
//  YapRun
//
//  State management for macOS onboarding flow.
//  Steps: Welcome → Mic → Accessibility → Model Download.
//

import Foundation
import Observation
import RunAnywhere
import os

@Observable
@MainActor
final class MacOnboardingViewModel {

    // MARK: - Step Enum

    enum Step: Int, CaseIterable {
        case welcome = 0
        case micPermission = 1
        case accessibility = 2
        case modelDownload = 3
    }

    // MARK: - State

    var currentStep: Step = .welcome
    var micGranted = false
    var accessibilityGranted = false
    var downloadProgress: Double = 0
    var downloadStage: String = ""
    var isDownloading = false
    var isModelReady = false
    var downloadError: String?

    // MARK: - Private

    private let logger = Logger(subsystem: "com.runanywhere.yaprun", category: "MacOnboarding")

    // MARK: - Navigation

    func advance() {
        guard let next = Step(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = next
    }

    // MARK: - Status Refresh

    func refreshStatus() {
        micGranted = MacPermissionService.microphoneState == .granted
        accessibilityGranted = MacPermissionService.isAccessibilityGranted
    }

    // MARK: - Microphone

    func requestMicPermission() async {
        let granted = await MacPermissionService.requestMicrophone()
        micGranted = granted
        logger.info("Microphone permission: \(granted ? "granted" : "denied")")
    }

    // MARK: - Accessibility

    func promptAccessibility() {
        MacPermissionService.promptAccessibility()
    }

    func openAccessibilitySettings() {
        MacPermissionService.openAccessibilitySettings()
    }

    // MARK: - Model Download

    func downloadDefaultModel() async {
        guard !isDownloading else { return }
        isDownloading = true
        downloadError = nil
        downloadProgress = 0
        downloadStage = "Preparing..."

        do {
            let modelId = ModelRegistry.defaultModelId
            let stream = try await RunAnywhere.downloadModel(modelId)
            for await progress in stream {
                downloadProgress = progress.overallProgress
                switch progress.stage {
                case .downloading:  downloadStage = "Downloading..."
                case .extracting:   downloadStage = "Extracting..."
                case .validating:   downloadStage = "Validating..."
                case .completed:    downloadStage = "Complete"
                @unknown default:   downloadStage = "Processing..."
                }
                if progress.stage == .completed { break }
            }

            logger.info("Model downloaded — loading into memory")
            try await RunAnywhere.loadSTTModel(modelId)
            UserDefaults.standard.set(modelId, forKey: "preferredSTTModelId")

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
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        logger.info("Onboarding marked complete")
    }
}

#endif
