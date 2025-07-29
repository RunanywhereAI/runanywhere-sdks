//
//  DownloadedModelsManagementView.swift
//  RunAnywhereAI
//
//  Created by Assistant on 7/28/25.
//

import SwiftUI

struct DownloadedModelsManagementView: View {
    @StateObject private var storageService = StorageMonitorService.shared
    @StateObject private var modelManager = ModelManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedModels = Set<String>()
    @State private var isEditMode = false
    @State private var showingDeleteConfirmation = false
    @State private var modelToDelete: DownloadedModelInfo?
    @State private var isDeleting = false
    @State private var deletionError: Error?
    @State private var showingError = false
    @State private var sortOrder: SortOrder = .sizeDescending
    
    enum SortOrder: String, CaseIterable {
        case nameAscending = "Name (A-Z)"
        case nameDescending = "Name (Z-A)"
        case sizeAscending = "Size (Small to Large)"
        case sizeDescending = "Size (Large to Small)"
        case dateAscending = "Date (Oldest First)"
        case dateDescending = "Date (Newest First)"
    }
    
    var sortedModels: [DownloadedModelInfo] {
        let models = storageService.storageInfo?.downloadedModels ?? []
        
        switch sortOrder {
        case .nameAscending:
            return models.sorted { $0.name < $1.name }
        case .nameDescending:
            return models.sorted { $0.name > $1.name }
        case .sizeAscending:
            return models.sorted { $0.size < $1.size }
        case .sizeDescending:
            return models.sorted { $0.size > $1.size }
        case .dateAscending:
            return models.sorted(by: { $0.downloadDate < $1.downloadDate })
        case .dateDescending:
            return models.sorted(by: { $0.downloadDate > $1.downloadDate })
        }
    }
    
