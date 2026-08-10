//
//  AddFromHuggingFaceView.swift
//  RunAnywhereAI
//
//  PocketPal-style "Add from Hugging Face" flow: search the Hub, pick a repo,
//  choose a GGUF quantization (or an MLX bundle), then register + download it
//  through the SDK. The SDK owns resolution/download; this view only collects
//  the user's choice and surfaces progress.
//
//  The sheet opens on the curated sub-1B catalog rather than on an empty search
//  box. An empty box asks the reader to already know what a good on-device model
//  is called, which on a Hub with a million repos is the whole problem; a ranked
//  set of models that actually fit on a phone gives them something to tap on the
//  first frame. Search is untouched and takes over the moment they type.
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
        /// In flight. `fraction` is 0...1 when a position is knowable, and nil
        /// when it is not — an unknown size, or a phase like verification that
        /// has no measurable length.
        case running(ModelDownloadPhase, fraction: Double?)
        case done
        case failed(String)
    }

    @Published var phases: [String: Phase] = [:]

    /// Register the artifact with the SDK, then download it, updating progress.
    ///
    /// Every event is read, not only `.progress`. `models.download(id:)` reports
    /// a failure as a `.failed` *event* and then finishes its stream normally, so
    /// a loop that filters for `.progress` runs off the end of a failed download
    /// and marks it "Downloaded" — a row claiming a model the user does not have.
    /// The verification and unpacking phases matter for the opposite reason: on a
    /// multi-gigabyte GGUF they run long enough that a bar left at 100% with no
    /// explanation reads as a hang.
    func download(
        key: String,
        name: String,
        url: String,
        framework: InferenceFramework,
        sizeBytes: Int64?
    ) async {
        phases[key] = .running(.starting, fraction: nil)
        do {
            let model = try await RunAnywhere.models.register(
                .url(
                    url,
                    name: name,
                    framework: framework,
                    memoryRequirementBytes: sizeBytes
                )
            )
            var terminal: Phase = .done
            for try await event in try await RunAnywhere.models.download(id: model.id) {
                switch event {
                case .started:
                    phases[key] = .running(.starting, fraction: nil)
                case .progress(let snapshot):
                    // Nil fraction means the size is unknown; the track sweeps
                    // rather than snapping back to zero.
                    phases[key] = .running(.downloading, fraction: snapshot.fraction.map(Double.init))
                case .verifying:
                    phases[key] = .running(.verifying, fraction: nil)
                case .extracting(_, _, let percent):
                    phases[key] = .running(
                        .extracting(percent: percent),
                        fraction: percent.map { Double($0) / 100 }
                    )
                case .completed:
                    terminal = .done
                case .cancelled:
                    terminal = .idle
                case .failed(_, _, let error):
                    terminal = .failed(error.message)
                }
            }
            phases[key] = terminal
            if terminal == .done {
                await ModelListViewModel.shared.loadModelsFromRegistry()
            }
        } catch {
            phases[key] = .failed((error as? SDKException)?.message ?? error.localizedDescription)
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

    /// The trimmed query, and the single place the sheet decides whether a
    /// search is in play at all. Whitespace-only input is not a search.
    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The curated set for whichever kind the picker has selected.
    ///
    /// MLX is reachable here only because `availableKinds` offered it, and that
    /// list is built from `mlxAvailable` — the registered-frameworks probe below.
    /// Reusing `searchKind` is therefore the same capability signal, not a
    /// second one.
    private var suggestions: [HFSuggestedModel] {
        HuggingFaceHubClient.suggestedModels(for: searchKind)
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
        .onChange(of: query) { _, newValue in
            // Clearing the field is what brings the suggestions back, so the
            // now-stale results have to go with it. Typing still does not fire a
            // request — submitting does; this only tears state down.
            guard newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            results = []
            errorMessage = nil
        }
        .onChange(of: searchKind) { _, _ in
            // Rows route by `searchKind`, so leaving GGUF hits on screen after a
            // switch to MLX would open the GGUF file list against an MLX repo.
            // Re-query rather than relabel; an empty query simply falls through
            // to the other kind's suggestions.
            results = []
            errorMessage = nil
            runSearch()
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
                    // Emptying the field is the only thing this does; the
                    // `onChange(of: query)` above owns tearing down the results,
                    // so clearing by keyboard and clearing by button cannot
                    // diverge.
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(AppSpacing.medium)
            .background(AppColors.backgroundGray6)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusLarge))
        }
        .padding(AppSpacing.large)
    }

    // MARK: Results

    /// Five branches, because these are five different facts: a request in
    /// flight, a request that failed, hits to show, an untouched sheet, and a
    /// query that genuinely matched nothing. The last two used to share one
    /// view; keeping them apart is what stops a failed search from silently
    /// presenting the curated catalog as its results.
    @ViewBuilder private var resultsContent: some View {
        if isSearching {
            Spacer()
            ProgressView("Searching…")
            Spacer()
        } else if let errorMessage {
            errorState(errorMessage)
        } else if !results.isEmpty {
            resultsList
        } else if trimmedQuery.isEmpty {
            suggestionsList
        } else {
            noResultsState
        }
    }

    // MARK: Search results

    private var resultsList: some View {
        List(results) { repo in
            NavigationLink {
                HuggingFaceRepoDetailView(repo: repo, kind: searchKind)
            } label: {
                repoRow(repo)
            }
        }
        .listStyle(.plain)
    }

    private func repoRow(_ repo: HFModelSummary) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(spacing: AppSpacing.smallMedium) {
                Text(repo.displayName)
                    .font(AppTypography.subheadlineSemibold)
                    .foregroundColor(AppColors.textPrimary)
                // The same chip the suggestion tiles carry, so a searched repo
                // and a suggested one are measured on the same scale. Only GGUF
                // searches can produce one; MLX rows simply have no badge.
                if let badge = repo.parameterBadge {
                    HFParameterBadge(text: badge)
                }
            }
            HStack(spacing: AppSpacing.medium) {
                if let owner = repo.owner {
                    Label(owner, systemImage: "person.crop.circle")
                        .accessibilityLabel("Published by \(owner)")
                }
                // Counts are omitted rather than zeroed when the Hub did not
                // report them — "0 downloads" is a claim, and a wrong one.
                if let downloads = repo.downloads {
                    Label(downloads.formatted(), systemImage: "arrow.down.circle")
                        .accessibilityLabel("\(downloads.formatted()) downloads")
                }
                if let likes = repo.likes {
                    Label(likes.formatted(), systemImage: "heart")
                        .accessibilityLabel("\(likes.formatted()) likes")
                }
            }
            .font(AppTypography.caption)
            .foregroundColor(AppColors.textSecondary)
        }
        .padding(.vertical, AppSpacing.xxSmall)
    }

    // MARK: Suggestions (idle state)

    private var suggestionsList: some View {
        List {
            Section {
                ForEach(suggestions) { suggestion in
                    // Deliberately the same destination a search hit opens.
                    // A suggestion is a shortcut to the existing flow, not a
                    // second download path.
                    NavigationLink {
                        HuggingFaceRepoDetailView(repo: suggestion.summary, kind: searchKind)
                    } label: {
                        suggestionRow(suggestion)
                    }
                }
            } header: {
                suggestionsHeader
            }
        }
        .listStyle(.plain)
    }

    private var suggestionsHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            Text("Suggested small models")
                .font(AppTypography.subheadlineSemibold)
                .foregroundColor(AppColors.textPrimary)
            Text("All under 1B parameters.")
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
        }
        // `List` uppercases section headers by default. This one is a title and
        // a sentence, not a group label, and "ALL UNDER 1B PARAMETERS." shouts.
        .textCase(nil)
        .padding(.vertical, AppSpacing.xSmall)
    }

    private func suggestionRow(_ suggestion: HFSuggestedModel) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            HStack(spacing: AppSpacing.smallMedium) {
                Text(suggestion.title)
                    .font(AppTypography.subheadlineSemibold)
                    .foregroundColor(AppColors.textPrimary)
                HFParameterBadge(text: suggestion.parameterBadge)
            }
            // Middle truncation: the tail of a repo id ("-Instruct-GGUF") is
            // what distinguishes it from its siblings, so it is the one part
            // that must survive a narrow phone.
            Text(suggestion.repoId)
                .font(AppTypography.caption2)
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(suggestion.blurb)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, AppSpacing.xxSmall)
    }

    // MARK: Empty results

    /// A query the reader actually typed that matched nothing.
    ///
    /// `ContentUnavailableView` rather than the app's branded `EmptyStateView`:
    /// on a plain list of search results, matching the system exactly is what
    /// makes the state read as "no matches" instead of "something broke".
    private var noResultsState: some View {
        ContentUnavailableView {
            Label("No results", systemImage: "magnifyingglass")
        } description: {
            Text("Nothing on Hugging Face matched “\(trimmedQuery)”. "
                 + "Clear the search to see suggested small models.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        let trimmed = trimmedQuery
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

// MARK: - Parameter Badge

/// The parameter-count chip, shared by suggestion tiles and search-result rows
/// so the two read as one screen rather than two features bolted together.
///
/// Brand-tinted because the parameter count is the thing this screen is
/// organised around, but tinted carefully: the fill is held at 12% and the text
/// is `brandInk`, not `brand`. Flat `#FF6900` on a 20% wash measures ≈2.6:1 and
/// is unreadable at chip size; the deepened ink on a 12% wash measures ≈4.8:1 in
/// light and ≈6.4:1 in dark, which clears AA for text this small.
private struct HFParameterBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppTypography.caption2)
            .fontWeight(.semibold)
            .foregroundColor(AppColors.brandInk)
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, AppSpacing.xxSmall)
            .background(
                AppColors.brand.opacity(0.12),
                in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall, style: .continuous)
            )
            // "135M" alone is ambiguous read aloud — megabytes, messages, or
            // parameters. Say what it counts.
            .accessibilityLabel("\(text) parameters")
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
        case let .running(phase, fraction):
            HStack(spacing: AppSpacing.smallMedium) {
                // No value means no position to claim — an unknown Content-Length
                // or a phase with no measurable length — so the bar spins rather
                // than sitting at a number it made up.
                if let fraction {
                    ProgressView(value: fraction).frame(width: 100)
                    Text("\(Int(fraction * 100))%")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .monospacedDigit()
                } else {
                    ProgressView().controlSize(.small)
                    Text(phase.label)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                fraction.map { "\(phase.label), \(Int($0 * 100)) percent" } ?? phase.label
            )
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
