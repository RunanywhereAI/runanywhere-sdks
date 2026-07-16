//
//  AddFromHuggingFaceView.swift
//  RunAnywhereAI
//
//  PocketPal-style "Add from Hugging Face" flow: search the Hub, pick a repo,
//  choose a GGUF quantization (or an MLX bundle), then register + download it
//  through the SDK. The SDK owns resolution/download; this view only collects
//  the user's choice and surfaces progress.
//

import SwiftUI
import RunAnywhere

// MARK: - Download Coordinator

/// Owns the register + download work and per-item progress so the views stay
/// thin. Keys are the GGUF file path (or the repo id for MLX bundles).
@MainActor
final class HuggingFaceDownloadModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloading(Double)
        case done
        case failed(String)
    }

    @Published var phases: [String: Phase] = [:]

    /// Register the artifact with the SDK, then download it, updating progress.
    func download(
        key: String,
        name: String,
        url: String,
        framework: InferenceFramework,
        sizeBytes: Int64?
    ) async {
        phases[key] = .downloading(0)
        do {
            let model = try await RunAnywhere.registerModel(
                name: name,
                url: url,
                framework: framework,
                memoryRequirement: sizeBytes
            )
            try await RunAnywhere.downloadModel(model) { [weak self] progress in
                await MainActor.run {
                    self?.phases[key] = .downloading(Double(progress.overallProgress))
                }
            }
            phases[key] = .done
            await ModelListViewModel.shared.loadModelsFromRegistry()
        } catch {
            phases[key] = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Root View

struct AddFromHuggingFaceView: View {
    @Environment(\.dismiss)
    private var dismiss

    @State private var searchKind: HFSearchKind = .gguf
    @State private var query: String = ""
    @State private var results: [HFModelSummary] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var mlxAvailable = false

    private let client = HuggingFaceHubClient()

    /// Kinds offered in the segmented control — MLX only where it can run.
    private var availableKinds: [HFSearchKind] {
        mlxAvailable ? HFSearchKind.allCases : [.gguf]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                resultsContent
            }
            .navigationTitle("Add from Hugging Face")
            #if os(iOS)
            .navigationBarTitleDisplayModeCompat(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.escape)
                }
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 600, minHeight: 400, idealHeight: 520)
        #endif
        .task {
            await detectMLXAvailability()
        }
    }

    // MARK: Header (picker + search)

    private var header: some View {
        VStack(spacing: AppSpacing.mediumLarge) {
            if availableKinds.count > 1 {
                Picker("Format", selection: $searchKind) {
                    ForEach(availableKinds) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: AppSpacing.smallMedium) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.textSecondary)
                TextField("Search Hugging Face", text: $query)
                    .textFieldStyle(.plain)
                    #if os(iOS)
                    .autocapitalization(.none)
                    #endif
                    .autocorrectionDisabled()
                    .onSubmit { runSearch() }
                if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppSpacing.medium)
            .background(AppColors.backgroundGray6)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge))
        }
        .padding(AppSpacing.large)
    }

    // MARK: Results

    @ViewBuilder private var resultsContent: some View {
        if isSearching {
            Spacer()
            ProgressView("Searching…")
            Spacer()
        } else if let errorMessage {
            errorState(errorMessage)
        } else if results.isEmpty {
            emptyState
        } else {
            List(results) { repo in
                NavigationLink {
                    HuggingFaceRepoDetailView(repo: repo, kind: searchKind)
                } label: {
                    repoRow(repo)
                }
            }
            .listStyle(.plain)
        }
    }

    private func repoRow(_ repo: HFModelSummary) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text(repo.displayName)
                .font(AppTypography.subheadlineSemibold)
                .foregroundColor(AppColors.textPrimary)
            HStack(spacing: AppSpacing.medium) {
                if let owner = repo.owner {
                    Label(owner, systemImage: "person.crop.circle")
                }
                Label("\(repo.downloads)", systemImage: "arrow.down.circle")
                Label("\(repo.likes)", systemImage: "heart")
            }
            .font(AppTypography.caption)
            .foregroundColor(AppColors.textSecondary)
        }
        .padding(.vertical, AppSpacing.xxSmall)
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.mediumLarge) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(AppColors.textSecondary.opacity(0.6))
            Text(query.isEmpty ? "Search for on-device models" : "No results")
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: AppSpacing.mediumLarge) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .semibold))
                .foregroundColor(AppColors.statusRed)
            Text(message)
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xLarge)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        Task {
            do {
                let found = try await client.searchModels(query: trimmed, kind: searchKind)
                await MainActor.run {
                    results = found
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    results = []
                    isSearching = false
                }
            }
        }
    }

    private func detectMLXAvailability() async {
        let frameworks = await RunAnywhere.getRegisteredFrameworks()
        await MainActor.run {
            mlxAvailable = frameworks.contains(.mlx)
        }
    }
}

