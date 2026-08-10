//
//  VLMViewModel.swift
//  RunAnywhereAI
//
//  The vision workbench's state: what the camera is doing, which picture the
//  next question is about, and what the model said back.
//
//  Feature parity target is the web app's Vision tab
//  (`examples/web/RunAnywhereAI/src/views/vision.ts`): an editable prompt, a
//  subject that can be either the live camera or a still loaded from disk, a
//  cancellable streamed answer, and a status line that distinguishes "done",
//  "done and the model said nothing", "cancelled" and "failed". Live
//  auto-streaming is the one capability this platform adds on top.
//

import Combine
import Foundation
import RunAnywhere
import SwiftUI
import os.log
@preconcurrency import AVFoundation

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Status vocabulary

/// Why the preview is, or is not, showing a camera.
///
/// One value rather than the old `isCameraAuthorized` Bool. "You declined",
/// "an administrator declined for you" and "there is no camera here at all"
/// need three different things from the reader, and a Bool rendered all three
/// as "Camera Access Required → Open Settings". On the Simulator, which has no
/// capture device, that told the user to grant access they had already granted
/// and left no way forward.
enum VLMCameraStatus: Equatable {
    /// Nothing has touched the camera yet — no vision model is loaded.
    case idle
    /// The system permission prompt is on screen.
    case requestingAccess
    /// A session exists and can deliver frames.
    case ready
    /// The user said no. Settings can undo it.
    case denied
    /// Policy (Screen Time, MDM) forbids it. Settings cannot undo it.
    case restricted
    /// No usable capture device. Carries the reason so the screen can say it.
    case unavailable(String)
}

/// What the last — or current — question did.
///
/// An enum rather than a status string so a new outcome cannot be added without
/// deciding what the screen says about it, and so "streamed nothing" stays
/// distinguishable from "was cancelled", which an empty answer pane cannot.
enum VLMRunStatus: Equatable {
    case idle
    case running
    /// Finished with text. `outputTokens == 0` means the backend reported no
    /// counters, not that it emitted nothing — that case is `producedNothing`.
    ///
    /// `tokensPerSecond` is `Float` because `GenerationResult` reports it as one;
    /// widening it here would have every construction site do a conversion that
    /// buys the screen nothing.
    case completed(outputTokens: Int, tokensPerSecond: Float)
    /// Finished cleanly and emitted no text at all.
    case producedNothing
    case cancelled
    case failed(String)
}

/// A still the user picked, standing in for the live camera as the subject of
/// the next question.
struct VLMPickedImage: Identifiable {
    let id = UUID()
    let filename: String
    let input: ImageInput
    let preview: Image
}

// MARK: - VLM View Model

@MainActor
@Observable
final class VLMViewModel: NSObject {
    // MARK: - Model

    private(set) var isModelLoaded = false
    private(set) var loadedModelName: String?

    // MARK: - Subject

    /// The question asked of every frame.
    ///
    /// Editable, and it is also what Live mode asks. The previous build kept a
    /// hard-coded sentence per mode, so there was nothing on screen to change
    /// and no way to ask the picture anything else.
    var prompt: String = VLMViewModel.defaultPrompt

    /// Matches the web app's default prompt verbatim.
    static let defaultPrompt = "Describe what you see in this image."

    /// When set, questions are asked of this still rather than the camera.
    private(set) var pickedImage: VLMPickedImage?

    // MARK: - Run

    private(set) var isProcessing = false
    private(set) var currentDescription = ""
    private(set) var runStatus: VLMRunStatus = .idle

    // MARK: - Auto streaming

    var isAutoStreamingEnabled = false
    static let autoStreamInterval: TimeInterval = 2.5

    /// The interval as a sentence, so the copy on screen and the timer that
    /// drives it cannot drift apart. `Int(2.5)` reads "every 2 seconds", which is
    /// a promise the loop does not keep.
    static var autoStreamIntervalLabel: String {
        autoStreamInterval == autoStreamInterval.rounded()
            ? "\(Int(autoStreamInterval)) seconds"
            : String(format: "%.1f seconds", autoStreamInterval)
    }

    private static let singleShotMaxTokens = 128
    private static let autoStreamMaxTokens = 64

    // MARK: - Camera

    private(set) var cameraStatus: VLMCameraStatus = .idle
    private(set) var captureSession: AVCaptureSession?

    /// True once the session has delivered a frame.
    ///
    /// Separate from `currentFrame` on purpose: the view needs to know whether
    /// there is anything to ask about, and reading the buffer itself from a
    /// view body would make `@Observable` re-render the screen at frame rate.
    /// This flips false→true once per session instead.
    private(set) var hasCameraFrame = false

