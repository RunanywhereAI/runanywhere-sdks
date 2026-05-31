//
//  ChatLoRASheets.swift
//  RunAnywhereAI
//
//  LoRA adapter file-picker, scale sheet, and management sheet.
//

import SwiftUI
import RunAnywhere

// MARK: - LoRA Scale Sheet

struct LoRAScaleSheetView: View {
    let url: URL?
    @Binding var scale: Float
    let isLoading: Bool
    let onLoad: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32))
                        .foregroundColor(.purple)

                    Text(url?.lastPathComponent ?? "LoRA Adapter")
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 8) {
                    Text("Scale: \(String(format: "%.1f", scale))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Slider(value: $scale, in: 0...2, step: 0.1)
                        .tint(.purple)

                    HStack {
                        Text("0.0")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("1.0")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("2.0")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                HStack(spacing: 16) {
                    Button("Cancel") { onCancel() }
                        .buttonStyle(.bordered)

                    Button {
                        onLoad()
                    } label: {
                        if isLoading {
                            ProgressView()
                                .frame(width: 60)
                        } else {
                            Text("Load")
                                .frame(width: 60)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(isLoading)
                }
            }
            .padding()
            .navigationTitle("Load LoRA Adapter")
            .navigationBarTitleDisplayModeCompat(.inline)
        }
    }
}

// MARK: - LoRA Management Sheet

struct LoRAManagementSheetView: View {
    @Bindable var viewModel: LLMViewModel
    let onOpenFilePicker: () -> Void
    let onDismiss: () -> Void

    @State private var selectedAdapterScale: [String: Float] = [:]

    var body: some View {
        NavigationView {
            List {
                availableAdaptersSection
                loadedAdaptersSection
                customAdapterSection
            }
            .navigationTitle("LoRA Adapters")
            .navigationBarTitleDisplayModeCompat(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }

    // MARK: - Available Adapters (from SDK Registry)

    @ViewBuilder private var availableAdaptersSection: some View {
        if !viewModel.availableAdapters.isEmpty {
            Section {
                ForEach(viewModel.availableAdapters, id: \.id) { adapter in
                    availableAdapterRow(adapter)
                }
            } header: {
                Text("Available for This Model")
            } footer: {
                Text("Downloaded adapters are stored locally.")
            }
        }
    }

    private func availableAdapterRow(_ adapter: RALoraAdapterCatalogEntry) -> some View {
        let isDownloaded = viewModel.isAdapterDownloaded(adapter)
        let scale = selectedAdapterScale[adapter.id] ?? adapter.defaultScale
        let isAlreadyApplied = viewModel.loraAdapters.contains {
            $0.adapterPath == viewModel.localPath(for: adapter)
        }
        let fileSizeText = ByteCountFormatter.string(fromByteCount: adapter.sizeBytes, countStyle: .file)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(adapter.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(adapter.description_p)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(fileSizeText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isAlreadyApplied {
                    Label("Applied", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if isDownloaded {
                    Label("Downloaded", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            if !isAlreadyApplied {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scale: \(String(format: "%.1f", scale))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(
                            value: Binding(
                                get: { selectedAdapterScale[adapter.id] ?? adapter.defaultScale },
                                set: { selectedAdapterScale[adapter.id] = $0 }
                            ),
                            in: 0...2,
                            step: 0.1
                        )
                        .tint(.purple)
                    }

                    Button {
                        let applyScale = selectedAdapterScale[adapter.id] ?? adapter.defaultScale
                        Task {
                            await viewModel.downloadAndLoadAdapter(adapter, scale: applyScale)
                        }
                    } label: {
                        Text(isDownloaded ? "Apply" : "Download")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(minWidth: 60)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(viewModel.isLoadingLoRA)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Loaded Adapters

    @ViewBuilder private var loadedAdaptersSection: some View {
        if !viewModel.loraAdapters.isEmpty {
            Section("Loaded Adapters") {
                ForEach(viewModel.loraAdapters, id: \.adapterPath) { adapter in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(URL(fileURLWithPath: adapter.adapterPath).lastPathComponent)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                HStack(spacing: 8) {
                                    Text("Scale: \(String(format: "%.1f", adapter.scale))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if adapter.applied {
                                        Text("Applied")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }
                            }

                            Spacer()

                            Button {
                                Task { await viewModel.removeLoraAdapter(path: adapter.adapterPath) }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        let prompts = LoraExamplePrompts.forAdapterPath(adapter.adapterPath)
                        if !prompts.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Try it out:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                ForEach(prompts, id: \.self) { prompt in
                                    Button {
                                        #if os(iOS)
                                        UIPasteboard.general.string = prompt
                                        #else
                                        NSPasteboard.general.setString(prompt, forType: .string)
                                        #endif
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "doc.on.doc")
                                                .font(.caption2)
                                            Text(prompt)
                                                .font(.caption)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.purple.opacity(0.15))
                                        .foregroundColor(.purple)
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                Button(role: .destructive) {
                    Task {
                        await viewModel.clearLoraAdapters()
                    }
                } label: {
                    Label("Clear All Adapters", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Custom File Picker

    private var customAdapterSection: some View {
        Section {
            Button {
                onOpenFilePicker()
            } label: {
                Label("Load from Files...", systemImage: "folder")
            }
        } footer: {
            Text("Select a .gguf LoRA adapter file from your device.")
        }
    }
}
