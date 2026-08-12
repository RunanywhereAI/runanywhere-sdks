//
//  WorkflowGraph.swift
//  RunAnywhereAI
//
//  The editor's value-type view of a workflow. The SDK's RAWorkflowDocument is
//  the stored shape; this graph is what the canvas draws and mutates. Value
//  semantics are the point: undo/redo is a snapshot of this struct, and
//  equality is what decides whether an edit is worth an undo step.
//

import Foundation
import RunAnywhere
import SwiftUI

struct WorkflowNode: Identifiable, Equatable {
    let id: String
    var kind: WorkflowNodeKind
    var name: String
    var position: CGPoint
    var settings = WorkflowNodeSettings()

    init(
        id: String = "node-" + UUID().uuidString.prefix(8).lowercased(),
        kind: WorkflowNodeKind,
        name: String,
        position: CGPoint
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.position = position
    }

    /// Mirrors `ports_for()` in workflow_validator.cpp. Triggers have none,
    /// Merge numbers its own and drops "in" entirely, and a Tool or Pack node
    /// keeps "in" and adds one port per declared argument.
    var inputPorts: [WorkflowInputPort] {
        switch kind {
        case .manualTrigger, .scheduleTrigger:
            return []
        case .merge:
            let count = max(1, settings.mergeInputCount)
            return (1...count).map { .flow("in\($0)") }
        case .toolCall, .packNode:
            return [.flow()] + settings.toolPorts.map {
                WorkflowInputPort(name: $0.name, role: .argument(required: $0.required))
            }
        default:
            return [.flow()]
        }
    }

    /// A pack declares its own outputs and mirrors them into the document at
    /// drop time; every other kind's outputs come from its type alone.
    ///
    /// Deduplicated because the names come from a file someone else wrote: two
    /// sockets with one name would collide as ForEach identities and give the
    /// canvas two anchors for the same port.
    var outputPorts: [WorkflowOutputPort] {
        guard kind == .packNode else { return kind.outputPorts }
        var seen: Set<String> = []
        let declared = settings.packOutputs
            .compactMap(WorkflowOutputPort.init(rawValue:))
            .filter { seen.insert($0.rawValue).inserted }
        return declared.isEmpty ? [.out] : declared
    }

    var argumentPorts: [WorkflowToolPort] {
        switch kind {
        case .toolCall, .packNode: return settings.toolPorts
        default: return []
        }
    }
}

/// A socket on a node, either end of a connection.
struct WorkflowEndpoint: Equatable, Hashable {
    var nodeID: String
    var port: String
}

struct WorkflowEdge: Identifiable, Hashable {
    var fromNode: String
    var fromPort: WorkflowOutputPort
    var toNode: String
    var toPort: String = WorkflowInputPort.flowName

    /// Identity is the quadruple itself; duplicates are invalid, so no UUID is
    /// needed and undo snapshots keep stable ids for free.
    var id: String { "\(fromNode)/\(fromPort.rawValue)→\(toNode)/\(toPort)" }
}

struct WorkflowGraph: Equatable {
    var nodes: [WorkflowNode] = []
    var edges: [WorkflowEdge] = []

    func node(_ id: String) -> WorkflowNode? {
        nodes.first { $0.id == id }
    }

    func nodeIndex(_ id: String) -> Int? {
        nodes.firstIndex { $0.id == id }
    }

    func hasEdge(from nodeID: String, port: WorkflowOutputPort, to target: WorkflowEndpoint) -> Bool {
        edges.contains {
            $0.fromNode == nodeID && $0.fromPort == port
                && $0.toNode == target.nodeID && $0.toPort == target.port
        }
    }

    func isInputConnected(_ nodeID: String, port: String) -> Bool {
        edges.contains { $0.toNode == nodeID && $0.toPort == port }
    }

    func isOutputConnected(_ nodeID: String, port: WorkflowOutputPort) -> Bool {
        edges.contains { $0.fromNode == nodeID && $0.fromPort == port }
    }

