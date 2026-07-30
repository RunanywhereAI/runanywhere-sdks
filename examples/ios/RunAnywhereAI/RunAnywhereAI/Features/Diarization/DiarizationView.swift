//
//  DiarizationView.swift
//  RunAnywhereAI
//
//  UI for standalone speaker diarization (NVIDIA Sortformer) over
//  `RunAnywhere.diarization`. Pure SwiftUI: model picker, microphone capture, and a
//  speaker-segment list — no inference or model logic lives here.
//

#if canImport(UIKit)
import SwiftUI

struct DiarizationView: View {
    @State private var viewModel = DiarizationViewModel()
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
                            audioCard
                            if !viewModel.segments.isEmpty {
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
                    ModelRequiredOverlay(modality: .diarization) {
                        showModelPicker = true
                    }
                }
            }
            .navigationTitle(hasModelSelected ? "Diarization" : "")
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
            ModelSelectionSheet(context: .diarization) { model in
                Task {
                    await viewModel.loadModelFromSelection(model)
                }
            }
        }
        .task { viewModel.refreshModelStatus() }
        .onDisappear { viewModel.cleanup() }
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
            Text("NVIDIA Sortformer (ONNX) — ~470 MB catalog download.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Audio

    private var audioCard: some View {
        card {
            Text("Audio")
                .font(AppTypography.subheadlineMedium)
                .foregroundColor(AppColors.textPrimary)
            Text("Record a clip with two or more speakers, then stop to diarize on-device.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
            if viewModel.isRecording {
                levelMeter
            }
            Button {
                Task { await viewModel.toggleRecording() }
            } label: {
                if viewModel.isDiarizing {
                    ProgressView()
                } else {
                    Text(viewModel.isRecording ? "Stop & diarize" : "Record")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isRecording ? AppColors.statusRed : AppColors.primaryAccent)
            .disabled(!viewModel.isModelLoaded || viewModel.isDiarizing)
        }
    }

    private var levelMeter: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(AppColors.statusGreen)
                    .frame(width: geo.size.width * CGFloat(min(max(viewModel.audioLevel, 0), 1)))
            }
        }
        .frame(height: 6)
    }

    // MARK: - Result

    private var resultCard: some View {
        card {
            HStack {
                Text("Speakers · \(viewModel.speakerCount)")
                    .font(AppTypography.subheadlineMedium)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                if viewModel.processingTimeMs > 0 {
                    Text("\(viewModel.processingTimeMs) ms")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            ForEach(Array(viewModel.segments.enumerated()), id: \.offset) { _, segment in
                HStack {
                    speakerChip(index: Int(segment.speakerIndex), id: segment.speakerID)
                    Text("\(format(ms: segment.startMs)) – \(format(ms: segment.endMs))")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textPrimary)
                    Spacer()
                    Text(duration(ms: segment.endMs - segment.startMs))
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    }

    // MARK: - Building blocks

    private func speakerChip(index: Int, id: String) -> some View {
        let color = Self.speakerColors[abs(index) % Self.speakerColors.count]
        return Text(id.isEmpty ? "Speaker \(index + 1)" : id)
            .font(AppTypography.caption)
            .foregroundColor(color)
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

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

    private func format(ms: Int64) -> String {
        let totalSeconds = Double(ms) / 1000.0
        let minutes = Int(totalSeconds) / 60
        let seconds = totalSeconds - Double(minutes * 60)
        return String(format: "%d:%05.2f", minutes, seconds)
    }

    private func duration(ms: Int64) -> String {
        String(format: "%.1fs", Double(ms) / 1000.0)
    }

    private static let speakerColors: [Color] = [
        .blue, .green, .red, .orange, .purple, .teal,
    ]
}
#endif
