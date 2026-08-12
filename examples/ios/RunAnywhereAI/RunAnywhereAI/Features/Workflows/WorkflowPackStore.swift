//
//  WorkflowPackStore.swift
//  RunAnywhereAI
//
//  Installed node packs, and the three stages of moving a bundle: a document
//  waiting for a save panel, a decoded file waiting for the user to pick items
//  out of it, and the per-item outcome of the import that followed.
//
//  Commons owns all of it — resolving which packs an exported workflow needs,
//  refusing a bundle from a newer writer, and reporting per item what it
//  skipped. This type calls those verbs and holds what the UI has to show.
//

import Foundation
import Observation
import RunAnywhere

@MainActor
@Observable
final class WorkflowPackStore {
    private(set) var installedPacks: [RANodePack] = []
    private(set) var packsByID: [String: RANodePack] = [:]

    private(set) var pendingExport: WorkflowBundleDocument?
    private(set) var pendingExportName = "Workflows"
    private(set) var pendingImport: WorkflowBundleImportRequest?
    private(set) var importOutcome: WorkflowImportOutcome?

    var errorMessage: String?

    // MARK: - Installed packs

    /// A failed listing leaves the palette without packs rather than blocking
    /// the editor, the same way the workflow library does.
    func refresh() async {
        guard let packs = try? await RunAnywhere.workflows.packs() else { return }
        installedPacks = packs.sorted { left, right in
            left.displayName.localizedCaseInsensitiveCompare(right.displayName) == .orderedAscending
        }
        packsByID = Self.indexed(installedPacks)
    }

    private static func indexed(_ packs: [RANodePack]) -> [String: RANodePack] {
        let pairs = packs.map { ($0.id, $0) }
        return Dictionary(pairs) { first, _ in first }
    }

    func pack(_ id: String) -> RANodePack? {
        packsByID[id]
    }

    #if DEBUG
    /// Previews cannot reach the SDK, and a pack card with no pack behind it
    /// only ever renders the missing placeholder.
    func seedForPreview(_ packs: [RANodePack]) {
        installedPacks = packs
        packsByID = Self.indexed(packs)
    }
    #endif

    /// Packs grouped for the palette, under whichever category each declared.
    /// Built-in category names match their palette section so a pack that says
    /// "Logic" lands beside the logic nodes rather than in a group of its own.
    func packs(inCategory category: String) -> [RANodePack] {
        installedPacks.filter {
            $0.paletteCategory.localizedCaseInsensitiveCompare(category) == .orderedSame
        }
    }

    /// Declared categories that match none of the built-in palette sections, so
    /// their packs still get somewhere to live.
    var customCategories: [String] {
        let builtIn = Set(WorkflowNodeCategory.allCases.map { $0.rawValue.lowercased() })
        let declared = installedPacks.map(\.paletteCategory)
        return Array(Set(declared.filter { !builtIn.contains($0.lowercased()) })).sorted()
    }

    @discardableResult
    func save(_ pack: RANodePack) async -> Bool {
        do {
            try await RunAnywhere.workflows.savePack(pack)
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ pack: RANodePack) async {
        do {
            try await RunAnywhere.workflows.deletePack(id: pack.id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Export

    func prepareExport(workflowIDs: [String], suggestedName: String) async {
        guard !workflowIDs.isEmpty else { return }
        do {
            let bundle = try await RunAnywhere.workflows.exportBundle(workflowIDs: workflowIDs)
            pendingExportName = suggestedName
            pendingExport = try WorkflowBundleDocument(bundle: bundle)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearPendingExport() {
        pendingExport = nil
    }

    func finishExport(_ result: Result<URL, Error>) {
        pendingExport = nil
        if case .failure(let error) = result, !error.isUserCancelled {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Import

    /// Read and decode only. Nothing is installed until the caller acts on the
    /// request, so the user has a chance to pick items out of the bundle and —
    /// for a script pack — to see what it may reach before agreeing to it.
    @discardableResult
    func loadBundle(from result: Result<URL, Error>) -> WorkflowBundleImportRequest? {
        switch result {
        case .failure(let error):
            if !error.isUserCancelled { errorMessage = error.localizedDescription }
            return nil
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let bundle = try RAWorkflowBundle(serializedBytes: Data(contentsOf: url))
                let request = WorkflowBundleImportRequest(
                    fileName: url.lastPathComponent, bundle: bundle
                )
                pendingImport = request.needsReview ? request : nil
                return request
            } catch {
                errorMessage = "\(url.lastPathComponent) is not a workflow bundle this app can read."
                return nil
            }
        }
    }

    func clearPendingImport() {
        pendingImport = nil
    }

    func clearImportOutcome() {
        importOutcome = nil
    }

    /// Import the chosen items. A pack left unselected is never written to disk,
    /// which is what makes declining a script pack's capabilities mean something.
    func performImport(
        _ request: WorkflowBundleImportRequest,
        workflowIDs: Set<String>,
        packIDs: Set<String>
    ) async {
        pendingImport = nil

        var bundle = request.bundle
        bundle.workflows = request.bundle.workflows.filter { workflowIDs.contains($0.id) }
        bundle.packs = request.bundle.packs.filter { packIDs.contains($0.id) }

        guard !bundle.workflows.isEmpty || !bundle.packs.isEmpty else { return }

        do {
            let result = try await RunAnywhere.workflows.importBundle(bundle)
            let workflowPairs = request.bundle.workflows.map { ($0.id, $0.name) }
            let packPairs = request.bundle.packs.map { ($0.id, $0.displayName) }
            let names = Dictionary(workflowPairs) { first, _ in first }
            let packNames = Dictionary(packPairs) { first, _ in first }
            importOutcome = WorkflowImportOutcome(
                workflows: result.importedWorkflowIds.map { names[$0] ?? $0 },
                packs: result.importedPackIds.map { packNames[$0] ?? $0 },
                skipped: result.skipped,
                declinedPacks: request.bundle.packs
                    .filter { !packIDs.contains($0.id) }
                    .map(\.displayName)
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension Error {
    /// Closing a save or open panel is not a failure worth an alert.
    var isUserCancelled: Bool {
        let error = self as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
    }
}