    /// Whether adding from→to would close a cycle, i.e. `from` is already
    /// reachable by walking forward from `to`. Commons rejects cycles at save;
    /// the canvas refuses to draw one in the first place.
    func createsCycle(from sourceID: String, to targetID: String) -> Bool {
        var visited: Set<String> = []
        var frontier = [targetID]
        while let current = frontier.popLast() {
            if current == sourceID { return true }
            guard visited.insert(current).inserted else { continue }
            frontier.append(contentsOf: edges.filter { $0.fromNode == current }.map(\.toNode))
        }
        return false
    }

    /// Names address nodes in `{{ Node Name.field }}` expressions, so a
    /// collision is a semantic error, not a cosmetic one.
    func uniqueName(for kind: WorkflowNodeKind) -> String {
        uniqueName(basedOn: kind.title)
    }

    func uniqueName(basedOn base: String) -> String {
        var candidate = base
        var counter = 2
        while nodes.contains(where: { $0.name == candidate }) {
            candidate = "\(base) \(counter)"
            counter += 1
        }
        return candidate
    }

    /// Drop edges whose ports no longer exist — what a shrinking Merge, a
    /// re-chosen tool, or a pack that changed its declared shape leaves behind.
    /// Both ends are checked: commons rejects an edge naming an undeclared port
    /// at either end, and a pack's outputs can change under a placed node.
    mutating func pruneDanglingEdges() {
        var inputs: [String: Set<String>] = [:]
        var outputs: [String: Set<String>] = [:]
        for node in nodes {
            inputs[node.id] = Set(node.inputPorts.map(\.name))
            outputs[node.id] = Set(node.outputPorts.map(\.rawValue))
        }
        edges.removeAll { edge in
            inputs[edge.toNode]?.contains(edge.toPort) != true
                || outputs[edge.fromNode]?.contains(edge.fromPort.rawValue) != true
        }
    }

    /// Bounding rectangle of every card in graph space, for fit-to-content.
    func boundingRect() -> CGRect? {
        guard let first = nodes.first else { return nil }
        var rect = WorkflowCanvasMetrics.cardFrame(of: first)
        for node in nodes.dropFirst() {
            rect = rect.union(WorkflowCanvasMetrics.cardFrame(of: node))
        }
        return rect
    }
}

// MARK: - Card summaries

extension WorkflowNode {
    /// One line of live configuration under the node name on the card.
    var parameterSummary: String {
        if kind == .packNode { return packSummary }
        switch kind.category {
        case .trigger: return triggerSummary
        case .ai: return aiSummary
        case .speech: return speechSummary
        case .knowledge: return knowledgeSummary
        case .models: return settings.modelID.isEmpty ? "Choose a model" : settings.modelID
        case .logic: return logicSummary
        case .integration: return integrationSummary
        }
    }

    private var packSummary: String {
        if settings.packMissing {
            return "Pack \(settings.packID) is not installed"
        }
        let count = settings.toolPorts.count
        return count == 0 ? "No inputs" : "\(count) input\(count == 1 ? "" : "s")"
    }

    private var triggerSummary: String {
        guard kind == .scheduleTrigger else {
            return settings.triggerItemsJSON.isEmpty ? "Starts the run" : "Starts with seed items"
        }
        switch settings.scheduleKind {
        case .daily:
            return String(format: "Every day at %02d:%02d", settings.scheduleHour, settings.scheduleMinute)
        case .cron:
            return settings.scheduleCron.isEmpty ? "Set a cron expression" : settings.scheduleCron
        case .interval, .unspecified, .UNRECOGNIZED:
            return "Every \(WorkflowScheduleFormat.interval(seconds: settings.scheduleIntervalSeconds))"
        }
    }

