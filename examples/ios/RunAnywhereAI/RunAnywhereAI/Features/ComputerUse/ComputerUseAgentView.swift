//
//  ComputerUseAgentView.swift
//  RunAnywhereAI
//
//  Computer-Use Agent demo. Pick a screenshot, describe a goal, and run one
//  agent step: the SDK renders the CUA system prompt, the VLM reasons over the
//  image, and `RunAnywhere.CUA.parseAction` returns a viewport-scaled action
//  that we draw straight onto the screenshot.
//
//  Pure SwiftUI — every model/prompt/coordinate concern lives in the SDK.
//

import PhotosUI
import RunAnywhere
import SwiftUI
import UniformTypeIdentifiers

struct ComputerUseAgentView: View {
    @State private var viewModel = ComputerUseAgentViewModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var showModelPicker = false
    @State private var showFileImporter = false

    var body: some View {
        ZStack {
            if viewModel.isCuaCapable {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
                        screenshotCard
                        taskCard
                        if viewModel.isRunning || !viewModel.rawOutput.isEmpty {
                            resultCard
                        }
                        if let error = viewModel.error {
                            Text(error)
                                .font(AppTypography.caption)
                                .foregroundColor(.red)
                        }
                        if !viewModel.statusMessage.isEmpty {
                            Text(viewModel.statusMessage)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                    .padding(AppSpacing.mediumLarge)
                }
            } else {
                VStack(spacing: AppSpacing.small) {
                    ModelRequiredOverlay(modality: .vlm) { showModelPicker = true }
                    // A multimodal model can be loaded and still not be a
                    // computer-use agent — say so rather than silently driving it.
                    if viewModel.isModelLoaded, !viewModel.statusMessage.isEmpty {
                        Text(viewModel.statusMessage)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.mediumLarge)
                    }
                }
            }
        }
        .navigationTitle("Computer Use")
        #if os(iOS)
        .navigationBarTitleDisplayModeCompat(.inline)
        #endif
        .toolbar {
            if viewModel.isModelLoaded {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showModelPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "cube")
                            Text(viewModel.loadedModelName ?? "Model").lineLimit(1)
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .adaptiveSheet(isPresented: $showModelPicker) {
            ModelSelectionSheet(context: .vlm) { model in
                Task { await viewModel.loadModelFromSelection(model) }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image]
        ) { result in
            guard case .success(let url) = result else { return }
            // Sandboxed app: the picked URL is only readable inside a
            // security-scoped session.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let image = AgentImage(data: data) {
                viewModel.screenshot = image
                viewModel.clearResult()
            }
        }
        .task { viewModel.refreshModelStatus() }
        .onChange(of: photoItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = AgentImage(data: data) {
                    viewModel.screenshot = image
                    viewModel.clearResult()
                }
            }
        }
    }

    // MARK: - Screenshot + action overlay

    private var screenshotCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Screenshot")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.textPrimary)

            if let screenshot = viewModel.screenshot {
                GeometryReader { geo in
                    let size = ComputerUseAgentViewModel.pixelSize(of: screenshot)
                    let fitted = fittedRect(
                        imageWidth: CGFloat(size.width),
                        imageHeight: CGFloat(size.height),
                        in: geo.size
                    )

                    ZStack(alignment: .topLeading) {
                        agentImageView(screenshot)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)

                        // The SDK already scaled the coordinate into the
                        // screenshot's pixel space — map it onto the drawn rect.
                        if let action = viewModel.action,
                           action.isValid,
                           let point = action.coordinate,
                           size.width > 0, size.height > 0 {
                            let x = fitted.minX + fitted.width * CGFloat(point.x) / CGFloat(size.width)
                            let y = fitted.minY + fitted.height * CGFloat(point.y) / CGFloat(size.height)
                            targetMarker
                                .position(x: x, y: y)
                        }
                    }
                }
                .frame(height: 320)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.12))
                    .frame(height: 160)
                    .overlay(
                        Text("Pick a screenshot to get started")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                    )
            }

            // Screenshots live on disk on the Mac (Desktop / a capture folder),
            // not in the Photos library — so PhotosPicker is the wrong
            // affordance there and makes the screen unusable. Use the file
            // importer on macOS and keep PhotosPicker on iOS.
            #if os(macOS)
            Button {
                showFileImporter = true
            } label: {
                Label(pickerTitle, systemImage: "photo")
                    .font(.callout)
            }
            #else
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(pickerTitle, systemImage: "photo")
                    .font(.callout)
            }
            #endif
        }
    }

    private var pickerTitle: String {
        viewModel.screenshot == nil ? "Choose Screenshot" : "Change Screenshot"
    }

    private var targetMarker: some View {
        ZStack {
            Circle()
                .strokeBorder(AppColors.primaryAccent, lineWidth: 3)
                .frame(width: 34, height: 34)
            Circle()
                .fill(AppColors.primaryAccent)
                .frame(width: 6, height: 6)
        }
        .shadow(radius: 2)
    }

    // MARK: - Task + run

    private var taskCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Goal")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.textPrimary)

            TextField("What should the agent do?", text: $viewModel.task, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)

            HStack {
                Button {
                    Task { await viewModel.runStep() }
                } label: {
                    Label("Run Agent Step", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.screenshot == nil || viewModel.isRunning)

                if viewModel.isRunning {
                    Button("Cancel") { viewModel.cancel() }
                        .buttonStyle(.bordered)
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    // MARK: - Result

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Parsed Action")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.textPrimary)

            if let action = viewModel.action, action.isValid {
                VStack(alignment: .leading, spacing: 4) {
                    row("Action", String(describing: action.kind))
                    if let point = action.coordinate {
                        row("Coordinate", "(\(point.x), \(point.y)) px")
                    }
                    if !action.text.isEmpty { row("Text", action.text) }
                    if action.scrollPixels != 0 { row("Scroll", "\(action.scrollPixels)") }
                    if action.waitSeconds != 0 { row("Wait", "\(action.waitSeconds)s") }
                    if !action.reasoning.isEmpty {
                        Text(action.reasoning)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                            .padding(.top, 4)
                    }
                }
            } else if !viewModel.isRunning {
                Text("No valid tool call parsed from the model's reply.")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            DisclosureGroup("Raw model output") {
                Text(viewModel.rawOutput.isEmpty ? "…" : viewModel.rawOutput)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .font(AppTypography.caption)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textPrimary)
        }
    }

    // MARK: - Helpers

    /// Rect the image actually occupies inside a `scaledToFit` container, so the
    /// marker lands on the right pixel rather than the container's corner.
    private func fittedRect(imageWidth: CGFloat, imageHeight: CGFloat, in container: CGSize) -> CGRect {
        guard imageWidth > 0, imageHeight > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageWidth, container.height / imageHeight)
        let width = imageWidth * scale
        let height = imageHeight * scale
        return CGRect(
            x: (container.width - width) / 2,
            y: (container.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func agentImageView(_ image: AgentImage) -> Image {
        #if canImport(UIKit)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
        #endif
    }
}
