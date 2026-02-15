//
//  VLMViewModel.swift
//  RunAnywhereAI
//
//  Simple ViewModel for Vision Language Model camera functionality
//

import Foundation
import SwiftUI
import RunAnywhere
@preconcurrency import AVFoundation
import os.log

#if canImport(UIKit)
import UIKit
#endif

#if os(macOS)
import AppKit
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

    // Auto-streaming mode
    var isAutoStreamingEnabled = false
    // nonisolated(unsafe) so deinit can cancel the task (deinit is nonisolated in Swift 6)
    nonisolated(unsafe) private var autoStreamTask: Task<Void, Never>?
    private static let autoStreamInterval: TimeInterval = 2.5 // seconds between auto-captures

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
        autoStreamTask?.cancel()
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
        // CRITICAL: Request BGRA format explicitly!
        // Default iOS camera output is YUV, which our pixel conversion code doesn't handle.
        // The SDK's VLMTypes.swift assumes BGRA (offset+2=R, offset+1=G, offset+0=B)
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
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
                maxTokens: 200
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
                maxTokens: 300
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

    #if os(macOS)
    func describeImage(_ nsImage: NSImage) async {
        isProcessing = true
        error = nil
        currentDescription = ""

        do {
            guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                let conversionError = NSError(
                    domain: "com.runanywhere.RunAnywhereAI",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to convert NSImage to CGImage"]
                )
                self.error = conversionError
                logger.error("VLM error: failed to convert NSImage to CGImage")
                isProcessing = false
                return
            }
            let width = cgImage.width
            let height = cgImage.height
            let rgbaBytesPerRow = 4 * width
            let rgbaTotalBytes = rgbaBytesPerRow * height
            var rgbaData = Data(count: rgbaTotalBytes)
            rgbaData.withUnsafeMutableBytes { ptr in
                guard let context = CGContext(
                    data: ptr.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: rgbaBytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                ) else { return }
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            // RGBX (4 bytes/pixel) → RGB (3 bytes/pixel): strip the padding byte
            var rgbData = Data(capacity: width * height * 3)
            rgbaData.withUnsafeBytes { buffer in
                let pixels = buffer.bindMemory(to: UInt8.self)
                for i in stride(from: 0, to: rgbaTotalBytes, by: 4) {
                    rgbData.append(pixels[i])     // R
                    rgbData.append(pixels[i + 1]) // G
                    rgbData.append(pixels[i + 2]) // B
                }
            }
            let image = VLMImage(rgbPixels: rgbData, width: width, height: height)
            let result = try await RunAnywhere.processImageStream(
                image,
                prompt: "Describe this image in detail.",
                maxTokens: 300
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

    // MARK: - Auto Streaming

    func toggleAutoStreaming() {
        isAutoStreamingEnabled.toggle()
        if isAutoStreamingEnabled {
            startAutoStreaming()
        } else {
            stopAutoStreaming()
        }
    }

    func startAutoStreaming() {
        guard autoStreamTask == nil else { return }

        autoStreamTask = Task {
            while !Task.isCancelled && isAutoStreamingEnabled {
                // Wait for any current processing to finish
                while isProcessing {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    if Task.isCancelled { return }
                }

                // Capture and describe
                await describeCurrentFrameForAutoStream()

                // Wait before next capture
                try? await Task.sleep(nanoseconds: UInt64(Self.autoStreamInterval * 1_000_000_000))
            }
        }
    }

    func stopAutoStreaming() {
        autoStreamTask?.cancel()
        autoStreamTask = nil
        isAutoStreamingEnabled = false
    }

    private func describeCurrentFrameForAutoStream() async {
        guard let pixelBuffer = currentFrame, !isProcessing else { return }

        isProcessing = true
        error = nil

        // For auto-stream, we replace the description instead of clearing first
        // This gives a smoother visual transition
        var newDescription = ""

        do {
            let image = VLMImage(pixelBuffer: pixelBuffer)
            let result = try await RunAnywhere.processImageStream(
                image,
                prompt: "Describe what you see in one sentence.",
                maxTokens: 100
            )

            for try await token in result.stream {
                newDescription += token
                currentDescription = newDescription
            }
        } catch {
            // Don't show errors during auto-stream, just log
            logger.error("Auto-stream VLM error: \(error.localizedDescription)")
        }

        isProcessing = false
    }
}

// MARK: - Camera Delegate

extension VLMViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        Task { @MainActor in self.currentFrame = pixelBuffer }
    }
}