    private var aiSummary: String {
        let model = settings.modelID.isEmpty ? "auto model" : settings.modelID
        switch kind {
        case .llmGenerate, .llmStructured, .vision:
            return settings.prompt.isEmpty ? "Write a prompt" : "\(model) · \(settings.prompt)"
        case .embed:
            return settings.textInput.isEmpty ? "Choose text to embed" : settings.textInput
        case .rerank:
            return settings.rerankQuery.isEmpty ? "Set a query" : settings.rerankQuery
        default:
            return model
        }
    }

    private var speechSummary: String {
        switch kind {
        case .speak:
            return settings.textInput.isEmpty ? "Write what to say" : settings.textInput
        case .segment:
            return settings.textInput.isEmpty ? "Choose text to segment" : settings.textInput
        default:
            return settings.binaryKey.isEmpty ? "Set the audio attachment" : settings.binaryKey
        }
    }

    private var knowledgeSummary: String {
        switch kind {
        case .ragQuery:
            return settings.ragQuestion.isEmpty ? "Ask a question" : settings.ragQuestion
        default:
            return settings.textInput.isEmpty ? "Choose text to ingest" : settings.textInput
        }
    }

    private var logicSummary: String {
        switch kind {
        case .condition, .filter:
            if settings.conditionLeft.isEmpty { return "Set a test" }
            return "\(settings.conditionLeft) \(settings.conditionOperator.symbol) \(settings.conditionRight)"
        case .loopOverItems:
            return settings.loopItems.isEmpty ? "Choose a list" : settings.loopItems
        case .code:
            let firstLine = settings.codeSource
                .split(separator: "\n", omittingEmptySubsequences: true).first
            return firstLine.map(String.init) ?? "JavaScript"
        case .setTransform:
            let count = settings.assignments.count
            return count == 0 ? "No fields yet" : "\(count) field\(count == 1 ? "" : "s")"
        case .merge:
            return "\(max(1, settings.mergeInputCount)) branches in"
        case .wait:
            return "Pause \(WorkflowScheduleFormat.interval(seconds: settings.waitSeconds))"
        default:
            return settings.fieldPath.isEmpty ? "Choose a field" : settings.fieldPath
        }
    }

    private var integrationSummary: String {
        switch kind {
        case .toolCall:
            return settings.toolName.isEmpty ? "Choose a tool" : settings.toolName
        case .httpRequest:
            if settings.httpURL.isEmpty { return "Set a URL" }
            return "\(settings.httpMethod.label) \(settings.httpURL)"
        default:
            return settings.filePath.isEmpty ? "Set a path" : settings.filePath
        }
    }
}

// MARK: - Canvas geometry

/// Card and socket geometry, shared by layout, hit areas, and edge anchors so
/// the three can never disagree.
///
/// A card is a header, a details band, and — only for a node with more than one
/// input — a rail of labelled argument rows underneath. Outputs stay centred on
/// the details band whatever the rail does, so a tool node's main flow keeps the
/// same shape as every other node's.
enum WorkflowCanvasMetrics {
    static let cardWidth: CGFloat = 240
    static let headerHeight: CGFloat = 34
    static let detailsHeight: CGFloat = 70
    static let portRowHeight: CGFloat = 24
    static let railTopPadding: CGFloat = 4
    static let railBottomPadding: CGFloat = 8

    /// Placement geometry, before a node exists to measure.
    static let defaultCardSize = CGSize(width: cardWidth, height: headerHeight + detailsHeight)

    /// Horizontal slack each side of the card, part of the node's own frame.
    /// Sockets sit inside this slack — never in an overlay outside the frame,
    /// which SwiftUI would render but refuse to hit-test.
    static let socketMargin: CGFloat = 18
    static let socketDiameter: CGFloat = 14
    /// Vertical offset of Condition's two output sockets from the details centre.
    static let portRowOffset: CGFloat = 15
    /// Snap distance for a dragged rope, in view points; divide by the zoom
    /// before comparing in graph space.
    static let snapRadius: CGFloat = 32
    static let minZoom: CGFloat = 0.25
    static let maxZoom: CGFloat = 2.0
    static let gridStep: CGFloat = 8

