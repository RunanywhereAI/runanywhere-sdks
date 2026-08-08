//
//  VLMCameraView.swift
//  RunAnywhereAI
//
//  The vision workbench: a subject, a question, and a streamed answer.
//
//  Feature parity target is the web app's Vision tab
//  (`examples/web/RunAnywhereAI/src/views/vision.ts`) — an editable prompt, a
//  subject that is either the live camera or a still from disk, a cancellable
//  streamed answer, and a status line that tells "done", "done and it said
//  nothing", "cancelled" and "failed" apart. Live auto-describe is the one thing
//  this platform adds on top; the Mac additionally accepts a dropped or pasted
//  image, because refusing a drag on a Mac reads as a broken window.
//
//  Every reachable state has copy of its own, and the copy is only ever as
//  confident as the app is: a Simulator with no capture device says so and points
//  at "Choose Image" rather than telling the reader to grant access they already
//  granted, which is what the previous single `isCameraAuthorized` Bool did.
//

import AVFoundation
import RunAnywhere
import SwiftUI
import UniformTypeIdentifiers
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct VLMCameraView: View {
    @State private var viewModel = VLMViewModel()
    @ObservedObject private var modelList = ModelListViewModel.shared

    @State private var showingModelSelection = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingImageImporter = false
    /// Why the last attachment was refused. Its own state, not the run status: a
    /// rejected file has nothing to do with what the model last did, and folding
    /// the two together would have "too large" overwrite a perfectly good answer.
    @State private var attachmentError: String?
    @State private var shouldResumeAutoStreaming = false
    /// True while a drag is over the subject pane.
    @State private var isDropTargeted = false

    @FocusState private var isPromptFocused: Bool

    @Environment(\.scenePhase)
    private var scenePhase
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        content
            .background(AppColors.background)
            .navigationTitle("Live Camera")
            #if os(iOS)
            .navigationBarTitleDisplayModeCompat(.inline)
            #endif
            .toolbar { toolbarContent }
            .adaptiveSheet(isPresented: $showingModelSelection) {
                ModelSelectionSheet(context: .vlm) { _ in
                    await viewModel.checkModelStatus()
                    await viewModel.startCameraIfPossible()
                }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, item in
                Task { await adoptPickedPhoto(item) }
            }
            .fileImporter(
                isPresented: $showingImageImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                adoptImportedFile(result)
            }
            .alert(
                "That image can't be used",
                isPresented: Binding(
                    get: { attachmentError != nil },
                    set: { if !$0 { attachmentError = nil } }
                )
            ) {
                Button("OK") { attachmentError = nil }
            } message: {
                Text(attachmentError ?? "")
            }
            // Structural, not spawned: cancelling this task (Live off, leaving the
            // screen, backgrounding) tears the native stream down with it.
            .task(id: viewModel.isAutoStreamingEnabled) {
                guard viewModel.isAutoStreamingEnabled else { return }
                await viewModel.runAutoStreamLoop()
            }
            .task { await viewModel.startCameraIfPossible() }
            .onDisappear {
                viewModel.cancel()
                viewModel.stopCamera()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhase(newPhase)
            }
            .onChange(of: viewModel.isModelLoaded) { _, loaded in
                // The camera follows the model: it comes up once something can
                // look through it, and it goes away if that model is unloaded or
                // deleted mid-session rather than running behind a first-run screen.
                if loaded {
                    Task { await viewModel.startCameraIfPossible() }
                } else {
                    viewModel.cancel()
                    viewModel.stopCamera()
                }
            }
    }

    @ViewBuilder private var content: some View {
        if viewModel.isModelLoaded {
            workbench
        } else if modelList.isLoadingModel {
            // A distinct state, and not the first-run screen: offering "Choose a
            // vision model" while one is already being loaded invites the reader
            // to start a second load.
            loadingModelState
        } else {
            ModelRequiredOverlay(modality: .vlm) { showingModelSelection = true }
        }
    }

    // MARK: - Loading

    private var loadingModelState: some View {
        VStack(spacing: Space.lg) {
            ProgressView()
                .controlSize(.large)
            Text("Loading the vision model…")
                .appType(.cardTitle)
            Text("This runs on this device, so the first load takes a moment.")
                .appType(.secondary)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Workbench

    private var workbench: some View {
        VStack(spacing: 0) {
            subjectPane

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    promptField
                    answerPanel
                }
                .padding(Space.lg)
                .measured(Measure.text)
            }
            // Dragging the answer puts the keyboard away. Without it, editing the
            // question left the software keyboard covering two thirds of the
            // screen and the answer arrived behind it.
            .scrollDismissesKeyboard(.interactively)

            Divider()

            controlBar
        }
    }
}