    var totalSelectedSize: Int64 {
        let models = storageService.storageInfo?.downloadedModels ?? []
        return models
            .filter { selectedModels.contains($0.path) }
            .reduce(0) { $0 + $1.size }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if let storageInfo = storageService.storageInfo {
                    // Header with storage summary
                    storageHeaderView(storageInfo)
                    
                    // Sort options
                    sortingView
                    
                    // Models list
                    if sortedModels.isEmpty {
                        emptyStateView
                    } else {
                        modelsListView
                    }
                } else {
                    ProgressView("Loading models...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Downloaded Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditMode ? "Done" : "Edit") {
                        withAnimation {
                            isEditMode.toggle()
                            if !isEditMode {
                                selectedModels.removeAll()
                            }
                        }
                    }
                    .disabled(sortedModels.isEmpty)
                }
            }
        }
        .task {
            await storageService.refreshStorageInfo()
        }
        .alert("Delete Model", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    deleteModel(model)
                }
            }
        } message: {
            if let model = modelToDelete {
                Text("Are you sure you want to delete \"\(model.name)\"? This action cannot be undone.")
            }
        }
        .alert("Deletion Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(deletionError?.localizedDescription ?? "Failed to delete model")
        }
    }
    
    // MARK: - Subviews
    
    private func storageHeaderView(_ storageInfo: StorageInfo) -> some View {
        VStack(spacing: 12) {
            // Storage overview
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Models Storage")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(storageInfo.modelsSize.formattedFileSize)
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Divider()
                    .frame(height: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model Count")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(storageInfo.downloadedModels.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Selection info when in edit mode
            if isEditMode && !selectedModels.isEmpty {
                HStack {
                    Text("\(selectedModels.count) selected")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(totalSelectedSize.formattedFileSize)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
            }
        }
        .padding(.vertical)
        .background(Color(.secondarySystemBackground))
    }
    
    private var sortingView: some View {
        HStack {
            Text("Sort by:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Picker("Sort Order", selection: $sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .font(.caption)
            
            Spacer()
            
            if isEditMode && !selectedModels.isEmpty {
                Button(action: deleteSelectedModels) {
                    Label("Delete Selected", systemImage: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .disabled(isDeleting)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var modelsListView: some View {
        List {
            ForEach(sortedModels, id: \.path) { model in
                ModelRowView(
                    model: model,
                    isEditMode: isEditMode,
                    isSelected: selectedModels.contains(model.path),
                    onToggleSelection: {
                        if selectedModels.contains(model.path) {
                            selectedModels.remove(model.path)
                        } else {
                            selectedModels.insert(model.path)
                        }
                    },
                    onDelete: {
                        modelToDelete = model
                        showingDeleteConfirmation = true
                    },
                    onVerify: {
                        verifyModel(model)
                    }
                )
            }
        }
        .listStyle(PlainListStyle())
    }
    
    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Downloaded Models",
            systemImage: "doc.badge.arrow.up",
            description: Text("Download models from the Models tab to use them for inference")
        )
    }
    
    // MARK: - Actions
    
    private func deleteModel(_ model: DownloadedModelInfo) {
        isDeleting = true
        
        Task {
            do {
                // Delete the model file
                try FileManager.default.removeItem(atPath: model.path)
                
                // Refresh storage info
                await storageService.refreshStorageInfo()
                
                // Refresh model list
                await modelManager.refreshModelList()
                
                await MainActor.run {
                    isDeleting = false
                    modelToDelete = nil
                    
                    // Remove from selection if it was selected
                    selectedModels.remove(model.path)
                }
            } catch {
                await MainActor.run {
                    deletionError = error
                    showingError = true
                    isDeleting = false
                }
            }
        }
    }
    
    private func deleteSelectedModels() {
        showingDeleteConfirmation = true
        // Set modelToDelete to nil to trigger bulk delete
        modelToDelete = nil
    }
    
    private func performBulkDelete() {
        isDeleting = true
        
        Task {
            var failedDeletions: [String] = []
            
            for modelPath in selectedModels {
                do {
                    try FileManager.default.removeItem(atPath: modelPath)
                } catch {
                    failedDeletions.append(URL(fileURLWithPath: modelPath).lastPathComponent)
                }
            }
            
            // Refresh storage info
            await storageService.refreshStorageInfo()
            
            // Refresh model list
            await modelManager.refreshModelList()
            
            await MainActor.run {
                isDeleting = false
                selectedModels.removeAll()
                isEditMode = false
                
                if !failedDeletions.isEmpty {
                    deletionError = NSError(
                        domain: "ModelDeletion",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to delete \(failedDeletions.count) models"]
                    )
                    showingError = true
                }
            }
        }
    }
    
    private func verifyModel(_ model: DownloadedModelInfo) {
        // Check if the file still exists
        let fileExists = FileManager.default.fileExists(atPath: model.path)
        
        if !fileExists {
            // Model file is missing, refresh the list
            Task {
                await storageService.refreshStorageInfo()
                await modelManager.refreshModelList()
            }
        }
    }
}

// MARK: - Model Row View

struct ModelRowView: View {
    let model: DownloadedModelInfo
    let isEditMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onDelete: () -> Void
    let onVerify: () -> Void
    
    @State private var fileExists = true
    
    private func formatPath(_ path: String) -> String {
        // Get the relative path from the Documents directory
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path {
            if path.hasPrefix(documentsPath) {
                let relativePath = String(path.dropFirst(documentsPath.count))
                return "~/Documents\(relativePath)"
            }
        }
        // If not in Documents, show the last few components
        let components = path.split(separator: "/")
        if components.count > 3 {
            return ".../\(components.suffix(3).joined(separator: "/"))"
        }
        return path
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox in edit mode
            if isEditMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .onTapGesture {
                        onToggleSelection()
                    }
            }
            
            // Model icon
            Image(systemName: fileExists ? "doc.fill" : "doc.badge.exclamationmark")
                .font(.title2)
                .foregroundColor(fileExists ? frameworkColor : .red)
                .frame(width: 40)
            
            // Model info
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(fileExists ? .primary : .secondary)
                
                HStack(spacing: 12) {
                    // Framework
                    Label(model.framework, systemImage: "cpu")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Size
                    Label(model.formattedSize, systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    // Date
                    Label(model.formattedDate, systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // File path
                Text(formatPath(model.path))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if !fileExists {
                    Text("File not found - tap to remove")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            
            Spacer()
            
            // Actions
            if !isEditMode {
                Menu {
                    Button(action: onVerify) {
                        Label("Verify File", systemImage: "checkmark.shield")
                    }
                    
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditMode {
                onToggleSelection()
            } else if !fileExists {
                onDelete()
            }
        }
        .onAppear {
            checkFileExists()
        }
    }
    
    private var frameworkColor: Color {
        switch model.framework.lowercased() {
        case "core ml": return .blue
        case "mlx": return .purple
        case "onnx runtime": return .orange
        case "tensorflow lite": return .green
        default: return .secondary
        }
    }
    
    private func checkFileExists() {
        fileExists = FileManager.default.fileExists(atPath: model.path)
    }
}

// Removed Int64 extension as it's already defined in StorageMonitorService.swift

#Preview {
    DownloadedModelsManagementView()
}