    /// The details band grows only when a node has enough outputs that the
    /// sockets spread beyond it — a pack declaring several. Every socket has to
    /// stay inside the card it belongs to, or it renders over the neighbour
    /// below and grabs nothing.
    static func detailsHeight(of node: WorkflowNode) -> CGFloat {
        let outputs = node.outputPorts.count
        guard outputs > 1 else { return detailsHeight }
        let spread = CGFloat(outputs - 1) * portRowOffset * 2
        return max(detailsHeight, spread + portRowHeight + railTopPadding * 2)
    }

    static func detailsCenterY(of node: WorkflowNode) -> CGFloat {
        headerHeight + detailsHeight(of: node) / 2
    }

    static func hasRail(_ node: WorkflowNode) -> Bool {
        node.inputPorts.count > 1
    }

    static func railHeight(_ node: WorkflowNode) -> CGFloat {
        guard hasRail(node) else { return 0 }
        return railTopPadding + CGFloat(node.inputPorts.count) * portRowHeight + railBottomPadding
    }

    static func cardSize(of node: WorkflowNode) -> CGSize {
        CGSize(
            width: cardWidth,
            height: headerHeight + detailsHeight(of: node) + railHeight(node)
        )
    }

    static func cardFrame(of node: WorkflowNode) -> CGRect {
        CGRect(origin: node.position, size: cardSize(of: node))
    }

    /// Vertical centre of an input socket inside the card. A lone input sits on
    /// the details band; a rail stacks them one row apart underneath it.
    static func inputOffsetY(of node: WorkflowNode, port: String) -> CGFloat? {
        guard let index = node.inputPorts.firstIndex(where: { $0.name == port }) else { return nil }
        guard hasRail(node) else { return detailsCenterY(of: node) }
        return headerHeight + detailsHeight(of: node) + railTopPadding
            + CGFloat(index) * portRowHeight + portRowHeight / 2
    }

    static func inputAnchor(of node: WorkflowNode, port: String) -> CGPoint? {
        guard let offset = inputOffsetY(of: node, port: port) else { return nil }
        return CGPoint(x: node.position.x, y: node.position.y + offset)
    }

    /// Outputs spread evenly about the details centre, so a single output stays
    /// centred and Condition's two land exactly where they always did.
    static func outputOffsetY(of node: WorkflowNode, port: WorkflowOutputPort) -> CGFloat {
        let ports = node.outputPorts
        let center = detailsCenterY(of: node)
        guard ports.count > 1, let index = ports.firstIndex(of: port) else { return center }
        let spread = CGFloat(ports.count - 1) * portRowOffset * 2
        return center - spread / 2 + CGFloat(index) * portRowOffset * 2
    }

    static func outputAnchor(of node: WorkflowNode, port: WorkflowOutputPort) -> CGPoint {
        CGPoint(
            x: node.position.x + cardWidth,
            y: node.position.y + outputOffsetY(of: node, port: port)
        )
    }

    static func snapToGrid(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x / gridStep).rounded() * gridStep,
            y: (point.y / gridStep).rounded() * gridStep
        )
    }
}

// MARK: - Run state

enum WorkflowNodeStatus: Equatable {
    case idle
    case running
    case succeeded
    case failed(message: String)
    case skipped

    var tint: Color {
        switch self {
        case .idle: return AppColors.mutedForeground
        case .running: return AppColors.brand
        case .succeeded: return AppColors.success
        case .failed: return AppColors.danger
        case .skipped: return AppColors.mutedForeground
        }
    }
}

enum WorkflowRunPhase: Equatable {
    case idle
    case running(startedAt: Date)
    case finished(RAWorkflowRunState, duration: TimeInterval)
}

struct WorkflowIssue: Identifiable, Equatable {
    let message: String
    let nodeID: String?