// MARK: - Subject
//
// Everything below hangs off extensions rather than the struct's own body: a
// SwiftUI screen with seven states is genuinely this many pieces, and the type
// stays readable only if the declaration itself is the shape of the screen and
// the pieces sit beside it.

extension VLMCameraView {
    /// What the next question is about: the live preview, the picked still, or
    /// the reason there is neither.
    private var subjectPane: some View {
        ZStack {
            // A viewfinder is black. This is the one surface in the app that is
            // not a palette token, because it is a hole in the UI onto the world.
            Color.black

            subjectContent

            if viewModel.isProcessing {
                lookingHUD
            }

            if viewModel.isAutoStreamingEnabled {
                liveBadge
            }
        }
        .frame(maxWidth: .infinity)
        // A 4:3 well rather than a fraction of `UIScreen.main.bounds`, which is
        // the wrong number in a Slide Over, in Stage Manager, and on the Mac.
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .frame(maxHeight: 440)
        .clipped()
        .overlay { dropCue }
        // Mac-native, and harmless on iOS where dragging a photo out of Photos
        // onto the app does the same thing.
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            adoptDroppedProviders(providers)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(subjectAccessibilityLabel)
    }

    @ViewBuilder private var subjectContent: some View {
        if let picked = viewModel.pickedImage {
            VStack(spacing: 0) {
                picked.preview
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Selected image: \(picked.filename)")

                pickedImageBar(filename: picked.filename)
            }
        } else if viewModel.cameraStatus == .ready, let session = viewModel.captureSession {
            CameraPreview(session: session)
                .accessibilityLabel("Live camera preview")
        } else {
            cameraStateView
        }
    }

