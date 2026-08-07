//
//  SegmentationView.swift
//  RunAnywhereAI
//
//  UI for semantic image segmentation (SegFormer) over `RunAnywhere.segmentation`.
//  Pure SwiftUI: model picker, image picker, and mask rendering — no inference
//  or model logic lives here.
//

#if canImport(UIKit)
import SwiftUI
import PhotosUI
import UIKit

struct SegmentationView: View {
    @State private var viewModel = SegmentationViewModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var showModelPicker = false

    private var hasModelSelected: Bool {
        viewModel.isModelLoaded
    }

    var body: some View {
        NavigationView {
            ZStack {
                if hasModelSelected {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
                            modelStatusCard
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
                } else {
                    Spacer()
                }

                if !hasModelSelected && !viewModel.isProcessing {
                    ModelRequiredOverlay(modality: .segmentation) {
                        showModelPicker = true
                    }
                }
            }
            .navigationTitle(hasModelSelected ? "Segmentation" : "")
            #if os(iOS)
            .navigationBarTitleDisplayModeCompat(.inline)
            .navigationBarHidden(!hasModelSelected)
            #endif
            .toolbar {
                if hasModelSelected {
                    #if os(iOS)
                    ToolbarItem(placement: .navigationBarTrailing) {
                        modelButton
                    }
                    #else
                    ToolbarItem(placement: .automatic) {
                        modelButton
                    }
                    #endif
                }
            }
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
        .adaptiveSheet(isPresented: $showModelPicker) {
            ModelSelectionSheet(context: .segmentation) { model in
                Task {
                    await viewModel.loadModelFromSelection(model)
                }
            }
        }
        .task { await viewModel.refreshModelStatus() }
        .onChange(of: photoItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    viewModel.setImage(image)
                }
            }
        }
    }

    // MARK: - Model

    private var modelButton: some View {
        Button {
            showModelPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cube")
                    .font(AppTypography.system14)
                if let modelName = viewModel.loadedModelName {
                    Text(modelName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                } else {
                    Text("Select Model")
                        .font(.caption)
                }
            }
        }
    }

    private var modelStatusCard: some View {
        card {
            HStack {
                Text("Model")
                    .font(AppTypography.subheadlineMedium)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                statusPill(ok: viewModel.isModelLoaded, text: "loaded")
            }
            if let name = viewModel.loadedModelName {
                Text(name)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            Text("SegFormer B0 ADE20K (ONNX) — download from the catalog, then Use.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
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
            .disabled(!viewModel.isModelLoaded
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
            ForEach(viewModel.classSummaries, id: \.classId) { summary in
                HStack {
                    Text(summary.label.isEmpty ? "class \(summary.classId)" : summary.label)
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
