//
//  VLMCameraView.swift
//  RunAnywhereAI
//
//  Simple camera view for Vision Language Model
//

import SwiftUI
import AVFoundation
import RunAnywhere

// MARK: - Live Mode View

struct VLMCameraView: View {
    @State private var viewModel = VLMViewModel()
    @State private var showingModelSelection = false
    @State private var shouldResumeAutoStreaming = false
    @Environment(\.scenePhase)
    private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isModelLoaded {
                mainContent
            } else {
                modelRequiredContent
            }
        }
        .navigationTitle("Live Mode")
        #if os(iOS)
        .navigationBarTitleDisplayModeCompat(.inline)
        #endif
        .toolbar { toolbarContent }
        #if os(iOS)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .adaptiveSheet(isPresented: $showingModelSelection) {
            ModelSelectionSheet(context: .vlm) { _ in
                await viewModel.checkModelStatus()
                setupCameraIfNeeded()
            }
        }
        .task(id: viewModel.isAutoStreamingEnabled) {
            guard viewModel.isAutoStreamingEnabled else { return }
            await viewModel.runAutoStreamLoop()
        }
        .onAppear { setupCameraIfNeeded() }
        .onDisappear {
            viewModel.isAutoStreamingEnabled = false
            viewModel.stopCamera()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                shouldResumeAutoStreaming = viewModel.isAutoStreamingEnabled
                viewModel.isAutoStreamingEnabled = false
                viewModel.stopCamera()
            } else if newPhase == .active {
                setupCameraIfNeeded()
                if shouldResumeAutoStreaming {
                    viewModel.isAutoStreamingEnabled = true
                    shouldResumeAutoStreaming = false
                }
            }
        }
        .onChange(of: viewModel.isModelLoaded) { _, loaded in
            // Start the camera once a model is ready; stop it if the model is
            // unloaded/deleted mid-session so the session doesn't keep running
            // behind the "choose a vision model" prompt.
            if loaded { setupCameraIfNeeded() } else { viewModel.stopCamera() }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Camera preview
            cameraPreview

            // Description
            descriptionPanel

            // Controls
            controlBar
        }
    }

    private var cameraPreview: some View {
        GeometryReader { _ in
            ZStack {
                if viewModel.isCameraAuthorized, let session = viewModel.captureSession {
                    CameraPreview(session: session)
                } else {
                    cameraPermissionView
                }

                // Processing overlay
                if viewModel.isProcessing {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text("Looking...").font(.caption).foregroundColor(.white)
                        }
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(AppSpacing.cornerRadiusModal)
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        #if os(iOS)
        .frame(height: UIScreen.main.bounds.height * 0.45)
        #else
        .frame(height: 400)
        #endif
    }

    private var cameraPermissionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill").font(.largeTitle).foregroundColor(AppColors.statusGray)
            Text("Camera Access Required").font(.headline).foregroundColor(.white)
            #if os(iOS)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            #endif
        }
    }

    private var descriptionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Text("Live answer")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    if viewModel.isAutoStreamingEnabled {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(AppColors.statusGreen)
                                .frame(width: 8, height: 8)
                            Text("LIVE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(AppColors.statusGreen)
                        }
                    }
                }
                Spacer()
                if !viewModel.currentDescription.isEmpty {
                    Button {
                        #if os(iOS)
                        UIPasteboard.general.string = viewModel.currentDescription
                        #elseif os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.currentDescription, forType: .string)
                        #endif
                    } label: {
                        Image(systemName: "doc.on.doc").font(.subheadline)
                    }.foregroundColor(.secondary)
                }
            }

            ScrollView {
                Text(viewModel.currentDescription.isEmpty
                     ? "Tap Ask to describe the camera, or turn on Live for automatic updates."
                     : viewModel.currentDescription)
                    .font(.system(.body, design: .default))
                    .fontWeight(.regular)
                    .foregroundColor(viewModel.currentDescription.isEmpty ? .secondary : .primary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)

            if let error = viewModel.error {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(AppColors.statusRed)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        #if os(iOS)
        .background(Color(.systemBackground))
        #elseif os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
    }

    private var controlBar: some View {
        HStack(spacing: 42) {
            // Main action button - tap for single, or shows streaming state
            VStack(spacing: 6) {
                Button {
                    if viewModel.isAutoStreamingEnabled {
                        viewModel.isAutoStreamingEnabled = false
                    } else {
                        Task { await viewModel.describeCurrentFrame() }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(buttonColor)
                            .frame(width: 64, height: 64)
                        if viewModel.isProcessing {
                            ProgressView().tint(.white)
                        } else if viewModel.isAutoStreamingEnabled {
                            Image(systemName: "stop.fill").font(.title2).foregroundColor(.white)
                        } else {
                            Image(systemName: "sparkles").font(.title).foregroundColor(.white)
                        }
                    }
                }
                .disabled(viewModel.isProcessing && !viewModel.isAutoStreamingEnabled)

                Text(viewModel.isAutoStreamingEnabled ? "Stop" : "Ask")
                    .font(.caption2)
                    .foregroundColor(.white)
            }

            // Auto-stream toggle
            Button { viewModel.toggleAutoStreaming() } label: {
                VStack(spacing: 4) {
                    Image(systemName: viewModel.isAutoStreamingEnabled ? "livephoto" : "livephoto.slash")
                        .font(.title2)
                        .symbolEffect(.pulse, isActive: viewModel.isAutoStreamingEnabled)
                    Text("Live").font(.caption2)
                }
                .foregroundColor(viewModel.isAutoStreamingEnabled ? AppColors.statusGreen : .white)
            }

            // Model button
            Button { showingModelSelection = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "cube").font(.title2)
                    Text("Model").font(.caption2)
                }
                .foregroundColor(.white)
            }
        }
        .padding(.vertical, 16)
        .background(Color.black)
    }

    // MARK: - Model Required

    private var modelRequiredContent: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "camera.viewfinder").font(AppTypography.system60).foregroundColor(AppColors.primaryAccent)
            Text("Live Mode").font(.title).fontWeight(.bold).foregroundColor(.white)
            Text("Choose a vision model to understand the camera").foregroundColor(AppColors.statusGray)
            Button { showingModelSelection = true } label: {
                HStack { Image(systemName: "sparkles"); Text("Choose Vision Model") }
                    .font(.headline).frame(width: 200).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent).tint(AppColors.primaryAccent)
            Spacer()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .navigationBarTrailing) {
            if let name = viewModel.loadedModelName {
                Text(name).font(.caption).foregroundColor(AppColors.statusGray)
            }
        }
        #else
        ToolbarItem(placement: .automatic) {
            if let name = viewModel.loadedModelName {
                Text(name).font(.caption).foregroundColor(AppColors.statusGray)
            }
        }
        #endif
    }

    // MARK: - Helpers

    private var buttonColor: Color {
        if viewModel.isAutoStreamingEnabled {
            return AppColors.statusRed
        } else if viewModel.isProcessing {
            return AppColors.statusGray
        } else {
            return AppColors.primaryAccent
        }
    }

    private func setupCameraIfNeeded() {
        // Don't run the camera until a vision model is loaded. Otherwise the
        // capture session (and the iOS camera privacy indicator) runs with no
        // visible preview and nothing to feed it, and the permission prompt
        // fires before the user has chosen a model.
        guard viewModel.isModelLoaded else { return }
        Task {
            await viewModel.checkCameraAuthorization()
            if viewModel.isCameraAuthorized {
                if viewModel.captureSession == nil {
                    viewModel.setupCamera()
                }
                viewModel.startCamera()
            }
        }
    }

}

// MARK: - Camera Preview

#if os(iOS)
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        // PreviewView handles its own layout via layoutSubviews
    }

    // Custom UIView that properly sizes AVCaptureVideoPreviewLayer
    class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer // swiftlint:disable:this force_cast
        }
    }
}
#elseif os(macOS)
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = previewLayer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif
