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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        Task {
                            await viewModel.refreshData()
                        }
                    }
                }
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
                ForEach(viewModel.storedModels, id: \.name) { model in
                    StoredModelRow(model: model) {
                        await viewModel.deleteModel(model.name)
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
    let model: StoredModelInfo
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
                VStack(alignment: .leading, spacing: 4) {
                    if let filePath = model.filePath {
                        Text("Path: \(filePath)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Text("Created: \(model.createdDate, style: .date)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let lastUsed = model.lastUsed {
                        Text("Last used: \(lastUsed, style: .relative)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
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