    /// Deterministic, so a re-validation that finds the same problems does
    /// not read as a fresh set to ForEach and animation.
    var id: String { (nodeID ?? "workflow") + "|" + message }
}

/// A rope dragged out of an output socket but not yet dropped. Coordinates are
/// graph space so zoom and pan never have to be undone by readers.
struct WorkflowDraftConnection: Equatable {
    var fromNode: String
    var fromPort: WorkflowOutputPort
    var cursor: CGPoint
    /// The input the rope will land on if released now. Drives the rope's snap
    /// and the target card's highlight from one value, so they cannot disagree.
    var snappedTarget: WorkflowEndpoint?
}

// MARK: - Proto display helpers

enum WorkflowScheduleFormat {
    static func interval(seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds.isMultiple(of: 3600), seconds >= 3600 {
            let hours = seconds / 3600
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        if seconds.isMultiple(of: 60), seconds >= 60 {
            let minutes = seconds / 60
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        return "\(seconds) second\(seconds == 1 ? "" : "s")"
    }
}

extension RAComparisonOperator {
    var label: String {
        switch self {
        case .equals: return "equals"
        case .notEquals: return "does not equal"
        case .contains: return "contains"
        case .greaterThan: return "is greater than"
        case .lessThan: return "is less than"
        case .isEmpty: return "is empty"
        case .unspecified, .UNRECOGNIZED: return "—"
        }
    }

    var symbol: String {
        switch self {
        case .equals: return "="
        case .notEquals: return "≠"
        case .contains: return "∋"
        case .greaterThan: return ">"
        case .lessThan: return "<"
        case .isEmpty: return "is empty"
        case .unspecified, .UNRECOGNIZED: return "?"
        }
    }

    static let selectable: [RAComparisonOperator] = [
        .equals, .notEquals, .contains, .greaterThan, .lessThan, .isEmpty
    ]
}

extension RAHttpMethod {
    var label: String {
        switch self {
        case .get: return "GET"
        case .post: return "POST"
        case .put: return "PUT"
        case .patch: return "PATCH"
        case .delete: return "DELETE"
        case .unspecified, .UNRECOGNIZED: return "—"
        }
    }

    static let selectable: [RAHttpMethod] = [.get, .post, .put, .patch, .delete]
}

extension RAHttpAuthKind {
    var label: String {
        switch self {
        case .bearer: return "Bearer token"
        case .header: return "Header key"
        case .query: return "Query parameter"
        case .unspecified, .UNRECOGNIZED: return "—"
        }
    }

    static let selectable: [RAHttpAuthKind] = [.bearer, .header, .query]
}

extension RAScheduleKind {
    var label: String {
        switch self {
        case .interval: return "Every interval"
        case .daily: return "Daily at a time"
        case .cron: return "Cron expression"
        case .unspecified, .UNRECOGNIZED: return "—"
        }
    }

    static let selectable: [RAScheduleKind] = [.interval, .daily, .cron]
}

extension RAModelCategory {
    var workflowLabel: String {
        switch self {
        case .language: return "Language"
        case .speechRecognition: return "Speech recognition"
        case .speechSynthesis: return "Speech synthesis"
        case .vision: return "Vision"
        case .multimodal: return "Multimodal"
        case .embedding: return "Embedding"
        case .voiceActivityDetection: return "Voice activity"
        case .speakerDiarization: return "Diarization"
        case .semanticSegmentation: return "Segmentation"
        case .rerank: return "Rerank"
        case .audio: return "Audio"
        case .imageGeneration: return "Image generation"
        case .unspecified, .UNRECOGNIZED: return "—"
        }
    }

    static let workflowSelectable: [RAModelCategory] = [
        .language, .speechRecognition, .speechSynthesis, .vision, .multimodal,
        .embedding, .voiceActivityDetection, .speakerDiarization, .semanticSegmentation, .rerank
    ]
}
