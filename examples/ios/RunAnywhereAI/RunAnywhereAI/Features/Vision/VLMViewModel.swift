//
//  VLMViewModel.swift
//  RunAnywhereAI
//
//  Simple ViewModel for Vision Language Model camera functionality
//

import Foundation
import SwiftUI
import RunAnywhere
import AVFoundation
import os.log

#if canImport(UIKit)
import UIKit
#endif

// MARK: - VLM View Model

@MainActor
@Observable
final class VLMViewModel: NSObject {
    // MARK: - State

    private(set) var isModelLoaded = false
    private(set) var loadedModelName: String?
    private(set) var isProcessing = false
    private(set) var currentDescription = ""
    private(set) var error: Error?
    private(set) var isCameraAuthorized = false

    // Camera
    private(set) var captureSession: AVCaptureSession?
    private var currentFrame: CVPixelBuffer?

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "VLM")

    // MARK: - Init

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vlmModelLoaded(_:)),
            name: Notification.Name("VLMModelLoaded"),
            object: nil
        )
        Task { await checkModelStatus() }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        // Note: Camera cleanup is handled by onDisappear in VLMCameraView
    }

    // MARK: - Model

    func checkModelStatus() async {
        isModelLoaded = await RunAnywhere.isVLMModelLoaded
    }

    @objc private func vlmModelLoaded(_ notification: Notification) {
        Task {
            if let model = notification.object as? ModelInfo {
                isModelLoaded = true
                loadedModelName = model.name
            } else {
                await checkModelStatus()
            }
        }
    }

    // MARK: - Camera

    func checkCameraAuthorization() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            isCameraAuthorized = true
        case .notDetermined:
            isCameraAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            isCameraAuthorized = false
        }
    }

    func setupCamera() {
        guard isCameraAuthorized else { return }

        let session = AVCaptureSession()
        session.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.queue"))
        output.alwaysDiscardsLateVideoFrames = true

        if session.canAddOutput(output) { session.addOutput(output) }

        captureSession = session
    }

    func startCamera() {
        guard let session = captureSession, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    func stopCamera() {
        guard let session = captureSession, session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }

    // MARK: - Describe

    func describeCurrentFrame() async {
        guard let pixelBuffer = currentFrame, !isProcessing else { return }

        isProcessing = true
        error = nil
        currentDescription = ""

        do {
            let image = VLMImage(pixelBuffer: pixelBuffer)
            let result = try await RunAnywhere.processImageStream(
                image,
                prompt: "Describe what you see briefly.",
                options: VLMGenerationOptions(maxTokens: 200)
            )

            for try await token in result.stream {
                currentDescription += token
            }
        } catch {
            self.error = error
            logger.error("VLM error: \(error.localizedDescription)")
        }

        isProcessing = false
    }

    #if canImport(UIKit)
    func describeImage(_ uiImage: UIImage) async {
        isProcessing = true
        error = nil
        currentDescription = ""

        do {
            let image = VLMImage(image: uiImage)
            let result = try await RunAnywhere.processImageStream(
                image,
                prompt: "Describe this image in detail.",
                options: VLMGenerationOptions(maxTokens: 300)
            )

            for try await token in result.stream {
                currentDescription += token
            }
        } catch {
            self.error = error
        }

        isProcessing = false
    }
    #endif

    func cancel() {
        Task { await RunAnywhere.cancelVLMGeneration() }
    }
}

// MARK: - Camera Delegate

extension VLMViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        Task { @MainActor in self.currentFrame = pixelBuffer }
    }
}
