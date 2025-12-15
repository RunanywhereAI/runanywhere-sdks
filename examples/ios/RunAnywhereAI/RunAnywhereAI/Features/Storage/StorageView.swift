//
//  StorageView.swift
//  RunAnywhereAI
//
//  Simplified storage view using SDK methods
//

import SwiftUI
import RunAnywhere

struct StorageView: View {
    @StateObject private var viewModel = StorageViewModel()

    var body: some View {
        #if os(macOS)
        // macOS: Custom layout without List
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xxLarge) {
                Text("Storage Management")
                    .font(AppTypography.largeTitleBold)
                    .padding(.bottom, AppSpacing.medium)

                // Storage Overview Card
                VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                    HStack {
                        Text("Storage Overview")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.textSecondary)

                        Spacer()

                        Button(action: {
                            Task {
                                await viewModel.refreshData()
                            }
                        }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }

                    VStack(spacing: 0) {
                        storageOverviewContent
                    }
                    .padding(AppSpacing.large)
                    .background(AppColors.backgroundSecondary)
                    .cornerRadius(AppSpacing.cornerRadiusLarge)
                }

                // Downloaded Models Card
                VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                    Text("Downloaded Models")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.textSecondary)

                    VStack(spacing: 0) {
                        storedModelsContent
                    }
                    .padding(AppSpacing.large)
                    .background(AppColors.backgroundSecondary)
                    .cornerRadius(AppSpacing.cornerRadiusLarge)
                }

                // Storage Management Card
                VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                    Text("Storage Management")
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.textSecondary)

                    VStack(spacing: 0) {
                        cacheManagementContent
                    }
                    .padding(AppSpacing.large)
                    .background(AppColors.backgroundSecondary)
                    .cornerRadius(AppSpacing.cornerRadiusLarge)
                }

                Spacer(minLength: AppSpacing.xxLarge)
            }
            .padding(AppSpacing.xxLarge)
            .frame(maxWidth: AppLayout.maxContentWidthLarge, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary)
        .task {
            await viewModel.loadData()
        }
        #else
        // iOS: Keep NavigationView
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
        #endif
    }

    #if os(macOS)
    private var storageOverviewContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
                // Total storage usage
                HStack {
                    Label("Total Usage", systemImage: "externaldrive")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: viewModel.totalStorageSize, countStyle: .file))
                        .foregroundColor(AppColors.textSecondary)
                }

                // Available space
                HStack {
                    Label("Available Space", systemImage: "externaldrive.badge.plus")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: viewModel.availableSpace, countStyle: .file))
                        .foregroundColor(AppColors.primaryGreen)
                }

                // Models storage
                HStack {
                    Label("Models Storage", systemImage: "cpu")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: viewModel.modelStorageSize, countStyle: .file))
                        .foregroundColor(AppColors.primaryBlue)
                }

                // Models count
                HStack {
                    Label("Downloaded Models", systemImage: "number")
                    Spacer()
                    Text("\(viewModel.storedModels.count)")
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
    #endif

    private var storageOverviewSection: some View {
        Section("Storage Overview") {
            VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
                // Total storage usage
                HStack {
                    Label("Total Usage", systemImage: "externaldrive")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: viewModel.totalStorageSize, countStyle: .file))
                        .foregroundColor(AppColors.textSecondary)
                }

                // Available space
                HStack {
                    Label("Available Space", systemImage: "externaldrive.badge.plus")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: viewModel.availableSpace, countStyle: .file))
                        .foregroundColor(AppColors.primaryGreen)
                }

                // Models storage
                HStack {
                    Label("Models Storage", systemImage: "cpu")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: viewModel.modelStorageSize, countStyle: .file))
                        .foregroundColor(AppColors.primaryBlue)
                }

                // Models count
                HStack {
                    Label("Downloaded Models", systemImage: "number")
                    Spacer()
                    Text("\(viewModel.storedModels.count)")
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .padding(.vertical, AppSpacing.xSmall)
        }
    }

    #if os(macOS)
    private var storedModelsContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.mediumLarge) {
            if viewModel.storedModels.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: AppSpacing.mediumLarge) {
                        Image(systemName: "cube")
                            .font(AppTypography.system48)
                            .foregroundColor(AppColors.textSecondary.opacity(0.5))
                        Text("No models downloaded yet")
                            .foregroundColor(AppColors.textSecondary)
                            .font(AppTypography.callout)
                    }
                    .padding(.vertical, AppSpacing.xxLarge)
                    Spacer()
                }
            } else {
                ForEach(viewModel.storedModels, id: \.id) { model in
                    StoredModelRow(model: model) {
                        await viewModel.deleteModel(model)
                    }
                    if model.id != viewModel.storedModels.last?.id {
                        Divider()
                            .padding(.vertical, AppSpacing.xSmall)
                    }
                }
            }
        }
    }
    #endif

    private var storedModelsSection: some View {
        Section("Downloaded Models") {
            if viewModel.storedModels.isEmpty {
                Text("No models downloaded yet")
                    .foregroundColor(AppColors.textSecondary)
                    .font(AppTypography.caption)
            } else {
                ForEach(viewModel.storedModels, id: \.id) { model in
                    StoredModelRow(model: model) {
                        await viewModel.deleteModel(model)
                    }
                }
            }
        }
    }

    #if os(macOS)
    private var cacheManagementContent: some View {
        VStack(spacing: AppSpacing.large) {
            Button(action: {
                Task {
                    await viewModel.clearCache()
                }
            }) {
                HStack {
                    Image(systemName: "trash")
                        .foregroundColor(AppColors.primaryRed)
                    Text("Clear Cache")
                    Spacer()
                    Text("Free up space by clearing cached data")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(AppSpacing.mediumLarge)
            .background(AppColors.badgeRed)
            .cornerRadius(AppSpacing.cornerRadiusRegular)
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular)
                    .stroke(AppColors.primaryRed.opacity(0.3), lineWidth: AppSpacing.strokeRegular)
            )

            Button(action: {
                Task {
                    await viewModel.cleanTempFiles()
                }
            }) {
                HStack {
                    Image(systemName: "trash")
                        .foregroundColor(AppColors.primaryOrange)
                    Text("Clean Temporary Files")
                    Spacer()
                    Text("Remove temporary files and logs")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(AppSpacing.mediumLarge)
            .background(AppColors.badgeOrange)
            .cornerRadius(AppSpacing.cornerRadiusRegular)
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusRegular)
                    .stroke(AppColors.primaryOrange.opacity(0.3), lineWidth: AppSpacing.strokeRegular)
            )
        }
    }
    #endif

    private var cacheManagementSection: some View {
        Section("Storage Management") {
            Button(action: {
                Task {
                    await viewModel.clearCache()
                }
            }) {
                HStack {
                    Image(systemName: "trash")
                        .foregroundColor(AppColors.primaryRed)
                    Text("Clear Cache")
                        .foregroundColor(AppColors.primaryRed)
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
                        .foregroundColor(AppColors.primaryOrange)
                    Text("Clean Temporary Files")
                        .foregroundColor(AppColors.primaryOrange)
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
        VStack(alignment: .leading, spacing: AppSpacing.smallMedium) {
            HStack {
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    Text(model.name)
                        .font(AppTypography.subheadlineMedium)

                    HStack(spacing: AppSpacing.smallMedium) {
                        Text(model.format.rawValue.uppercased())
                            .font(AppTypography.caption2)
                            .padding(.horizontal, AppSpacing.small)
                            .padding(.vertical, AppSpacing.xxSmall)
                            .background(AppColors.badgeBlue)
                            .cornerRadius(AppSpacing.cornerRadiusSmall)

                        if let framework = model.framework {
                            Text(framework.displayName)
                                .font(AppTypography.caption2)
                                .padding(.horizontal, AppSpacing.small)
                                .padding(.vertical, AppSpacing.xxSmall)
                                .background(AppColors.badgeGreen)
                                .cornerRadius(AppSpacing.cornerRadiusSmall)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: AppSpacing.xSmall) {
                    Text(ByteCountFormatter.string(fromByteCount: model.size, countStyle: .file))
                        .font(AppTypography.captionMedium)

                    HStack(spacing: AppSpacing.xSmall) {
                        Button(showingDetails ? "Hide" : "Details") {
                            withAnimation {
                                showingDetails.toggle()
                            }
                        }
                        .font(AppTypography.caption2)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(AppColors.primaryRed)
                        }
                        .font(AppTypography.caption2)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(isDeleting)
                    }
                }
            }

            if showingDetails {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    // Model Format and Framework
                    HStack {
                        Text("Format:")
                            .font(AppTypography.caption2Medium)
                        Text(model.format.rawValue.uppercased())
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.textSecondary)
                    }

                    if let framework = model.framework {
                        HStack {
                            Text("Framework:")
                                .font(AppTypography.caption2Medium)
                            Text(framework.displayName)
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }

                    // Description
                    if let description = model.description {
                        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                            Text("Description:")
                                .font(AppTypography.caption2Medium)
                            Text(description)
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Tags
                    if !model.tags.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                            Text("Tags:")
                                .font(AppTypography.caption2Medium)
                            HStack(spacing: AppSpacing.xSmall) {
                                ForEach(model.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(AppTypography.caption2)
                                        .padding(.horizontal, AppSpacing.small)
                                        .padding(.vertical, AppSpacing.xxSmall)
                                        .background(AppColors.badgeBlue)
                                        .cornerRadius(AppSpacing.cornerRadiusSmall)
                                }
                            }
                        }
                    }

                    Divider()

                    // File Information
                    VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                        Text("Path:")
                            .font(AppTypography.caption2Medium)
                        Text(model.path.path)
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let checksum = model.checksum {
                        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                            Text("Checksum:")
                                .font(AppTypography.caption2Medium)
                            Text(checksum)
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    HStack {
                        Text("Created:")
                            .font(AppTypography.caption2Medium)
                        Text(model.createdDate, style: .date)
                            .font(AppTypography.caption2)
                            .foregroundColor(AppColors.textSecondary)
                    }

                    if let lastUsed = model.lastUsed {
                        HStack {
                            Text("Last used:")
                                .font(AppTypography.caption2Medium)
                            Text(lastUsed, style: .relative)
                                .font(AppTypography.caption2)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                }
                .padding(.top, AppSpacing.xSmall)
                .padding(.horizontal, AppSpacing.smallMedium)
                .padding(.vertical, AppSpacing.small)
                .background(AppColors.backgroundTertiary)
                .cornerRadius(AppSpacing.cornerRadiusRegular)
            }
        }
        .padding(.vertical, AppSpacing.xSmall)
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
