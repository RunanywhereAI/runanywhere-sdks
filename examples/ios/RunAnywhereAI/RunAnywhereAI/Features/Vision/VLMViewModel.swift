//
//  VLMViewModel.swift
//  RunAnywhereAI
//
//  Simple ViewModel for Vision Language Model camera functionality
//

import Foundation
import SwiftUI
import RunAnywhere
import Combine
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
    static let autoStreamInterval: TimeInterval = 2.5 // seconds between auto-captures

    // Camera
    private(set) var captureSession: AVCaptureSession?
    private var currentFrame: CVPixelBuffer?

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "VLM")
    private var lifecycleCancellable: AnyCancellable?

    // MARK: - Init

    override init() {
        super.init()
        subscribeToModelLifecycle()
        Task { await checkModelStatus() }
    }

    // MARK: - Model

    func checkModelStatus() async {
        var req = RACurrentModelRequest()
        req.category = .multimodal
        isModelLoaded = RunAnywhere.currentModel(req).found
    }

    /// Track the VLM model slot via the SDK event bus. Model loads route through
    /// `RunAnywhere.loadModel(category: .multimodal)`, which publishes a
    /// component-lifecycle event for SDK_COMPONENT_VLM — the single source of
    /// truth, replacing the former "VLMModelLoaded" NotificationCenter post.
    private func subscribeToModelLifecycle() {
        lifecycleCancellable = RunAnywhere.events.events(for: .component)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in self?.handleComponentLifecycleEvent(event) }
            }
    }

    private func handleComponentLifecycleEvent(_ event: RASDKEvent) {
        let lifecycle = event.componentLifecycle
        guard lifecycle.component == .vlm else { return }

        switch lifecycle.currentState {
        case .ready:
            isModelLoaded = true
            if let model = ModelListViewModel.shared.availableModels.first(where: { $0.id == lifecycle.modelID }) {
                loadedModelName = model.name
            }
        case .notLoaded, .unloading, .shutdown, .deleting:
            isModelLoaded = false
            loadedModelName = nil
        default:
            break
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
            guard let image = RAVLMImage.fromPixelBuffer(pixelBuffer) else {
                throw Self.imageConversionError("Failed to convert camera frame to VLM input")
            }
            let prompt = "Describe what you see briefly."
            var options = RAVLMGenerationOptions.defaults(prompt: prompt)
            options.maxTokens = 200
            let stream = try await RunAnywhere.processImageStream(image, options: options)

            for await event in stream where !event.generation.token.isEmpty {
                currentDescription += event.generation.token
            }
            logger.info("VLM streaming completed")
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
            guard let image = RAVLMImage.fromUIImage(uiImage) else {
                throw Self.imageConversionError("Failed to convert image to VLM input")
            }
            let prompt = "Describe this image in detail."
            var options = RAVLMGenerationOptions.defaults(prompt: prompt)
            options.maxTokens = 300
            let stream = try await RunAnywhere.processImageStream(image, options: options)

            for await event in stream where !event.generation.token.isEmpty {
                currentDescription += event.generation.token
            }
            logger.info("VLM streaming completed")
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
            let rgbData = Self.rgbData(from: cgImage, width: width, height: height)
            let image = RAVLMImage.fromRawRGB(rgbData, width: width, height: height)
            let prompt = "Describe this image in detail."
            var options = RAVLMGenerationOptions.defaults(prompt: prompt)
            options.maxTokens = 300
            let stream = try await RunAnywhere.processImageStream(image, options: options)

            for await event in stream where !event.generation.token.isEmpty {
                currentDescription += event.generation.token
            }
            logger.info("VLM streaming completed")
        } catch {
            self.error = error
        }

        isProcessing = false
    }

    /// Convert a `CGImage` to raw RGB (3 bytes/pixel) data — strips the padding byte
    /// from the RGBX layout produced by `CGContext` using `noneSkipLast`.
    private static func rgbData(from cgImage: CGImage, width: Int, height: Int) -> Data {
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
        var rgbData = Data(capacity: width * height * 3)
        rgbaData.withUnsafeBytes { buffer in
            let pixels = buffer.bindMemory(to: UInt8.self)
            for i in stride(from: 0, to: rgbaTotalBytes, by: 4) {
                rgbData.append(pixels[i])     // R
                rgbData.append(pixels[i + 1]) // G
                rgbData.append(pixels[i + 2]) // B
            }
        }
        return rgbData
    }
    #endif

    func cancel() {
        Task { await RunAnywhere.cancelVLMGeneration() }
    }

    // MARK: - Auto Streaming

    func toggleAutoStreaming() {
        isAutoStreamingEnabled.toggle()
    }

    func runAutoStreamLoop() async {
        while !Task.isCancelled {
            while isProcessing {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { return }
            }
            await describeCurrentFrameForAutoStream()
            try? await Task.sleep(nanoseconds: UInt64(Self.autoStreamInterval * 1_000_000_000))
        }
    }

    private func describeCurrentFrameForAutoStream() async {
        guard let pixelBuffer = currentFrame, !isProcessing else { return }

        isProcessing = true
        error = nil

        // For auto-stream, we replace the description instead of clearing first
        // This gives a smoother visual transition
        var newDescription = ""

        do {
            guard let image = RAVLMImage.fromPixelBuffer(pixelBuffer) else {
                throw Self.imageConversionError("Failed to convert camera frame to VLM input")
            }
            let prompt = "Describe what you see in one sentence."
            var options = RAVLMGenerationOptions.defaults(prompt: prompt)
            options.maxTokens = 100
            let stream = try await RunAnywhere.processImageStream(image, options: options)

            for await event in stream where !event.generation.token.isEmpty {
                newDescription += event.generation.token
                currentDescription = newDescription
            }
            logger.info("VLM streaming completed")
        } catch {
            // Don't show errors during auto-stream, just log
            logger.error("Auto-stream VLM error: \(error.localizedDescription)")
        }

        isProcessing = false
    }

    private static func imageConversionError(_ message: String) -> NSError {
        NSError(
            domain: "com.runanywhere.RunAnywhereAI",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

// MARK: - Camera Delegate

extension VLMViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        Task { @MainActor in self.currentFrame = pixelBuffer }
    }
}
