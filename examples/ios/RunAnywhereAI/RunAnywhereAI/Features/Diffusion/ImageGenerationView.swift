import SwiftUI
import RunAnywhere

// MARK: - Image Generation View

/// Simple view for text-to-image generation using Diffusion models
struct ImageGenerationView: View {
    @StateObject private var viewModel = DiffusionViewModel()
    @State private var showModelPicker = false

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: AppSpacing.large) {
                        // Model status
                        modelStatusSection

                        // Generated Image Display
                        imageDisplaySection(geometry: geometry)

                        // Prompt Input
                        promptInputSection

                        // Quick Prompts
                        quickPromptsSection

                        // Generate Button
                        generateButtonSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Image Generation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .task {
            await viewModel.initialize()
        }
        .sheet(isPresented: $showModelPicker) {
            DiffusionModelPickerView(viewModel: viewModel, isPresented: $showModelPicker)
        }
    }

    // MARK: - Model Status

    private var modelStatusSection: some View {
        HStack {
            Circle()
                .fill(viewModel.isModelLoaded ? Color.green : Color.orange)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isModelLoaded ? (viewModel.currentModelName ?? "Model loaded") : "No model loaded")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if viewModel.isModelLoaded && !viewModel.currentBackend.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: backendIcon)
                            .font(.caption2)
                        Text(viewModel.currentBackend)
                            .font(.caption2)
                    }
                    .foregroundColor(backendColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(backendColor.opacity(0.15))
                    .cornerRadius(4)
                }
            }

            Spacer()

            Button(viewModel.isModelLoaded ? "Change" : "Load Model") { showModelPicker = true }
                .buttonStyle(.bordered)
                .tint(AppColors.primaryAccent)
        }
        .padding()
        .background(AppColors.backgroundSecondary)
        .cornerRadius(AppSpacing.cornerRadiusLarge)
    }

    private var backendIcon: String {
        if viewModel.currentBackend.contains("CoreML") {
            return "apple.logo"
        } else if viewModel.currentBackend.contains("ONNX") {
            return "cpu"
        }
        return "gearshape"
    }

    private var backendColor: Color {
        if viewModel.currentBackend.contains("CoreML") {
            return .blue
        } else if viewModel.currentBackend.contains("ONNX") {
            return .purple
        }
        return .secondary
    }

    // MARK: - Image Display

    private func imageDisplaySection(geometry: GeometryProxy) -> some View {
        let imageSize = min(geometry.size.width - 32, 400.0)

        return ZStack {
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge)
                .fill(AppColors.backgroundSecondary)
                .frame(width: imageSize, height: imageSize)

            if let image = viewModel.generatedImage {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageSize, height: imageSize)
                    .cornerRadius(AppSpacing.cornerRadiusLarge)
            } else if viewModel.isGenerating {
                VStack(spacing: AppSpacing.medium) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text(viewModel.statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    ProgressView(value: viewModel.progress)
                        .frame(width: 150)
                }
            } else {
                VStack(spacing: AppSpacing.small) {
                    Image(systemName: "photo.artframe")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    Text("Enter a prompt to generate")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Prompt Input

    private var promptInputSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Prompt")
                .font(.headline)

            TextEditor(text: $viewModel.prompt)
                .frame(minHeight: 80)
                .padding(8)
                .background(AppColors.backgroundSecondary)
                .cornerRadius(AppSpacing.cornerRadiusLarge)
                .overlay(
                    RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }

    // MARK: - Quick Prompts

    private var quickPromptsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.small) {
                ForEach(DiffusionViewModel.samplePrompts, id: \.self) { prompt in
                    Button {
                        viewModel.prompt = prompt
                    } label: {
                        Text(prompt.prefix(25) + "...")
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppColors.backgroundSecondary)
                            .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Generate Button

    private var generateButtonSection: some View {
        VStack(spacing: AppSpacing.small) {
            if viewModel.isGenerating {
                Button {
                    Task { await viewModel.cancelGeneration() }
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Cancel")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Button {
                    Task { await viewModel.generateImage() }
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Generate")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.primaryAccent)
                .disabled(!viewModel.canGenerate)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Model Picker

struct DiffusionModelPickerView: View {
    @ObservedObject var viewModel: DiffusionViewModel
    @Binding var isPresented: Bool

    private static let firstLoadBannerText = "First load may take 1–2 minutes depending on model size and device performance."

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // First-load info banner
                HStack(spacing: AppSpacing.small) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.body)
                        .foregroundStyle(AppColors.primaryAccent)
                    Text(Self.firstLoadBannerText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(AppColors.backgroundSecondary)

                if viewModel.availableModels.isEmpty {
                    VStack(spacing: AppSpacing.large) {
                        Image(systemName: "photo.artframe")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No Diffusion Models")
                            .font(.headline)
                        Text("No image generation models are registered.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(viewModel.availableModels, id: \.id) { model in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.name).font(.headline)
                                    Text(model.framework.displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if model.isDownloaded {
                                    if viewModel.isLoadingModel && viewModel.selectedModel?.id == model.id {
                                        HStack(spacing: AppSpacing.small) {
                                            ProgressView()
                                            Text("Loading...")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    } else {
                                        Button("Load") {
                                            viewModel.selectedModel = model
                                            Task {
                                                await viewModel.loadSelectedModel()
                                                if viewModel.isModelLoaded { isPresented = false }
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(viewModel.isDownloading)
                                    }
                                } else {
                                    Button("Download") {
                                        viewModel.selectedModel = model
                                        Task { await viewModel.downloadModel(model) }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(viewModel.isDownloading)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if viewModel.isDownloading {
                    VStack(spacing: AppSpacing.small) {
                        ProgressView(value: viewModel.downloadProgress)
                        Text(viewModel.downloadStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(AppColors.backgroundSecondary)
                }
            }
            .navigationTitle("Diffusion Models")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}

#Preview {
    ImageGenerationView()
}
