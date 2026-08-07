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
    private static let liveFrameMaxTokens = 96
    private static let selectedImageMaxTokens = 128
    private static let autoStreamMaxTokens = 64

    // Camera
    private(set) var captureSession: AVCaptureSession?
    private var currentFrame: CVPixelBuffer?

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "VLM")
    private var lifecycleCancellable: AnyCancellable?
    private var generationTask: Task<Void, Error>?

    // MARK: - Init

    override init() {
        super.init()
        subscribeToModelLifecycle()
        Task { await checkModelStatus() }
    }

    // MARK: - Model

    func checkModelStatus() async {
        let state = await RunAnywhere.models.state()
        isModelLoaded = (state.loaded[.multimodal] ?? state.loaded[.vision]) != nil
    }

    /// Track the VLM model slot via the SDK event bus. Model loads publish a
    /// component-lifecycle event for SDK_COMPONENT_VLM — the single source of
    /// truth, replacing the former "VLMModelLoaded" NotificationCenter post.
    private func subscribeToModelLifecycle() {
        lifecycleCancellable = RunAnywhere.eventBus.events(for: .component)
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

    /// Resolve a capture device that exists on the current platform. iOS prefers
    /// the rear wide-angle camera (falling back to any default video device);
    /// macOS has no camera at `.back` position, so `AVCaptureDevice.default(for:)`
    /// selects the built-in/Continuity/external camera (which reports
    /// `.front`/`.unspecified`). Hard-coding `.back` returned nil on Mac, leaving
    /// Live mode permanently stuck on "Camera Access Required" even after access
    /// was granted.
    private static func defaultCameraDevice() -> AVCaptureDevice? {
        #if os(macOS)
        return AVCaptureDevice.default(for: .video)
        #else
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
        #endif
    }

    func setupCamera() {
        guard isCameraAuthorized else { return }

        let session = AVCaptureSession()
        session.sessionPreset = .medium

        guard let device = Self.defaultCameraDevice(),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureVideoDataOutput()
        // Request BGRA explicitly: the default camera output is YUV, which costs
        // an extra colour conversion on every frame we hand to the VLM.
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

    /// Stream one VLM turn into `currentDescription`. The iteration runs inside
    /// `generationTask` so `cancel()` can tear the native stream down.
    /// `clearOnFirstToken` keeps the previous answer on screen until new text
    /// arrives, which is what auto-stream mode wants.
    private func runGeneration(
        image: ImageInput,
        prompt: String,
        maxTokens: Int,
        clearOnFirstToken: Bool = false
    ) async throws {
        let options = LlmOptions(maxOutputTokens: maxTokens)
        let task = Task { @MainActor in
            let stream = try await RunAnywhere.vlm.generateStream(
                image: image,
                prompt: prompt,
                options: options
            )
            var isFirstToken = true
            for try await event in stream {
                switch event {
                case .textDelta(_, _, _, _, let text):
                    guard !text.isEmpty else { continue }
                    if isFirstToken {
                        isFirstToken = false
                        if clearOnFirstToken { self.currentDescription = "" }
                    }
                    self.currentDescription += text
                case .completed(_, let result):
                    self.logger.info(
                        "VLM streaming completed: \(result.outputTokens) tokens, \(result.tokensPerSecond) tok/s"
                    )
                default:
                    break
                }
            }
        }
        generationTask = task
        defer { generationTask = nil }
        try await task.value
    }

    func describeCurrentFrame() async {
        guard let pixelBuffer = currentFrame, !isProcessing else { return }

        isProcessing = true
        error = nil
        currentDescription = ""

        do {
            let image = try ImageInput.pixelBuffer(pixelBuffer)
            try await runGeneration(
                image: image,
                prompt: "Describe what you see briefly.",
                maxTokens: Self.liveFrameMaxTokens
            )
        } catch is CancellationError {
            // User-initiated cancel; keep whatever text already streamed in.
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
            let image = try ImageInput.uiImage(uiImage)
            try await runGeneration(
                image: image,
                prompt: "Describe this image in detail.",
                maxTokens: Self.selectedImageMaxTokens
            )
        } catch is CancellationError {
            // User-initiated cancel.
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
                throw Self.imageConversionError("Failed to convert image to VLM input")
            }
            let image = try ImageInput.cgImage(cgImage)
            try await runGeneration(
                image: image,
                prompt: "Describe this image in detail.",
                maxTokens: Self.selectedImageMaxTokens
            )
        } catch is CancellationError {
            // User-initiated cancel.
        } catch {
            self.error = error
        }

        isProcessing = false
    }
    #endif

    func cancel() {
        generationTask?.cancel()
        generationTask = nil
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

        do {
            let image = try ImageInput.pixelBuffer(pixelBuffer)
            try await runGeneration(
                image: image,
                prompt: "Describe what you see in one sentence.",
                maxTokens: Self.autoStreamMaxTokens,
                clearOnFirstToken: true
            )
        } catch is CancellationError {
            // User-initiated cancel.
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
