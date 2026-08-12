//
//  WorkflowEditorViewModel+Packs.swift
//  RunAnywhereAI
//
//  The editor's side of node packs and bundles. Placing a pack, uninstalling
//  one, and moving a bundle in or out are all orchestration: `WorkflowPackStore`
//  makes the SDK calls, and what lives here is what the open graph and the
//  library have to do afterwards.
//

import Foundation
import RunAnywhere
import SwiftUI

extension WorkflowEditorViewModel {
    // MARK: - Node packs

    @discardableResult
    func addPackNode(_ pack: RANodePack, at position: CGPoint) -> WorkflowNode? {
        var node = WorkflowNode(
            kind: .packNode,
            name: graph.uniqueName(basedOn: pack.displayName),
            position: WorkflowCanvasMetrics.snapToGrid(position)
        )
        node.settings = WorkflowPackCatalog.settings(for: pack)
        mutate { $0.nodes.append(node) }
        selectedNodeIDs = [node.id]
        selectedEdgeID = nil
        return node
    }

    func presentation(of node: WorkflowNode) -> WorkflowNodePresentation {
        WorkflowPackCatalog.presentation(of: node, packs: packStore.packsByID)
    }

    /// Uninstalling a pack leaves any node that used it as a marked placeholder
    /// rather than deleting the user's work.
    func deletePack(_ pack: RANodePack) async {
        await packStore.delete(pack)
        reconcilePackNodes()
    }

    // MARK: - Bundles

    /// Export reads what is stored, so a selection that includes the open
    /// workflow saves it first rather than shipping the previous version.
    func exportBundle(workflowIDs: Set<String>) async {
        guard !workflowIDs.isEmpty else { return }
        if workflowIDs.contains(workflowID) {
            await save()
            guard errorMessage == nil else { return }
        }
        // Library order first, then anything selected that the library listing
        // does not know about, so a selection is never silently narrowed.
        let known = savedWorkflows.map(\.id).filter(workflowIDs.contains)
        let ordered = known + workflowIDs.subtracting(known).sorted()
        let suggested = ordered.count == 1
            ? (savedWorkflows.first { $0.id == ordered[0] }?.name ?? workflowName)
            : "Workflows"
        await packStore.prepareExport(workflowIDs: ordered, suggestedName: suggested)
    }

    /// A bundle with one item and no script pack in it has nothing to choose and
    /// nothing to agree to, so it imports without a sheet.
    func loadBundle(_ result: Result<URL, Error>) async {
        guard let request = packStore.loadBundle(from: result), !request.needsReview else { return }
        await importBundle(
            request,
            workflows: Set(request.bundle.workflows.map(\.id)),
            packs: Set(request.bundle.packs.map(\.id))
        )
    }

    func importBundle(
        _ request: WorkflowBundleImportRequest,
        workflows: Set<String>,
        packs: Set<String>
    ) async {
        await packStore.performImport(request, workflowIDs: workflows, packIDs: packs)
        await refreshLibrary()
        await refreshPacks()
        await WorkflowScheduler.shared.reload()
    }

    /// Turn the open graph into a composite pack. It composes nodes the host
    /// already has, so it grants nothing new and needs no capability review.
    func saveAsPack(_ draft: WorkflowPackDraft) async -> Bool {
        let id = WorkflowPackCatalog.freshID(basedOn: draft.name)
        let inner = WorkflowDocumentMapping.document(
            id: id,
            name: draft.name,
            graph: graph,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
        let saved = await packStore.save(draft.compositePack(id: id, graph: inner))
        if saved { reconcilePackNodes() }
        return saved
    }

    func saveScriptPack(_ draft: WorkflowPackDraft) async -> Bool {
        let id = WorkflowPackCatalog.freshID(basedOn: draft.name)
        let saved = await packStore.save(draft.scriptPack(id: id))
        if saved { reconcilePackNodes() }
        return saved
    }
}