    private var currentFrame: CVPixelBuffer?

    /// One queue for the life of the view model. Building a new one per
    /// `setupCamera()` leaked a queue every time the model was swapped.
    private let frameQueue = DispatchQueue(label: "com.runanywhere.vlm.camera")

    /// True from the moment `startCameraIfPossible()` begins building a session
    /// until it has one (or has given up).
    ///
    /// `authorizeCamera()` suspends on the system permission prompt, and this
    /// screen calls `startCameraIfPossible()` from four places — `.task`, the
    /// scene-phase change, the model-loaded transition and the picker's
    /// completion. On a first run they arrive together, so without this flag two
    /// of them clear the `captureSession == nil` check across that suspension and
    /// build two sessions; the loser is dropped while still running, holding the
    /// device and the platform's camera indicator.
    private var isStartingCamera = false

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "VLM")
    private var lifecycleCancellable: AnyCancellable?
    private var generationTask: Task<Void, Never>?

    // MARK: - Init

    override init() {
        super.init()
        subscribeToModelLifecycle()
        Task { await checkModelStatus() }
    }

    // MARK: - Model

    func checkModelStatus() async {
        let state = await RunAnywhere.models.state()
        // Both slots, matching `RunAnywhere.vlm`'s own resolution order
        // (`.multimodal` with a `.vision` fallback) and the web app's picker.
        let loaded = state.loaded[.multimodal] ?? state.loaded[.vision]
        isModelLoaded = loaded != nil
        if let loaded {
            loadedModelName = ModelListViewModel.shared.availableModels
                .first { $0.id == loaded.id }?.name ?? loaded.id
        } else {
            loadedModelName = nil
        }
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

    /// What to say when the machine simply has no camera to offer. Each phrase
    /// ends with the way forward, because "load an image" is a real answer here
    /// and "open Settings" is not.
    private static var noCaptureDeviceMessage: String {
        // "Choose an image", not "load an image" — the button beneath these
        // sentences says Choose Image, and copy that names a control by a
        // different word than the control's own label sends the reader hunting.
        #if targetEnvironment(simulator)
        return "The Simulator has no camera. Choose an image instead, or run on a device."
        #elseif os(macOS)
        return "No camera is connected to this Mac. Attach one, or choose an image instead."
        #else
        return "No camera is available on this device. Choose an image instead."
        #endif
    }

    /// Bring the camera up, if this device has one and the user allows it.
    ///
    /// Idempotent: safe to call from `onAppear`, from a scene-phase change and
    /// from the model-loaded transition, which is what the screen does.
    func startCameraIfPossible() async {
        // Don't touch the camera until a vision model is ready. Otherwise the
        // session (and the platform's camera privacy indicator) runs behind the
        // "choose a vision model" screen with nothing to feed, and the
        // permission prompt arrives before the user has asked for anything.
        guard isModelLoaded else { return }
        // A second caller joins rather than races: the one already in flight is
        // building the session both of them want.
        guard !isStartingCamera else { return }

        if captureSession == nil {
            isStartingCamera = true
            defer { isStartingCamera = false }
            guard await authorizeCamera(), configureSession() else { return }
        }
        startCamera()
    }

    /// Drop a failed/refused session so the next attempt genuinely re-asks
    /// rather than short-circuiting on a stale status.
    func retryCamera() async {
        // Stop before dropping the reference. Releasing a running
        // `AVCaptureSession` does not stop it — it keeps the capture device
        // claimed and the camera indicator lit, and the next `configureSession()`
        // then fails at `canAddInput` and blames "another app" for us.
        stopCamera()
        captureSession = nil
        cameraStatus = .idle
        await startCameraIfPossible()
    }

    private func authorizeCamera() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            cameraStatus = .requestingAccess
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted { cameraStatus = .denied }
            return granted
        case .denied:
            cameraStatus = .denied
            return false
        case .restricted:
            cameraStatus = .restricted
            return false
        @unknown default:
            cameraStatus = .unavailable("This device would not report its camera permission.")
            return false
        }
    }

    /// Build the capture session, reporting *which* step failed.
    ///
    /// Every early return here used to be a bare `return`, so a Mac with the
    /// camera already claimed by another app, and a Simulator with no camera at
    /// all, both ended on the permission screen.
    private func configureSession() -> Bool {
        guard let device = Self.defaultCameraDevice() else {
            cameraStatus = .unavailable(Self.noCaptureDeviceMessage)
            return false
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            cameraStatus = .unavailable(error.localizedDescription)
            return false
        }

        let session = AVCaptureSession()
        session.sessionPreset = .medium

        guard session.canAddInput(input) else {
            cameraStatus = .unavailable("\(device.localizedName) is in use by another app.")
            return false
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        // Request BGRA explicitly: the default camera output is YUV, which costs
        // an extra colour conversion on every frame we hand to the VLM.
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: frameQueue)
        output.alwaysDiscardsLateVideoFrames = true

        guard session.canAddOutput(output) else {
            cameraStatus = .unavailable("\(device.localizedName) cannot deliver video frames.")
            return false
        }
        session.addOutput(output)

        #if os(iOS)
        // Rotate the *frames* the way the preview layer already rotates itself.
        //
        // `AVCaptureVideoPreviewLayer` defaults to portrait, but a video data
        // output hands back the sensor's native landscape buffer — so on a
        // portrait phone the user saw an upright scene while the model was asked
        // about a picture lying on its side. Rotating text 90° is exactly the
        // input a VLM cannot read, which made "read this sign" fail for reasons
        // nothing on screen explained.
        if let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        #endif

        captureSession = session
        cameraStatus = .ready
        return true
    }

    private func startCamera() {
        guard let session = captureSession, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    func stopCamera() {
        hasCameraFrame = false
        currentFrame = nil
        guard let session = captureSession, session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }

    private func receive(frame: CVPixelBuffer) {
        currentFrame = frame
        // Written through a guard so the property only changes once per session;
        // assigning `true` on every frame would notify observers 30 times a
        // second for a value that never actually changes.
        if !hasCameraFrame { hasCameraFrame = true }
    }

    // MARK: - Picked stills

    /// Ask about a still instead of the camera.
    func usePickedImage(_ attachment: ChatImageAttachment) {
        guard let preview = Self.previewImage(from: attachment.data) else {
            runStatus = .failed("That image could not be displayed.")
            return
        }
        // A picked still and a live feed are two subjects; Live mode would keep
        // re-describing a photo that never changes.
        isAutoStreamingEnabled = false
        cancel()
        // And the camera stops. Nothing is showing its preview any more, so a
        // running session only drains the battery and holds the platform's
        // camera-in-use indicator on over a screen that is displaying a photo.
        stopCamera()
        pickedImage = VLMPickedImage(
            filename: attachment.filename,
            input: attachment.image,
            preview: preview
        )
        currentDescription = ""
        runStatus = .idle
    }

    /// Hand the camera back the subject.
    ///
    /// Restarts the session `usePickedImage` stopped — the caller does not have
    /// to remember that the picked-image path turned it off.
    func clearPickedImage() async {
        pickedImage = nil
        currentDescription = ""
        runStatus = .idle
        await startCameraIfPossible()
    }

    private static func previewImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        return UIImage(data: data).map(Image.init(uiImage:))
        #elseif canImport(AppKit)
        return NSImage(data: data).map(Image.init(nsImage:))
        #else
        return nil
        #endif
    }

    // MARK: - Asking

    /// True when there is a picture for a question to be about.
    ///
    /// Separate from `canAsk` because the Live toggle needs the same fact while a
    /// run is in flight, and `canAsk` is false then.
    var hasSubject: Bool {
        pickedImage != nil || hasCameraFrame
    }

    /// True when the Ask control can do what its label promises.
    var canAsk: Bool {
        isModelLoaded && !isProcessing && hasSubject
    }

    /// Ask one question about the current subject.
    func ask() {
        guard !isProcessing else { return }
        // `isProcessing` is raised inside the task body, which does not start
        // synchronously, so two calls in one run-loop turn both clear the guard
        // above. Without this the second assignment orphans the first task and
        // `cancel()` can no longer reach it — two runs then write the same
        // answer pane and status line.
        generationTask?.cancel()
        generationTask = Task { @MainActor [weak self] in
            await self?.run(maxTokens: Self.singleShotMaxTokens, clearOnFirstToken: false)
        }
    }

    /// Stop the run that is in flight.
    ///
    /// Also turns Live off: a Stop that left auto-streaming armed would fire the
    /// next capture 2.5 seconds later, so the button would have cancelled
    /// nothing the user could see.
    func cancel() {
        isAutoStreamingEnabled = false
        generationTask?.cancel()
        generationTask = nil
    }

    func toggleAutoStreaming() {
        isAutoStreamingEnabled.toggle()
    }

    /// Driven by the view's `.task(id: isAutoStreamingEnabled)`.
    ///
    /// Each turn is awaited *structurally* — no inner `Task` — so cancelling
    /// that view task (turning Live off, leaving the screen, backgrounding the
    /// app) tears the native stream down with it. The previous build spawned an
    /// unstructured task per turn, so "Stop" stopped the loop while the model
    /// kept generating into a view nobody was watching.
    func runAutoStreamLoop() async {
        while !Task.isCancelled {
            // Skip the turn rather than run one that can only fail. Live can be
            // switched on in the beat before the first frame lands, and it stays
            // on if the camera is later stopped — both would otherwise post
            // "there's nothing to look at" every 2.5 seconds as if the model had
            // failed.
            if hasSubject {
                await run(maxTokens: Self.autoStreamMaxTokens, clearOnFirstToken: true)
            }
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: UInt64(Self.autoStreamInterval * 1_000_000_000))
        }
    }

    /// The subject of the next question: the picked still, else the newest
    /// camera frame. Throws rather than returning nil so the reason reaches the
    /// status line.
    ///
    /// The frame is handed to `ImageInput` as a `CVPixelBuffer`. Pixel format
    /// conversion is the SDK's job — nothing here goes through `CIContext`.
    private func currentSubject() throws -> ImageInput {
        if let pickedImage { return pickedImage.input }
        guard let currentFrame else {
            throw LLMError.custom(
                cameraStatus == .ready
                    ? "The camera hasn't delivered a frame yet. Give it a moment."
                    : "There's nothing to look at yet. Start the camera, or load an image."
            )
        }
        return try ImageInput.pixelBuffer(currentFrame)
    }

    private var effectivePrompt: String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultPrompt : trimmed
    }

    /// One turn, run inside the caller's task so cancellation propagates.
    ///
    /// `clearOnFirstToken` keeps the previous answer on screen until new text
    /// arrives, which is what Live mode wants — blanking the pane between
    /// captures makes the panel strobe.
    private func run(maxTokens: Int, clearOnFirstToken: Bool) async {
        isProcessing = true
        runStatus = .running
        if !clearOnFirstToken { currentDescription = "" }
        defer { isProcessing = false }

        do {
            let image = try currentSubject()
            let stream = try await RunAnywhere.vlm.generateStream(
                image: image,
                prompt: effectivePrompt,
                options: LlmOptions(maxOutputTokens: maxTokens)
            )

            var isFirstToken = true
            var sawTerminal = false

            for try await event in stream {
                let isTerminal = apply(
                    event,
                    isFirstToken: &isFirstToken,
                    clearOnFirstToken: clearOnFirstToken
                )
                sawTerminal = sawTerminal || isTerminal
            }

            if !sawTerminal {
                runStatus = terminalStatusWithoutEvent()
            }
        } catch is CancellationError {
            runStatus = .cancelled
        } catch {
            runStatus = .failed(error.localizedDescription)
            logger.error("VLM run failed: \(error.localizedDescription)")
        }
    }

    /// Fold one stream event into the screen's state. Returns true when the event
    /// was a terminal one, so the caller knows the stream said how it ended
    /// rather than merely stopping.
    private func apply(
        _ event: GenerationEvent,
        isFirstToken: inout Bool,
        clearOnFirstToken: Bool
    ) -> Bool {
        switch event {
        case .textDelta(_, _, _, _, let text):
            guard !text.isEmpty else { return false }
            if isFirstToken {
                isFirstToken = false
                if clearOnFirstToken { currentDescription = "" }
            }
            currentDescription += text
            return false

        case .completed(_, let result):
            if currentDescription.isEmpty, !result.text.isEmpty {
                currentDescription = result.text
            }
            runStatus = currentDescription.isEmpty
                ? .producedNothing
                : .completed(
                    outputTokens: result.outputTokens,
                    tokensPerSecond: result.tokensPerSecond
                )
            logger.info(
                "VLM run completed: \(result.outputTokens) tokens, \(result.tokensPerSecond) tok/s"
            )
            return true

        case .failed(_, _, let error):
            // `vlm.generateStream` reports failure as an *event*, not by throwing
            // (same grammar as `llm.generateStream`). Without this branch a run
            // that died mid-answer was indistinguishable from one that simply
            // finished early, and the screen said nothing at all.
            runStatus = .failed(error.localizedDescription)
            logger.error("VLM run failed: \(error.localizedDescription)")
            return true

        case .cancelled:
            runStatus = .cancelled
            return true

        default:
            return false
        }
    }

    /// The stream ended without a terminal event — decide which outcome it was
    /// from what actually happened, rather than claiming success.
    private func terminalStatusWithoutEvent() -> VLMRunStatus {
        if Task.isCancelled { return .cancelled }
        if currentDescription.isEmpty { return .producedNothing }
        return .completed(outputTokens: 0, tokensPerSecond: 0)
    }
}

// MARK: - Camera Delegate

extension VLMViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        Task { @MainActor in self.receive(frame: pixelBuffer) }
    }
}
