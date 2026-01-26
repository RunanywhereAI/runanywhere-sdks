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
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.isModelLoaded {
                    mainContent
                } else {
                    modelRequiredContent
                }
            }
            .navigationTitle("Vision AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .sheet(isPresented: $showingModelSelection) {
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
        .onDisappear { viewModel.stopCamera() }
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
        GeometryReader { geo in
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
        .frame(height: UIScreen.main.bounds.height * 0.45)
    }

    private var cameraPermissionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill").font(.largeTitle).foregroundColor(.gray)
            Text("Camera Access Required").font(.headline).foregroundColor(.white)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var descriptionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Description").font(.headline).foregroundColor(.white)
                Spacer()
                if !viewModel.currentDescription.isEmpty {
                    Button { UIPasteboard.general.string = viewModel.currentDescription } label: {
                        Image(systemName: "doc.on.doc").font(.caption)
                    }.foregroundColor(.gray)
                }
            }

            ScrollView {
                Text(viewModel.currentDescription.isEmpty ? "Tap the button to describe what your camera sees" : viewModel.currentDescription)
                    .font(.body)
                    .foregroundColor(viewModel.currentDescription.isEmpty ? .gray : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)

            if let error = viewModel.error {
                Text(error.localizedDescription).font(.caption).foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.95))
    }

    private var controlBar: some View {
        HStack(spacing: 50) {
            // Photos button
            Button { showingPhotos = true } label: {
                Image(systemName: "photo").font(.title2).foregroundColor(.white)
            }

            // Describe button
            Button { Task { await viewModel.describeCurrentFrame() } } label: {
                ZStack {
                    Circle().fill(viewModel.isProcessing ? Color.gray : Color.orange).frame(width: 64, height: 64)
                    if viewModel.isProcessing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "sparkles").font(.title).foregroundColor(.white)
                    }
                }
            }
            .disabled(viewModel.isProcessing)

            // Model button
            Button { showingModelSelection = true } label: {
                Image(systemName: "cube").font(.title2).foregroundColor(.white)
            }
        }
        .padding(.vertical, 20)
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
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Close") { dismiss() }.foregroundColor(.white)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            if let name = viewModel.loadedModelName {
                Text(name).font(.caption).foregroundColor(.gray)
            }
        }
    }

    // MARK: - Helpers

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
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        await viewModel.describeImage(image)
    }
}

// MARK: - Camera Preview

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        context.coordinator.layer = layer
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.layer?.frame = view.bounds
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    class Coordinator { var layer: AVCaptureVideoPreviewLayer? }
}