// MARK: - Repo Detail

struct HuggingFaceRepoDetailView: View {
    let repo: HFModelSummary
    let kind: HFSearchKind

    @StateObject private var downloadModel = HuggingFaceDownloadModel()
    @State private var files: [HFRepoFile] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let client = HuggingFaceHubClient()

    var body: some View {
        Group {
            switch kind {
            case .gguf:
                ggufContent
            case .mlx:
                mlxContent
            }
        }
        .navigationTitle(repo.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayModeCompat(.inline)
        #endif
        .task {
            if kind == .gguf {
                await loadFiles()
            }
        }
    }

    // MARK: GGUF (quant list)

    @ViewBuilder private var ggufContent: some View {
        if isLoading {
            ProgressView("Loading files…")
        } else if let errorMessage {
            detailError(errorMessage)
        } else if files.isEmpty {
            Text("No GGUF files found in this repo.")
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .padding()
        } else {
            List(files) { file in
                fileRow(file)
            }
            .listStyle(.plain)
        }
    }

    private func fileRow(_ file: HFRepoFile) -> some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                Text(file.quantLabel)
                    .font(AppTypography.subheadlineSemibold)
                    .foregroundColor(AppColors.textPrimary)
                Text(file.formattedSize)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            Spacer()
            downloadControl(for: file.path) {
                await startGgufDownload(file)
            }
        }
        .padding(.vertical, AppSpacing.xxSmall)
    }

    // MARK: MLX (single bundle)

    private var mlxContent: some View {
        VStack(spacing: AppSpacing.large) {
            VStack(spacing: AppSpacing.smallMedium) {
                Image(systemName: "cube.box")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(AppColors.primaryAccent)
                Text(repo.displayName)
                    .font(AppTypography.headlineSemibold)
                Text("MLX repo bundle")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            downloadControl(for: repo.id) {
                await startMLXDownload()
            }
            .frame(maxWidth: 260)

            if let errorMessage {
                Text(errorMessage)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.statusRed)
            }
            Spacer()
        }
        .padding(AppSpacing.xLarge)
    }

    // MARK: Shared download control

    @ViewBuilder
    private func downloadControl(for key: String, action: @escaping () async -> Void) -> some View {
        switch downloadModel.phases[key] ?? .idle {
        case .idle:
            Button {
                Task { await action() }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primaryAccent)
        case .downloading(let progress):
            HStack(spacing: AppSpacing.smallMedium) {
                ProgressView(value: progress)
                    .frame(width: 100)
                Text("\(Int(progress * 100))%")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
        case .done:
            Label("Downloaded", systemImage: "checkmark.circle.fill")
                .font(AppTypography.captionMedium)
                .foregroundColor(AppColors.statusGreen)
        case .failed(let message):
            VStack(alignment: .trailing, spacing: AppSpacing.xxSmall) {
                Button {
                    Task { await action() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                Text(message)
                    .font(AppTypography.caption2)
                    .foregroundColor(AppColors.statusRed)
                    .lineLimit(2)
            }
        }
    }

    private func detailError(_ message: String) -> some View {
        VStack(spacing: AppSpacing.mediumLarge) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(AppColors.statusRed)
            Text(message)
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(AppSpacing.xLarge)
    }

    // MARK: Actions

    private func loadFiles() async {
        isLoading = true
        errorMessage = nil
        do {
            let found = try await client.listGgufFiles(repoId: repo.id)
            await MainActor.run {
                files = found
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func startGgufDownload(_ file: HFRepoFile) async {
        let url = "https://huggingface.co/\(repo.id)/resolve/main/\(file.path)"
        let name = "\(repo.displayName) (\(file.quantLabel))"
        await downloadModel.download(
            key: file.path,
            name: name,
            url: url,
            framework: .llamaCpp,
            sizeBytes: file.sizeBytes > 0 ? file.sizeBytes : nil
        )
    }

    private func startMLXDownload() async {
        let url = "https://huggingface.co/\(repo.id)"
        await downloadModel.download(
            key: repo.id,
            name: repo.displayName,
            url: url,
            framework: .mlx,
            sizeBytes: nil
        )
    }
}

#Preview {
    AddFromHuggingFaceView()
}
