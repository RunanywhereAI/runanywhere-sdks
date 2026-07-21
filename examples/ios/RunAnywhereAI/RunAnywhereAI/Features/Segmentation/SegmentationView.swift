//
//  SegmentationView.swift
//  RunAnywhereAI
//
//  UI for semantic image segmentation (SegFormer) over `RunAnywhere.segment`.
//  Pure SwiftUI: EULA gate, model supply, image picker, and mask rendering —
//  no inference or model logic lives here.
//

#if canImport(UIKit)
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct SegmentationView: View {
    @State private var viewModel = SegmentationViewModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var showingModelImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
                licenseCard
                modelCard
                imageCard
                if !viewModel.classSummaries.isEmpty {
                    resultCard
                }
                if let error = viewModel.error {
                    errorBanner(error)
                }
                if !viewModel.statusMessage.isEmpty {
                    Text(viewModel.statusMessage)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .padding(AppSpacing.mediumLarge)
        }
        .navigationTitle("Segmentation")
        #if os(iOS)
        .navigationBarTitleDisplayModeCompat(.inline)
        #endif
        .task { viewModel.refreshModelStatus() }
        .onChange(of: photoItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    viewModel.setImage(image)
                }
            }
        }
        .fileImporter(
            isPresented: $showingModelImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { await viewModel.importAndLoadModel(from: url) }
                }
            case .failure(let failure):
                viewModel.reportError("Could not open the model: \(failure.localizedDescription)")
            }
        }
    }

    // MARK: - License

    private var licenseCard: some View {
        card {
            Text("Model license")
                .font(AppTypography.subheadlineMedium)
                .foregroundColor(AppColors.textPrimary)
            Text("SegFormer segmentation weights are released for noncommercial research / evaluation only. The SDK will not load them until you accept the pinned upstream terms. Acceptance applies to this app session and does not download any model.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
            Link("SegFormer LICENSE",
                 destination: URL(string: "https://github.com/NVlabs/SegFormer/blob/65fa8cfa9b52b6ee7e8897a98705abf8570f9e32/LICENSE")!)
                .font(AppTypography.caption)
            Toggle(isOn: Binding(
                get: { viewModel.licenseAccepted },
                set: { if $0 { viewModel.acceptLicense() } }
            )) {
                Text("I have read and accept the NVIDIA SegFormer noncommercial license.")
                    .font(AppTypography.caption)
            }
            .disabled(viewModel.licenseAccepted)
        }
    }

    // MARK: - Model

    private var modelCard: some View {
        card {
            HStack {
                Text("Model")
                    .font(AppTypography.subheadlineMedium)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                statusPill(ok: viewModel.isModelLoaded,
                           text: viewModel.isModelLoaded ? "loaded" : "not loaded")
            }
            Text("SegFormer weights are user-supplied and uncataloged. Pick the model folder (model.onnx + config.json + preprocessor_config.json + runanywhere-segmentation.json); the SDK imports and loads it under the semantic-segmentation category.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
            Button {
                showingModelImporter = true
            } label: {
                if viewModel.isImportingModel {
                    ProgressView()
                } else {
                    Text(viewModel.isModelLoaded ? "Change model folder…" : "Choose model folder…")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.licenseAccepted || viewModel.isImportingModel)
        }
    }

    // MARK: - Image

    private var imageCard: some View {
        card {
            Text("Image")
                .font(AppTypography.subheadlineMedium)
                .foregroundColor(AppColors.textPrimary)
            imagePreview
            PhotosPicker(selection: $photoItem, matching: .images) {
                Text(viewModel.sourceImage == nil ? "Pick image…" : "Change image…")
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.licenseAccepted)

            Button {
                Task { await viewModel.runSegmentation() }
            } label: {
                if viewModel.isSegmenting {
                    ProgressView()
                } else {
                    Text("Run segmentation")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.licenseAccepted
                      || !viewModel.isModelLoaded
                      || viewModel.sourceImage == nil
                      || viewModel.isSegmenting)
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let sourceImage = viewModel.sourceImage {
            ZStack {
                Image(uiImage: sourceImage)
                    .resizable()
                    .scaledToFit()
                if let mask = viewModel.maskImage {
                    Image(uiImage: mask)
                        .resizable()
                        .scaledToFit()
                        .opacity(0.55)
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular))
        } else {
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular)
                .fill(Color(.tertiarySystemFill))
                .frame(height: 160)
                .overlay(
                    Text("No image selected")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                )
        }
    }

    // MARK: - Result

    private var resultCard: some View {
        card {
            HStack {
                Text("Classes")
                    .font(AppTypography.subheadlineMedium)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                if viewModel.processingTimeMs > 0 {
                    Text("\(viewModel.processingTimeMs) ms")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            ForEach(viewModel.classSummaries, id: \.classID) { summary in
                HStack {
                    Text(summary.label.isEmpty ? "class \(summary.classID)" : summary.label)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()
                    Text("\(summary.pixelCount) px · \(String(format: "%.1f", summary.fraction * 100))%")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    // MARK: - Building blocks

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(AppTypography.caption)
            .foregroundColor(AppColors.statusRed)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.small)
            .background(AppColors.statusRed.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular))
    }

    private func statusPill(ok: Bool, text: String) -> some View {
        Text(text)
            .font(AppTypography.caption)
            .foregroundColor(ok ? AppColors.statusGreen : AppColors.statusGray)
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, 2)
            .background((ok ? AppColors.statusGreen : AppColors.statusGray).opacity(0.12),
                        in: Capsule())
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.mediumLarge)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular))
    }
}
#endif