    /// Names the still and offers the way back to the camera. Without it the
    /// preview is a photo with no indication that the camera has been displaced.
    private func pickedImageBar(filename: String) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "photo")
                .appType(.caption)
            Text(filename)
                .appType(.caption)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: Space.sm)

            Button {
                Task { await viewModel.clearPickedImage() }
            } label: {
                Label("Use Camera", systemImage: "camera")
                    .appType(.caption)
            }
            .buttonStyle(.borderless)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .frame(minHeight: Measure.hitTarget)
        .background(.ultraThinMaterial)
    }

    /// One screen per camera outcome, each ending in the way forward.
    private var cameraStateView: some View {
        VStack(spacing: Space.md) {
            if case .requestingAccess = viewModel.cameraStatus {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: cameraStateGlyph)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }

            Text(cameraStateTitle)
                .appType(.cardTitle)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(cameraStateMessage)
                .appType(.secondary)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            HStack(spacing: Space.md) {
                ForEach(cameraStateActions, id: \.title) { action in
                    Button(action.title, action: action.perform)
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
            }
            .padding(.top, Space.xs)
        }
        .padding(Space.lg)
    }

    private var cameraStateGlyph: String {
        switch viewModel.cameraStatus {
        case .denied, .restricted: return "lock.slash"
        case .unavailable: return "video.slash"
        case .idle, .requestingAccess, .ready: return "camera"
        }
    }

    private var cameraStateTitle: String {
        switch viewModel.cameraStatus {
        case .idle: return "Camera off"
        case .requestingAccess: return "Waiting for permission"
        case .ready: return "Starting the camera…"
        case .denied: return "Camera access is off"
        case .restricted: return "Camera use is restricted"
        case .unavailable: return "No camera available"
        }
    }

    private var cameraStateMessage: String {
        switch viewModel.cameraStatus {
        case .idle:
            return "Start the camera to ask about what it sees, or choose an image instead."
        case .requestingAccess:
            return "Allow camera access to use the live view."
        case .ready:
            // `.ready` with no session is a beat, not a state. Say what is
            // happening rather than inventing a problem.
            return "The preview appears in a moment."
        case .denied:
            #if os(iOS)
            return "Turn Camera on for \(Self.appDisplayName) in Settings, or choose an image instead."
            #else
            return "Allow \(Self.appDisplayName) under Privacy & Security ▸ Camera, "
                + "or choose an image instead."
            #endif
        case .restricted:
            return "A Screen Time or device-management policy blocks the camera. "
                + "You can still ask about an image."
        case .unavailable(let reason):
            return reason
        }
    }

    private struct CameraStateAction {
        let title: String
        let perform: () -> Void
    }

    private var cameraStateActions: [CameraStateAction] {
        let chooseImage = CameraStateAction(title: "Choose Image") { showingPhotoPicker = true }

        switch viewModel.cameraStatus {
        case .requestingAccess, .ready:
            return []
        case .idle:
            return [
                CameraStateAction(title: "Start Camera") { Task { await viewModel.retryCamera() } },
                chooseImage
            ]
        case .unavailable:
            // "Try Again", not "Start Camera": the same tap on a Mac that has
            // just had a camera plugged in succeeds, and on a Simulator it
            // cannot. A retry is what the button honestly promises; starting the
            // camera is not something it can guarantee.
            return [
                CameraStateAction(title: "Try Again") { Task { await viewModel.retryCamera() } },
                chooseImage
            ]
        case .denied:
            return [
                CameraStateAction(title: "Open Settings", perform: openPrivacySettings),
                chooseImage
            ]
        case .restricted:
            // No Settings button: policy is not something this reader can undo,
            // and a button that opens a pane where the switch is greyed out is
            // worse than no button.
            return [chooseImage]
        }
    }

    /// The name the platform itself shows for this app.
    ///
    /// Read from the bundle rather than written into the sentence: the target is
    /// `RunAnywhereAI` but the display name is `RunAnywhere`, so a hardcoded
    /// string sent the reader looking in Settings for a row that is not there.
    private static let appDisplayName: String = {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleDisplayName"] as? String
            ?? info?[kCFBundleNameKey as String] as? String
            ?? "this app"
    }()

    private var subjectAccessibilityLabel: String {
        if let picked = viewModel.pickedImage { return "Subject: image \(picked.filename)" }
        if viewModel.cameraStatus == .ready { return "Subject: live camera" }
        return "\(cameraStateTitle). \(cameraStateMessage)"
    }

    private var lookingHUD: some View {
        VStack {
            Spacer()
            HStack(spacing: Space.sm) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("Looking…")
                    .appType(.caption)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, Space.lg)
        }
        .allowsHitTesting(false)
    }

    /// Word plus dot, never dot alone — a green circle is not a state anyone can
    /// read, and it is invisible to a reader who cannot separate it from red.
    private var liveBadge: some View {
        VStack {
            HStack {
                HStack(spacing: Space.xs) {
                    Circle()
                        .fill(AppColors.statusGreen)
                        .frame(width: 8, height: 8)
                    Text("LIVE")
                        .appType(.chip)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, Space.sm)
                .padding(.vertical, Space.xs)
                .background(.ultraThinMaterial, in: Capsule())

                Spacer()
            }
            Spacer()
        }
        .padding(Space.md)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var dropCue: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    AppColors.brand,
                    style: StrokeStyle(lineWidth: Stroke.emphasis, dash: [7, 5])
                )
                .background(AppColors.brand.opacity(0.10))
                .overlay {
                    Label("Drop an image", systemImage: "arrow.down.doc")
                        .appType(.cardTitle)
                        .foregroundStyle(AppColors.brandInk)
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, Space.md)
                        .background(.regularMaterial, in: Capsule())
                }
                .padding(Space.md)
                .allowsHitTesting(false)
                .transition(.opacity)
                .motionAware(Motion.microFade, value: isDropTargeted)
        }
    }

    // MARK: - Prompt

    private var promptField: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("QUESTION")
                .appType(.overline)
                .foregroundStyle(AppColors.textSecondary)

            TextField(
                "What's in this image?",
                text: $viewModel.prompt,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .appType(.body)
            .lineLimit(1...4)
            .focused($isPromptFocused)
            .padding(Space.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(AppColors.surfaceSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(AppColors.borderSubtle, lineWidth: Hairline.width)
            )
            .accessibilityLabel("Question about the image")

            Text("Live mode asks this same question every \(VLMViewModel.autoStreamIntervalLabel).")
                .appType(.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    // MARK: - Answer

    private var answerPanel: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Text("ANSWER")
                    .appType(.overline)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()

                if !viewModel.currentDescription.isEmpty {
                    Button {
                        copyAnswer()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .appType(.caption)
                            .labelStyle(.iconOnly)
                            .frame(width: Measure.hitTarget, height: Measure.hitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityLabel("Copy the answer")
                    .help("Copy the answer")
                }
            }

            // Above the answer, not below it. A long description is taller than
            // the pane, so a status line underneath sat off the bottom of the
            // scroll view — the one line that says whether the run finished,
            // said nothing, was cancelled or failed was the line nobody saw.
            if let status = runStatusLine {
                Text(status.text)
                    .appType(.meta)
                    .foregroundStyle(status.isFailure ? AppColors.dangerText : AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Status: \(status.text)")
            }

            if viewModel.currentDescription.isEmpty {
                Text(emptyAnswerHint)
                    .appType(.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Through the app's renderer, like the chat transcript: a VLM
                // answers in the same markdown an LLM does, and this pane used to
                // print the literal `**Description:**` and `1.` list markers it
                // emitted.
                AdaptiveMarkdownText(
                    viewModel.currentDescription,
                    font: AppType.font(.body),
                    color: AppColors.foreground
                )
                .textSelection(.enabled)
            }
        }
    }

    private var emptyAnswerHint: String {
        if viewModel.pickedImage != nil {
            return "Tap Ask to describe this image."
        }
        guard viewModel.hasSubject else {
            return "Point the camera at something, or choose an image, and the answer appears here."
        }
        return "Tap Ask for one answer, or turn on Live to keep describing what the camera sees."
    }

    private struct RunStatusLine {
        let text: String
        let isFailure: Bool
    }

    /// Each outcome gets its own sentence, so "it answered nothing" is never
    /// mistaken for "you cancelled it" — which an empty answer pane cannot say.
    private var runStatusLine: RunStatusLine? {
        switch viewModel.runStatus {
        case .idle:
            return nil
        case .running:
            return RunStatusLine(text: "Generating…", isFailure: false)
        case let .completed(tokens, tokensPerSecond):
            guard tokensPerSecond > 0 else { return RunStatusLine(text: "Done.", isFailure: false) }
            let rate = String(format: "%.1f", tokensPerSecond)
            return RunStatusLine(text: "Done — \(tokens) tokens at \(rate) tok/s.", isFailure: false)
        case .producedNothing:
            return RunStatusLine(text: "Done — the model returned no text.", isFailure: false)
        case .cancelled:
            return RunStatusLine(text: "Cancelled.", isFailure: false)
        case .failed(let message):
            return RunStatusLine(text: message, isFailure: true)
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(alignment: .top, spacing: Space.xl) {
            askControl
            liveControl
            libraryControl
            filesControl
            modelControl
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(maxWidth: .infinity)
        .background(AppColors.surface)
    }

    /// One slot, two jobs: Ask when nothing is running, Stop when something is.
    /// A single button so the row never reflows mid-answer, and so Stop is where
    /// the finger already is.
    private var askControl: some View {
        let isStopping = viewModel.isProcessing || viewModel.isAutoStreamingEnabled

        return VStack(spacing: Space.xs) {
            Button {
                Haptics.light()
                // The question has been asked; the keyboard's job is over, and
                // leaving it up hides the answer it was asked to produce.
                isPromptFocused = false
                if isStopping {
                    viewModel.cancel()
                } else {
                    viewModel.ask()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(isStopping ? AppColors.danger : AppColors.brand)
                        .frame(width: 60, height: 60)

                    Image(systemName: isStopping ? "stop.fill" : "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        // Ink on orange (6.1:1); white on the red stop reads at
                        // 3.9:1, which large/bold glyph work is allowed.
                        .foregroundStyle(isStopping ? AppColors.onBrandLarge : AppColors.onBrand)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isStopping && !viewModel.canAsk)
            .motionAware(Motion.microFade, value: isStopping)

            Text(isStopping ? "Stop" : "Ask")
                .appType(.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isStopping ? "Stop" : "Ask about the image")
        .accessibilityHint(askAccessibilityHint(isStopping: isStopping))
    }

    private func askAccessibilityHint(isStopping: Bool) -> String {
        if isStopping { return "Stops the answer that is being generated." }
        if !viewModel.hasSubject { return "Unavailable until the camera is running or an image is chosen." }
        return "Asks the question once."
    }

    /// Disabled — not hidden — when there is no live subject, and it says why in
    /// its own help/hint rather than silently doing nothing.
    private var liveControl: some View {
        let canGoLive = viewModel.pickedImage == nil && viewModel.hasSubject

        return VLMSecondaryControl(
            title: "Live",
            systemImage: viewModel.isAutoStreamingEnabled ? "livephoto" : "livephoto.slash",
            tint: viewModel.isAutoStreamingEnabled ? AppColors.successText : AppColors.textSecondary,
            isEnabled: canGoLive || viewModel.isAutoStreamingEnabled,
            help: liveHelp(canGoLive: canGoLive)
        ) {
            viewModel.toggleAutoStreaming()
        }
        .symbolEffect(
            .pulse,
            // A perpetual pulse is exactly the motion Reduce Motion asks us to
            // drop; the word "LIVE" on the preview still carries the state.
            isActive: viewModel.isAutoStreamingEnabled && !reduceMotion
        )
    }

    private func liveHelp(canGoLive: Bool) -> String {
        if viewModel.isAutoStreamingEnabled {
            return "Stop describing automatically"
        }
        if viewModel.pickedImage != nil {
            return "Live needs the camera — a still image never changes"
        }
        if !viewModel.hasSubject {
            return "Live needs a running camera"
        }
        return "Describe what the camera sees every \(VLMViewModel.autoStreamIntervalLabel)"
    }

    private var libraryControl: some View {
        VLMSecondaryControl(
            title: "Photos",
            systemImage: "photo.on.rectangle",
            isEnabled: !viewModel.isProcessing,
            help: "Ask about a photo from your library"
        ) {
            showingPhotoPicker = true
        }
    }

    private var filesControl: some View {
        VLMSecondaryControl(
            title: "Files",
            systemImage: "folder",
            isEnabled: !viewModel.isProcessing,
            help: "Ask about an image file"
        ) {
            showingImageImporter = true
        }
    }

    private var modelControl: some View {
        VLMSecondaryControl(
            title: "Model",
            systemImage: "cube",
            isEnabled: !viewModel.isProcessing,
            help: viewModel.loadedModelName.map { "\($0) — choose a different vision model" }
                ?? "Choose a vision model"
        ) {
            showingModelSelection = true
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            if let name = viewModel.loadedModelName {
                Text(name)
                    .appType(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityLabel("Vision model: \(name)")
            }
        }
    }

    // MARK: - Scene phase

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            shouldResumeAutoStreaming = viewModel.isAutoStreamingEnabled
            viewModel.cancel()
            viewModel.stopCamera()
        case .active:
            Task {
                await viewModel.startCameraIfPossible()
                if shouldResumeAutoStreaming {
                    shouldResumeAutoStreaming = false
                    viewModel.isAutoStreamingEnabled = true
                }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Picking a subject

    @MainActor
    private func adoptPickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { selectedPhotoItem = nil }

        do {
            viewModel.usePickedImage(try await ChatAttachmentLoader.imageAttachment(from: item))
        } catch {
            attachmentError = error.localizedDescription
        }
    }

    private func adoptImportedFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { @MainActor in
                await adoptFile(at: url)
            }
        case .failure(let error):
            attachmentError = error.localizedDescription
        }
    }

    /// The one validating path for a file, whichever way it arrived. The
    /// importer's `allowedContentTypes` only filters its own list — the reader
    /// can switch it to "All Files", and a drop never consults it at all.
    @MainActor
    private func adoptFile(at url: URL) async {
        do {
            viewModel.usePickedImage(try await ChatAttachmentLoader.imageAttachment(forFileAt: url))
        } catch {
            attachmentError = error.localizedDescription
        }
    }

    /// Claim the first item of a drop. One item, because the workbench asks about
    /// one picture and quietly discarding the other nine would be worse than
    /// saying so. Returns `true` so the pointer does not animate a rejection
    /// while the asynchronous read is still running.
    private func adoptDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        Task { @MainActor in
            do {
                if let url = try await ChatAttachmentLoader.fileURL(from: provider) {
                    await adoptFile(at: url)
                } else if let data = try await ChatAttachmentLoader.imageData(from: provider) {
                    viewModel.usePickedImage(try ChatAttachmentLoader.imageAttachment(
                        from: data,
                        filename: provider.suggestedName ?? "Dropped image"
                    ))
                } else {
                    attachmentError = "That can't be used here. Drop an image file, or a picture "
                        + "dragged from Photos, Preview, or a browser."
                }
            } catch {
                attachmentError = error.localizedDescription
            }
        }
        return true
    }

    // MARK: - Platform actions

    private func copyAnswer() {
        #if canImport(UIKit)
        UIPasteboard.general.string = viewModel.currentDescription
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.currentDescription, forType: .string)
        #endif
        Haptics.light()
    }

    private func openPrivacySettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #elseif os(macOS)
        // The camera pane specifically, not the top of System Settings: a reader
        // sent to the front door has to find Privacy & Security themselves.
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        ) else { return }
        NSWorkspace.shared.open(url)
        #endif
    }
}

// MARK: - Secondary control

/// One of the small labelled controls in the bar beside Ask.
///
/// A view rather than a six-argument builder method: the arguments were the
/// control, so naming them once here is both shorter at each call site and the
/// only place the 44pt hit target and the help/hint pairing are decided.
private struct VLMSecondaryControl: View {
    let title: String
    let systemImage: String
    var tint: Color = AppColors.textSecondary
    let isEnabled: Bool
    /// Doubles as the VoiceOver hint, so a pointer user and a screen-reader user
    /// are told the same thing about a control that is disabled.
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .appType(.caption)
            }
            .foregroundStyle(tint)
            // 44pt under a coarse pointer, 28 on the Mac — the shared token, so
            // one control cannot drift below the floor the rest of the app holds.
            .frame(minWidth: Measure.hitTarget, minHeight: Measure.hitTarget + 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityHint(help)
    }
}
