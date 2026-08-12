//
//  WorkflowEditorViewModel.swift
//  RunAnywhereAI
//
//  Owns the graph, selection, undo, and every SDK call the workflow editor
//  makes. Undo is snapshot-based: WorkflowGraph is a small value type, so each
//  undoable edit stores the whole previous graph and restoring it is one
//  assignment — no per-operation inverse logic to get wrong.
//

import Foundation
import Observation
import RunAnywhere
import SwiftUI

@MainActor
@Observable
final class WorkflowEditorViewModel {
    private(set) var workflowID: String
    var workflowName: String
    private(set) var graph = WorkflowGraph()

    var selectedNodeIDs: Set<String> = []
    var selectedEdgeID: String?

    private(set) var draft: WorkflowDraftConnection?
    private(set) var draftCandidates: Set<WorkflowEndpoint> = []

    private(set) var statuses: [String: WorkflowNodeStatus] = [:]
    private(set) var nodeOutputs: [String: String] = [:]
    private(set) var runPhase: WorkflowRunPhase = .idle

    /// Problems commons found in the stored shape, and problems only the editor
    /// can see — a required tool argument with neither a wire nor a literal is
    /// invisible to the validator, which cannot know what the host registry
    /// expects to receive.
    private(set) var remoteIssues: [WorkflowIssue] = []
    private(set) var localIssues: [WorkflowIssue] = []

    var issues: [WorkflowIssue] { localIssues + remoteIssues }

    private(set) var savedWorkflows: [RAWorkflowSummary] = []
    private(set) var availableModels: [ModelInfo] = []
    private(set) var availableTools: [ToolDefinition] = []

    /// Installed node packs and the bundle import/export flows. Held apart from
    /// the graph because none of it depends on which workflow is open.
    let packStore = WorkflowPackStore()

    var errorMessage: String?

    private(set) var canUndo = false
    private(set) var canRedo = false

    @ObservationIgnored weak var undoManager: UndoManager? {
        didSet { refreshUndoState() }
    }

    @ObservationIgnored private var createdAtMs: Int64
    @ObservationIgnored private var dragSession: (origins: [String: CGPoint], before: WorkflowGraph)?
    @ObservationIgnored private var coalesceKey: String?
    @ObservationIgnored private var coalesceDeadline = Date.distantPast
    @ObservationIgnored private var validationTask: Task<Void, Never>?
    @ObservationIgnored private var runEventTask: Task<Void, Never>?
    @ObservationIgnored private var activeRun: WorkflowRun?
    @ObservationIgnored private var runStartDate: Date?

    init() {
        workflowID = Self.freshWorkflowID()
        workflowName = "Untitled workflow"
        createdAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        seedTrigger()
    }

    var isRunning: Bool {
        if case .running = runPhase { return true }
        return false
    }

    var singleSelectedNode: WorkflowNode? {
        guard selectedNodeIDs.count == 1, let id = selectedNodeIDs.first else { return nil }
        return graph.node(id)
    }

    func status(of nodeID: String) -> WorkflowNodeStatus {
        statuses[nodeID] ?? .idle
    }

    func issues(for nodeID: String) -> [WorkflowIssue] {
        issues.filter { $0.nodeID == nodeID }
    }

    /// Cards highlight per node, snapping resolves per port.
    var draftCandidateNodes: Set<String> {
        Set(draftCandidates.map(\.nodeID))
    }

    // MARK: - Undoable mutation

    /// Apply an edit, and make it undoable only if it changed anything.
    func mutate(_ body: (inout WorkflowGraph) -> Void) {
        let before = graph
        body(&graph)
        graph.pruneDanglingEdges()
        guard graph != before else { return }
        coalesceKey = nil
        registerUndo(restoring: before)
        scheduleValidation()
    }

