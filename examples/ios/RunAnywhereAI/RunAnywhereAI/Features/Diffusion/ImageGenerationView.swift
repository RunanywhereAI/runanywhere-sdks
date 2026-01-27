import SwiftUI
import RunAnywhere

// MARK: - Keyboard Dismissal Extension

#if os(iOS)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

// MARK: - Image Generation View

/// Main view for text-to-image generation using Diffusion models
struct ImageGenerationView: View {
    @StateObject private var viewModel = DiffusionViewModel()
    @State private var showSettings = false
    @State private var showModelPicker = false

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: AppSpacing.large) {
                        // Header with model status
                        modelStatusSection

                        // Generated Image Display
                        imageDisplaySection(geometry: geometry)

                        // Prompt Input
                        promptInputSection

                        // Quick Prompts
                        quickPromptsSection

                        // Generate Button
                        generateButtonSection

                        // Settings
                        if showSettings {
                            settingsSection
                        }
                    }
                    .padding()
                }
                .onTapGesture {
                    // Dismiss keyboard when tapping outside text fields
                    hideKeyboard()
                }
            }
            .navigationTitle("Image Generation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { showSettings.toggle() }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
        }
        .task {
            await viewModel.initialize()
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .sheet(isPresented: $showModelPicker) {
            DiffusionModelPickerView(viewModel: viewModel, isPresented: $showModelPicker)
        }
    }

    // MARK: - Model Status Section

    private var modelStatusSection: some View {
        HStack {
            Circle()
                .fill(viewModel.isModelLoaded ? Color.green : Color.orange)
                .frame(width: 10, height: 10)

            if viewModel.isModelLoaded {
                Text(viewModel.currentModelName ?? "Model loaded")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("No model loaded")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !viewModel.isModelLoaded {
                Button("Load Model") {
                    showModelPicker = true
                }
                .buttonStyle(.bordered)
                .tint(AppColors.primaryAccent)
            }
        }
        .padding()
        .background(AppColors.backgroundSecondary)
        .cornerRadius(AppSpacing.cornerRadiusLarge)
    }

    // MARK: - Image Display Section

    private func imageDisplaySection(geometry: GeometryProxy) -> some View {
        let imageSize = min(geometry.size.width - 32, 400.0)

        return VStack(spacing: AppSpacing.medium) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge)
                    .fill(AppColors.backgroundSecondary)
                    .frame(width: imageSize, height: imageSize)

                if let image = viewModel.generatedImage {
                    // Generated Image
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: imageSize, height: imageSize)
                        .cornerRadius(AppSpacing.cornerRadiusLarge)
                } else if viewModel.isGenerating {
                    // Loading state with progress
                    VStack(spacing: AppSpacing.medium) {
                        ProgressView()
                            .scaleEffect(1.5)

                        Text(viewModel.statusMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ProgressView(value: viewModel.progress)
                            .frame(width: 150)

                        Text(viewModel.progressPercentage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // Placeholder
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

            // Seed info
            if let seed = viewModel.lastSeedUsed {
                HStack {
                    Text("Seed: \(seed)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button {
                        viewModel.seed = seed
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Prompt Input Section

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

            if showSettings {
                Text("Negative Prompt")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("Things to avoid...", text: $viewModel.negativePrompt)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Quick Prompts Section

    private var quickPromptsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Quick Prompts")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.small) {
                    ForEach(DiffusionViewModel.samplePrompts, id: \.self) { prompt in
                        Button {
                            viewModel.prompt = prompt
                        } label: {
                            Text(prompt.prefix(30) + "...")
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
    }

    // MARK: - Generate Button Section

    private var generateButtonSection: some View {
        VStack(spacing: AppSpacing.small) {
            HStack(spacing: AppSpacing.medium) {
                if viewModel.isGenerating {
                    Button {
                        Task {
                            await viewModel.cancelGeneration()
                        }
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
                        // Dismiss keyboard before generating
                        hideKeyboard()
                        Task {
                            await viewModel.generateImage()
                        }
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
            }

            // Error message
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Divider()

            Text("Generation Settings")
                .font(.headline)

            // Resolution
            VStack(alignment: .leading, spacing: 4) {
                Text("Resolution")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Resolution", selection: Binding(
                    get: { "\(viewModel.width)x\(viewModel.height)" },
                    set: { newValue in
                        if let res = viewModel.availableResolutions.first(where: { "\($0.width)x\($0.height)" == newValue }) {
                            viewModel.width = res.width
                            viewModel.height = res.height
                        }
                    }
                )) {
                    ForEach(viewModel.availableResolutions, id: \.label) { res in
                        Text(res.label).tag("\(res.width)x\(res.height)")
                    }
                }
                .pickerStyle(.segmented)
            }

            // Steps
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Steps")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(viewModel.steps)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { Double(viewModel.steps) },
                        set: { viewModel.steps = Int($0) }
                    ),
                    in: 10...50,
                    step: 5
                )
            }

            // Guidance Scale
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Guidance Scale")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f", viewModel.guidanceScale))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Slider(
                    value: $viewModel.guidanceScale,
                    in: 1...20,
                    step: 0.5
                )
            }

            // Seed
            HStack {
                Text("Seed")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                TextField("Random", value: $viewModel.seed, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)

                Button {
                    viewModel.seed = -1
                } label: {
                    Image(systemName: "dice")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(AppColors.backgroundSecondary)
        .cornerRadius(AppSpacing.cornerRadiusLarge)
    }
}

// MARK: - Diffusion Model Picker View

struct DiffusionModelPickerView: View {
    @ObservedObject var viewModel: DiffusionViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.availableModels.isEmpty {
                    emptyStateView
                } else {
                    modelListView
                }

                // Download progress section
                if viewModel.isDownloading {
                    downloadProgressView
                }
            }
            .navigationTitle("Diffusion Models")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: AppSpacing.large) {
            Image(systemName: "photo.artframe")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Diffusion Models")
                .font(.headline)

            Text("No image generation models are registered.\nAdd models in the app configuration.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var modelListView: some View {
        List {
            ForEach(viewModel.availableModels, id: \.id) { model in
                DiffusionModelRow(
                    model: model,
                    isSelected: viewModel.selectedModel?.id == model.id,
                    isDownloading: viewModel.isDownloading,
                    onSelect: {
                        viewModel.selectedModel = model
                    },
                    onDownload: {
                        Task {
                            await viewModel.downloadModel(model)
                        }
                    },
                    onLoad: {
                        Task {
                            await viewModel.loadSelectedModel()
                            if viewModel.isModelLoaded {
                                isPresented = false
                            }
                        }
                    }
                )
            }
        }
    }

    private var downloadProgressView: some View {
        VStack(spacing: AppSpacing.small) {
            ProgressView(value: viewModel.downloadProgress)
                .progressViewStyle(.linear)

            Text(viewModel.downloadStatus)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(AppColors.backgroundSecondary)
    }
}

// MARK: - Diffusion Model Row

struct DiffusionModelRow: View {
    let model: ModelInfo
    let isSelected: Bool
    let isDownloading: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onLoad: () -> Void

    var body: some View {
        HStack {
            // Selection indicator
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? AppColors.primaryAccent : .secondary)
                .onTapGesture { onSelect() }

            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.headline)

                HStack {
                    Text(model.framework.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let size = model.downloadSize {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(formatSize(size))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Action button
            if model.isDownloaded {
                Button("Load") {
                    onSelect()
                    onLoad()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.primaryAccent)
                .disabled(isDownloading)
            } else {
                Button("Download") {
                    onSelect()
                    onDownload()
                }
                .buttonStyle(.bordered)
                .tint(AppColors.primaryBlue)
                .disabled(isDownloading)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Preview

#Preview {
    ImageGenerationView()
}
