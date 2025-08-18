//
//  StorageView.swift
//  RunAnywhereAI
//
//  Simplified storage view using SDK methods
//

import SwiftUI
import RunAnywhereSDK

struct StorageView: View {
    @StateObject private var viewModel = StorageViewModel()

    var body: some View {
        NavigationView {
            List {
                storageOverviewSection
                storedModelsSection
                cacheManagementSection
            }
            .navigationTitle("Storage")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        Task {
                            await viewModel.refreshData()
                        }
                    }
                }
                #else
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") {
                        Task {
                            await viewModel.refreshData()
                        }
                    }
                }
                #endif
            }
            .task {
                await viewModel.loadData()
            }
        }
    }

    private var storageOverviewSection: some View {
        Section("Storage Overview") {
            VStack(alignment: .leading, spacing: 12) {
                // Total storage usage
                HStack {
                    Label("Total Usage", systemImage: "externaldrive")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: viewModel.totalStorageSize, countStyle: .file))
                        .foregroundColor(.secondary)
                }

                // Available space
                HStack {
                    Label("Available Space", systemImage: "externaldrive.badge.plus")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: viewModel.availableSpace, countStyle: .file))
                        .foregroundColor(.green)
                }

                // Models storage
                HStack {
                    Label("Models Storage", systemImage: "cpu")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: viewModel.modelStorageSize, countStyle: .file))
                        .foregroundColor(.blue)
                }

                // Models count
                HStack {
                    Label("Downloaded Models", systemImage: "number")
                    Spacer()
                    Text("\(viewModel.storedModels.count)")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var storedModelsSection: some View {
        Section("Downloaded Models") {
            if viewModel.storedModels.isEmpty {
                Text("No models downloaded yet")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ForEach(viewModel.storedModels, id: \.id) { model in
                    StoredModelRow(model: model) {
                        await viewModel.deleteModel(model.id)
                    }
                }
            }
        }
    }

    private var cacheManagementSection: some View {
        Section("Storage Management") {
            Button(action: {
                Task {
                    await viewModel.clearCache()
                }
            }) {
                HStack {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                    Text("Clear Cache")
                        .foregroundColor(.red)
                    Spacer()
                }
            }

            Button(action: {
                Task {
                    await viewModel.cleanTempFiles()
                }
            }) {
                HStack {
                    Image(systemName: "trash")
                        .foregroundColor(.orange)
                    Text("Clean Temporary Files")
                        .foregroundColor(.orange)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Supporting Views

private struct StoredModelRow: View {
    let model: StoredModel
    let onDelete: () async -> Void
    @State private var showingDetails = false
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        Text(model.format.rawValue.uppercased())
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)

                        if let framework = model.framework {
                            Text(framework.displayName)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(ByteCountFormatter.string(fromByteCount: model.size, countStyle: .file))
                        .font(.caption)
                        .fontWeight(.medium)

                    HStack(spacing: 4) {
                        Button(showingDetails ? "Hide" : "Details") {
                            withAnimation {
                                showingDetails.toggle()
                            }
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(isDeleting)
                    }
                }
            }

            if showingDetails {
                VStack(alignment: .leading, spacing: 6) {
                    // Model Format and Framework
                    HStack {
                        Text("Format:")
                            .font(.caption2)
                            .fontWeight(.medium)
                        Text(model.format.rawValue.uppercased())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let framework = model.framework {
                        HStack {
                            Text("Framework:")
                                .font(.caption2)
                                .fontWeight(.medium)
                            Text(framework.displayName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Context Length
                    if let contextLength = model.contextLength {
                        HStack {
                            Text("Context Length:")
                                .font(.caption2)
                                .fontWeight(.medium)
                            Text("\(contextLength) tokens")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Metadata
                    if let metadata = model.metadata {
                        if let author = metadata.author {
                            HStack {
                                Text("Author:")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                Text(author)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let license = metadata.license {
                            HStack {
                                Text("License:")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                Text(license)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let description = metadata.description {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Description:")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                Text(description)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if !metadata.tags.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Tags:")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                HStack(spacing: 4) {
                                    ForEach(metadata.tags, id: \.self) { tag in
                                        Text(tag)
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.2))
                                            .cornerRadius(4)
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    // File Information
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Path:")
                            .font(.caption2)
                            .fontWeight(.medium)
                        Text(model.path.path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let checksum = model.checksum {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Checksum:")
                                .font(.caption2)
                                .fontWeight(.medium)
                            Text(checksum)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    HStack {
                        Text("Created:")
                            .font(.caption2)
                            .fontWeight(.medium)
                        Text(model.createdDate, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let lastUsed = model.lastUsed {
                        HStack {
                            Text("Last used:")
                                .font(.caption2)
                                .fontWeight(.medium)
                            Text(lastUsed, style: .relative)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
        .alert("Delete Model", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    isDeleting = true
                    await onDelete()
                    isDeleting = false
                }
            }
        } message: {
            Text("Are you sure you want to delete \(model.name)? This action cannot be undone.")
        }
    }
}

#Preview {
    StorageView()
}
