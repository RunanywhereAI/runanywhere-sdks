//
//  VLMCameraView.swift
//  RunAnywhereAI
//
//  Simple camera view for Vision Language Model
//

import SwiftUI
import AVFoundation
import RunAnywhere
import PhotosUI

// MARK: - VLM Camera View

struct VLMCameraView: View {
    @State private var viewModel = VLMViewModel()
    @State private var showingModelSelection = false
    @State private var showingPhotos = false
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isModelLoaded {
                mainContent
            } else {
                modelRequiredContent
            }
        }
        .navigationTitle("Vision AI")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
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
        .photosPicker(isPresented: $showingPhotos, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, item in
            Task { await handlePhoto(item) }
        }
        .onAppear { setupCameraIfNeeded() }
        .onDisappear {
            viewModel.stopAutoStreaming()
            viewModel.stopCamera()
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
                            Text("Analyzing...").font(.caption).foregroundColor(.white)
                        }
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
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
            Image(systemName: "camera.fill").font(.largeTitle).foregroundColor(.gray)
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
                    Text("Description")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    if viewModel.isAutoStreamingEnabled {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("LIVE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
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
                     ? "Tap the button to describe what your camera sees"
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
                    .foregroundColor(.red)
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
        HStack(spacing: 32) {
            // Photos button
            Button { showingPhotos = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "photo").font(.title2)
                    Text("Photos").font(.caption2)
                }
                .foregroundColor(.white)
            }

            // Main action button - tap for single, or shows streaming state
            Button {
                if viewModel.isAutoStreamingEnabled {
                    viewModel.stopAutoStreaming()
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

            // Auto-stream toggle
            Button { viewModel.toggleAutoStreaming() } label: {
                VStack(spacing: 4) {
                    Image(systemName: viewModel.isAutoStreamingEnabled ? "livephoto" : "livephoto.slash")
                        .font(.title2)
                        .symbolEffect(.pulse, isActive: viewModel.isAutoStreamingEnabled)
                    Text("Live").font(.caption2)
                }
                .foregroundColor(viewModel.isAutoStreamingEnabled ? .green : .white)
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
            Image(systemName: "camera.viewfinder").font(.system(size: 60)).foregroundColor(.orange)
            Text("Vision AI").font(.title).fontWeight(.bold).foregroundColor(.white)
            Text("Select a vision model to describe images").foregroundColor(.gray)
            Button { showingModelSelection = true } label: {
                HStack { Image(systemName: "sparkles"); Text("Select Model") }
                    .font(.headline).frame(width: 200).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent).tint(.orange)
            Spacer()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .navigationBarTrailing) {
            if let name = viewModel.loadedModelName {
                Text(name).font(.caption).foregroundColor(.gray)
            }
        }
        #else
        ToolbarItem(placement: .automatic) {
            if let name = viewModel.loadedModelName {
                Text(name).font(.caption).foregroundColor(.gray)
            }
        }
        #endif
    }

    // MARK: - Helpers

    private var buttonColor: Color {
        if viewModel.isAutoStreamingEnabled {
            return .red
        } else if viewModel.isProcessing {
            return .gray
        } else {
            return .orange
        }
    }

    private func setupCameraIfNeeded() {
        Task {
            await viewModel.checkCameraAuthorization()
            if viewModel.isCameraAuthorized && viewModel.captureSession == nil {
                viewModel.setupCamera()
                viewModel.startCamera()
            }
        }
    }

    private func handlePhoto(_ item: PhotosPickerItem?) async {
        guard let item = item,
              let data = try? await item.loadTransferable(type: Data.self) else { return }
        #if os(iOS)
        guard let image = UIImage(data: data) else { return }
        #elseif os(macOS)
        guard let image = NSImage(data: data) else { return }
        #endif
        await viewModel.describeImage(image)
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