    /// Inspector edits funnel through here. Consecutive edits to the same
    /// field within the window share one undo step, so undoing a typed
    /// sentence is one ⌘Z rather than one per keystroke.
    func updateNode(_ id: String, coalescing field: String, _ body: (inout WorkflowNode) -> Void) {
        guard let index = graph.nodeIndex(id) else { return }
        let before = graph
        body(&graph.nodes[index])
        graph.pruneDanglingEdges()
        guard graph != before else { return }
        scheduleValidation()

        let key = "\(id).\(field)"
        let now = Date()
        if coalesceKey == key, now < coalesceDeadline {
            coalesceDeadline = now.addingTimeInterval(2)
            return
        }
        coalesceKey = key
        coalesceDeadline = now.addingTimeInterval(2)
        registerUndo(restoring: before)
    }

    private func registerUndo(restoring snapshot: WorkflowGraph) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                let current = target.graph
                target.graph = snapshot
                target.coalesceKey = nil
                target.pruneSelection()
                target.registerUndo(restoring: current)
                target.scheduleValidation()
            }
        }
        refreshUndoState()
    }

    func undo() {
        undoManager?.undo()
        refreshUndoState()
    }

    func redo() {
        undoManager?.redo()
        refreshUndoState()
    }

    private func refreshUndoState() {
        canUndo = undoManager?.canUndo ?? false
        canRedo = undoManager?.canRedo ?? false
    }

    private func pruneSelection() {
        selectedNodeIDs = selectedNodeIDs.filter { id in graph.node(id) != nil }
        if let edgeID = selectedEdgeID, !graph.edges.contains(where: { $0.id == edgeID }) {
            selectedEdgeID = nil
        }
    }

    // MARK: - Node editing

    @discardableResult
    func addNode(_ kind: WorkflowNodeKind, at position: CGPoint) -> WorkflowNode? {
        if kind.isTrigger, graph.nodes.contains(where: { $0.kind.isTrigger }) {
            errorMessage = "A workflow has exactly one trigger, and this one already has it. " +
                "Delete the current trigger to swap it for another."
            return nil
        }
        let node = WorkflowNode(
            kind: kind,
            name: graph.uniqueName(for: kind),
            position: WorkflowCanvasMetrics.snapToGrid(position)
        )
        mutate { $0.nodes.append(node) }
        selectedNodeIDs = [node.id]
        selectedEdgeID = nil
        return node
    }

    func deleteSelection() {
        if let edgeID = selectedEdgeID {
            selectedEdgeID = nil
            mutate { graph in graph.edges.removeAll { $0.id == edgeID } }
            return
        }
        guard !selectedNodeIDs.isEmpty else { return }
        let ids = selectedNodeIDs
        selectedNodeIDs = []
        mutate { graph in
            graph.nodes.removeAll { ids.contains($0.id) }
            graph.edges.removeAll { ids.contains($0.fromNode) || ids.contains($0.toNode) }
            for index in graph.nodes.indices {
                graph.nodes[index].settings.loopBodyNodeIDs.removeAll { ids.contains($0) }
            }
        }
    }

    func duplicateSelection() {
        let originals = graph.nodes.filter {
            selectedNodeIDs.contains($0.id) && !$0.kind.isTrigger
        }
        guard !originals.isEmpty else { return }

        var idMap: [String: String] = [:]
        var copies: [WorkflowNode] = []
        var working = graph
        for original in originals {
            var copy = WorkflowNode(
                kind: original.kind,
                name: working.uniqueName(basedOn: original.name),
                position: CGPoint(x: original.position.x + 32, y: original.position.y + 32)
            )
            copy.settings = original.settings
            copy.settings.loopBodyNodeIDs = []
            idMap[original.id] = copy.id
            copies.append(copy)
            working.nodes.append(copy)
        }
        let internalEdges = graph.edges.compactMap { edge -> WorkflowEdge? in
            guard let from = idMap[edge.fromNode], let to = idMap[edge.toNode] else { return nil }
            return WorkflowEdge(
                fromNode: from, fromPort: edge.fromPort, toNode: to, toPort: edge.toPort
            )
        }
        mutate { graph in
            graph.nodes.append(contentsOf: copies)
            graph.edges.append(contentsOf: internalEdges)
        }
        selectedNodeIDs = Set(copies.map(\.id))
        selectedEdgeID = nil
    }

    // MARK: - Node dragging

    /// First drag event: capture every selected node's start position. Frames
    /// after that compute `start + translation`, never `current + translation` —
    /// translation is cumulative from the drag start, so adding it to a
    /// position that already moved compounds and the node flies off.
    func beginNodeDrag(anchor nodeID: String) {
        guard dragSession == nil else { return }
        if !selectedNodeIDs.contains(nodeID) {
            selectedNodeIDs = [nodeID]
            selectedEdgeID = nil
        }
        var origins: [String: CGPoint] = [:]
        for node in graph.nodes where selectedNodeIDs.contains(node.id) {
            origins[node.id] = node.position
        }
        dragSession = (origins, graph)
    }

    func dragSelection(by delta: CGSize) {
        guard let session = dragSession else { return }
        for (id, origin) in session.origins {
            guard let index = graph.nodeIndex(id) else { continue }
            graph.nodes[index].position = WorkflowCanvasMetrics.snapToGrid(
                CGPoint(x: origin.x + delta.width, y: origin.y + delta.height)
            )
        }
    }

    func endNodeDrag() {
        guard let session = dragSession else { return }
        dragSession = nil
        guard graph != session.before else { return }
        coalesceKey = nil
        registerUndo(restoring: session.before)
        scheduleValidation()
    }

    // MARK: - Connecting

    func updateDraft(
        from nodeID: String,
        port: WorkflowOutputPort,
        cursor: CGPoint,
        snapDistance: CGFloat
    ) {
        if draft == nil || draft?.fromNode != nodeID || draft?.fromPort != port {
            draftCandidates = validTargets(from: nodeID, port: port)
        }
        var snapped: WorkflowEndpoint?
        var best = snapDistance
        for endpoint in draftCandidates {
            guard let target = graph.node(endpoint.nodeID),
                  let anchor = WorkflowCanvasMetrics.inputAnchor(of: target, port: endpoint.port)
            else { continue }
            let distance = hypot(anchor.x - cursor.x, anchor.y - cursor.y)
            if distance <= best {
                best = distance
                snapped = endpoint
            }
        }
        draft = WorkflowDraftConnection(
            fromNode: nodeID, fromPort: port, cursor: cursor, snappedTarget: snapped
        )
    }

    /// Sockets the rope may land on: no self-loops, no duplicate edges, no node
    /// without an input, and nothing that would close a cycle — the same rules
    /// commons enforces at save, applied before the edge can exist.
    private func validTargets(
        from nodeID: String, port: WorkflowOutputPort
    ) -> Set<WorkflowEndpoint> {
        var targets: Set<WorkflowEndpoint> = []
        for node in graph.nodes where node.id != nodeID {
            guard !graph.createsCycle(from: nodeID, to: node.id) else { continue }
            for input in node.inputPorts {
                let endpoint = WorkflowEndpoint(nodeID: node.id, port: input.name)
                guard !graph.hasEdge(from: nodeID, port: port, to: endpoint) else { continue }
                targets.insert(endpoint)
            }
        }
        return targets
    }

    func completeDraft() {
        defer {
            draft = nil
            draftCandidates = []
        }
        guard let draft, let target = draft.snappedTarget else { return }
        let edge = WorkflowEdge(
            fromNode: draft.fromNode,
            fromPort: draft.fromPort,
            toNode: target.nodeID,
            toPort: target.port
        )
        mutate { $0.edges.append(edge) }
    }

    func cancelDraft() {
        draft = nil
        draftCandidates = []
    }

    func deleteEdge(_ edgeID: String) {
        if selectedEdgeID == edgeID { selectedEdgeID = nil }
        mutate { graph in graph.edges.removeAll { $0.id == edgeID } }
    }

    // MARK: - Persistence

    func save() async {
        errorMessage = nil
        do {
            try await RunAnywhere.workflows.save(document)
            await refreshLibrary()
            await WorkflowScheduler.shared.reload()
        } catch {
            errorMessage = error.localizedDescription
            scheduleValidation()
        }
    }

    /// A failed listing leaves the library section empty rather than raising
    /// an alert — it also runs at first appearance, before anything is stored.
    func refreshLibrary() async {
        if let workflows = try? await RunAnywhere.workflows.list() {
            savedWorkflows = workflows
        }
    }

    /// The pickers' source data. Failure leaves them empty rather than
    /// blocking the editor.
    func refreshCatalogs() async {
        availableModels = (try? await RunAnywhere.models.list(
            filter: ModelFilter(downloadedOnly: true)
        )) ?? []
        availableTools = await RunAnywhere.llm.tools.list()
        await refreshPacks()
        backfillToolPorts()
    }

    /// A tool node saved before its argument list travelled in the document has
    /// no ports to draw. Filling them in from the registry is reconciliation,
    /// not an edit, so it takes no undo step.
    private func backfillToolPorts() {
        var changed = false
        for index in graph.nodes.indices {
            let node = graph.nodes[index]
            guard node.kind == .toolCall,
                  node.settings.toolPorts.isEmpty,
                  !node.settings.toolName.isEmpty,
                  let tool = availableTools.first(where: { $0.name == node.settings.toolName })
            else { continue }
            let ports = WorkflowToolPort.ports(of: tool)
            guard !ports.isEmpty else { continue }
            graph.nodes[index].settings.toolPorts = ports
            changed = true
        }
        guard changed else { return }
        scheduleValidation()
    }

    func models(for category: RAModelCategory) -> [ModelInfo] {
        availableModels.filter { $0.category == category }
    }

    // MARK: - Node packs

    func refreshPacks() async {
        await packStore.refresh()
        reconcilePackNodes()
    }

    /// Bring every pack node back in line with what is installed: re-mirror the
    /// declared ports and outputs, and flag the ones whose pack is gone. Like
    /// `backfillToolPorts`, this is reconciliation and takes no undo step.
    ///
    /// Lives here rather than in the packs extension because it writes `graph`,
    /// whose setter is private to this file.
    func reconcilePackNodes() {
        var changed = false
        for index in graph.nodes.indices where graph.nodes[index].kind == .packNode {
            let pack = packStore.pack(graph.nodes[index].settings.packID)
            if WorkflowPackCatalog.reconcile(&graph.nodes[index].settings, against: pack) {
                changed = true
            }
        }
        guard changed else { return }
        graph.pruneDanglingEdges()
        scheduleValidation()
    }

    func load(id: String) async {
        errorMessage = nil
        do {
            let loaded = try await RunAnywhere.workflows.load(id: id)
            workflowID = loaded.id
            workflowName = loaded.name
            createdAtMs = loaded.createdAtMs
            graph = WorkflowDocumentMapping.graph(from: loaded)
            reconcilePackNodes()
            resetEditorState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(id: String) async {
        do {
            try await RunAnywhere.workflows.delete(id: id)
            await refreshLibrary()
            await WorkflowScheduler.shared.reload()
            if id == workflowID { newWorkflow() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func newWorkflow() {
        workflowID = Self.freshWorkflowID()
        workflowName = "Untitled workflow"
        createdAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        graph = WorkflowGraph()
        seedTrigger()
        resetEditorState()
    }

    /// Commons requires exactly one trigger, so an empty canvas starts with it
    /// placed rather than asking the user to discover the rule.
    private func seedTrigger() {
        let trigger = WorkflowNode(
            kind: .manualTrigger,
            name: WorkflowNodeKind.manualTrigger.title,
            position: CGPoint(x: 96, y: 160)
        )
        graph.nodes.append(trigger)
    }

    private func resetEditorState() {
        selectedNodeIDs = []
        selectedEdgeID = nil
        statuses = [:]
        nodeOutputs = [:]
        localIssues = []
        remoteIssues = []
        runPhase = .idle
        coalesceKey = nil
        undoManager?.removeAllActions(withTarget: self)
        refreshUndoState()
        scheduleValidation()
    }

    private static func freshWorkflowID() -> String {
        "wf-" + UUID().uuidString.prefix(8).lowercased()
    }
}

// MARK: - Validation and tool arguments

extension WorkflowEditorViewModel {
    private var document: RAWorkflowDocument {
        WorkflowDocumentMapping.document(
            id: workflowID, name: workflowName, graph: graph, createdAtMs: createdAtMs
        )
    }

    func scheduleValidation() {
        validationTask?.cancel()
        recomputeLocalIssues()
        guard !graph.nodes.isEmpty else {
            remoteIssues = []
            return
        }
        let snapshot = document
        validationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            guard let result = try? await RunAnywhere.workflows.validate(snapshot) else { return }
            guard !Task.isCancelled else { return }
            self?.remoteIssues = result.issues.map {
                WorkflowIssue(message: $0.message, nodeID: $0.hasNodeID ? $0.nodeID : nil)
            }
        }
    }

    private func recomputeLocalIssues() {
        var found: [WorkflowIssue] = []
        for node in graph.nodes where node.kind == .toolCall {
            for port in node.settings.toolPorts where port.required {
                let wired = graph.isInputConnected(node.id, port: port.name)
                let literal = !node.settings.toolArgument(port.name).isEmpty
                guard !wired, !literal else { continue }
                found.append(WorkflowIssue(
                    message: "'\(port.name)' is required: connect it or type a value",
                    nodeID: node.id
                ))
            }
        }
        localIssues = found
    }

    // MARK: - Tool arguments

    /// Picking a tool reshapes the node: its declared arguments become input
    /// sockets, and the ports travel in the document so the shape survives on a
    /// machine where the tool is not registered.
    func selectTool(named name: String, for nodeID: String) {
        let ports = availableTools.first { $0.name == name }
            .map(WorkflowToolPort.ports(of:)) ?? []
        updateNode(nodeID, coalescing: "toolName") { node in
            node.settings.toolName = name
            node.settings.toolPorts = ports
        }
    }

    func toolArgumentState(_ node: WorkflowNode, port: WorkflowToolPort) -> WorkflowArgumentState {
        if graph.isInputConnected(node.id, port: port.name) { return .wired }
        if !node.settings.toolArgument(port.name).isEmpty { return .literal }
        return port.required ? .missing : .unset
    }
}

// MARK: - Running

extension WorkflowEditorViewModel {
    func run() async {
        guard !isRunning else { return }
        errorMessage = nil
        statuses = [:]
        nodeOutputs = [:]

        // The runner executes what is stored, so an unsaved edit would
        // otherwise silently run the previous version.
        await save()
        guard errorMessage == nil else { return }

        do {
            let run = try await RunAnywhere.workflows.run(workflowID: workflowID)
            activeRun = run
            runStartDate = Date()
            runPhase = .running(startedAt: runStartDate ?? Date())

            runEventTask = Task { [weak self] in
                for await event in run.events {
                    self?.apply(event)
                }
                self?.finishRun()
            }

            try run.start()
        } catch {
            runPhase = .idle
            activeRun?.destroy()
            activeRun = nil
            errorMessage = error.localizedDescription
        }
    }

    func cancelRun() {
        try? activeRun?.cancel()
    }

    private func apply(_ event: RAWorkflowRunEvent) {
        switch event.event {
        case .runStarted:
            break
        case .nodeStateChanged(let change):
            statuses[change.nodeID] = nodeStatus(for: change)
            if !change.output.isEmpty {
                nodeOutputs[change.nodeID] = change.output.map(\.json).joined(separator: "\n")
            }
        case .runFinished(let finished):
            let duration = runStartDate.map { Date().timeIntervalSince($0) } ?? 0
            runPhase = .finished(finished.state, duration: duration)
            if finished.state == .failed, finished.hasError, errorMessage == nil {
                errorMessage = finished.error.message
            }
        case .none:
            break
        }
    }

    private func nodeStatus(for change: RANodeStateChanged) -> WorkflowNodeStatus {
        switch change.state {
        case .running: return .running
        case .succeeded: return .succeeded
        case .skipped: return .skipped
        case .failed:
            return .failed(message: change.hasError ? change.error.message : "Node failed")
        case .pending, .unspecified, .UNRECOGNIZED: return .idle
        }
    }

    private func finishRun() {
        if case .running = runPhase {
            runPhase = .finished(.cancelled, duration: runStartDate.map {
                Date().timeIntervalSince($0)
            } ?? 0)
        }
        runEventTask = nil
        activeRun?.destroy()
        activeRun = nil
        runStartDate = nil
    }
}
