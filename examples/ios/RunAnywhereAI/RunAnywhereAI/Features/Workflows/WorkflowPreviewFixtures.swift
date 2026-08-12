//
//  WorkflowPreviewFixtures.swift
//  RunAnywhereAI
//
//  Graphs for previews. Nobody can click a Mac canvas in review, so the shapes
//  that are easy to get wrong — a tool node grown by its arguments, a Merge
//  with numbered inputs, a branching Condition — are worth rendering statically.
//
//  Plain values only: a fixture that reaches through the view model inherits
//  its actor isolation and its SDK calls, and then breaks for reasons that have
//  nothing to do with the layout being previewed.
//

#if DEBUG

import Foundation
import RunAnywhere

enum WorkflowPreviewFixtures {
    static let installedPackID = "digest-composer"
    static let absentPackID = "weather-summary"

    /// A composite pack with two declared inputs and two named outputs — the
    /// shape that grows the details band and needs a caption per socket.
    static var installedPack: RANodePack {
        var pack = RANodePack()
        pack.id = installedPackID
        pack.name = "Digest Composer"
        pack.description_p = "Turns a list of items into one summary paragraph."
        pack.author = "RunAnywhere"
        pack.version = "1.2.0"
        pack.category = WorkflowNodeCategory.knowledge.rawValue
        pack.icon = "text.append"
        pack.accentRgb = WorkflowPackAccent.blue.rawValue
        pack.inputs = [
            WorkflowToolPort(name: "items", summary: "The list to digest", required: true).wire,
            WorkflowToolPort(name: "tone", summary: "Voice to write in").wire
        ]
        pack.outputs = ["digest", "skipped"]
        pack.composite = RACompositeImplementation()
        return pack
    }

    /// Dropped from `installedPack`, then reconciled on a machine without it.
    static func missingPackNode(at position: CGPoint) -> WorkflowNode {
        var node = WorkflowNode(kind: .packNode, name: "Weather Summary", position: position)
        node.settings.packID = absentPackID
        node.settings.toolPorts = [WorkflowToolPort(name: "city", required: true)]
        node.settings.packMissing = true
        return node
    }

    static func packNode(at position: CGPoint) -> WorkflowNode {
        var node = WorkflowNode(kind: .packNode, name: "Digest Composer", position: position)
        node.settings = WorkflowPackCatalog.settings(for: installedPack)
        node.settings.setToolArgument("tone", to: "plain")
        return node
    }

    /// A script pack that asks for real access, which is what the import picker
    /// has to put in front of the user before they take it.
    static var scriptPack: RANodePack {
        var pack = RANodePack()
        pack.id = "slack-poster"
        pack.name = "Slack Poster"
        pack.description_p = "Posts an item to a Slack webhook."
        pack.author = "community"
        pack.version = "0.3.1"
        pack.category = WorkflowNodeCategory.integration.rawValue
        pack.icon = "paperplane.fill"
        pack.accentRgb = WorkflowPackAccent.red.rawValue
        pack.inputs = [WorkflowToolPort(name: "text", required: true).wire]

        var script = RAScriptImplementation()
        script.source = "return items;"
        pack.script = script

        var capabilities = RANodePackCapabilities()
        capabilities.network = true
        capabilities.tools = true
        capabilities.toolNames = ["get_current_time"]
        pack.capabilities = capabilities
        return pack
    }

    /// Two workflows and two packs, one of each kind, so the picker shows both
    /// the pre-selected composite row and the unchecked script row.
    static var importableBundle: RAWorkflowBundle {
        var bundle = RAWorkflowBundle()
        bundle.formatVersion = 1
        bundle.generator = "runanywhere-commons"
        bundle.workflows = [
            WorkflowDocumentMapping.document(
                id: "wf-digest", name: "Daily digest", graph: cardGallery, createdAtMs: 0
            ),
            WorkflowDocumentMapping.document(
                id: "wf-empty", name: "Scratch", graph: WorkflowGraph(), createdAtMs: 0
            )
        ]
        bundle.packs = [installedPack, scriptPack]
        return bundle
    }

    static var partialImportOutcome: WorkflowImportOutcome {
        var issue = RABundleImportIssue()
        issue.kind = .workflow
        issue.id = "wf-broken"
        issue.message = "workflow contains a cycle"
        return WorkflowImportOutcome(
            workflows: ["Daily digest"],
            packs: ["Digest Composer"],
            skipped: [issue],
            declinedPacks: ["Slack Poster"]
        )
    }
    static func toolNode(at position: CGPoint) -> WorkflowNode {
        var node = WorkflowNode(kind: .toolCall, name: "Send notification", position: position)
        node.settings.toolName = "send_notification"
        node.settings.toolPorts = [
            WorkflowToolPort(name: "body", summary: "Message text", required: true),
            WorkflowToolPort(name: "sound", summary: "Alert sound", required: false),
            WorkflowToolPort(name: "title", summary: "Notification title", required: true)
        ]
        node.settings.setToolArgument("title", to: "Joke of the hour")
        return node
    }

    static func mergeNode(at position: CGPoint) -> WorkflowNode {
        var node = WorkflowNode(kind: .merge, name: "Merge", position: position)
        node.settings.mergeInputCount = 3
        return node
    }

    static func scheduleNode(at position: CGPoint) -> WorkflowNode {
        var node = WorkflowNode(kind: .scheduleTrigger, name: "Every hour", position: position)
        node.settings.scheduleKind = .interval
        node.settings.scheduleIntervalSeconds = 3600
        return node
    }

    /// One of each interesting card shape, wired the way the port rules require:
    /// a branch into a named tool argument, and a branch into a numbered Merge
    /// input.
    static var cardGallery: WorkflowGraph {
        var llm = WorkflowNode(kind: .llmGenerate, name: "Write a joke", position: CGPoint(x: 320, y: 40))
        llm.settings.prompt = "Tell me a short programming joke."

        var condition = WorkflowNode(
            kind: .condition, name: "Is it funny", position: CGPoint(x: 600, y: 40)
        )
        condition.settings.conditionLeft = "{{ Write a joke.text }}"
        condition.settings.conditionOperator = .contains
        condition.settings.conditionRight = "why"

        let nodes = [
            scheduleNode(at: CGPoint(x: 40, y: 40)),
            llm,
            condition,
            toolNode(at: CGPoint(x: 880, y: 40)),
            mergeNode(at: CGPoint(x: 600, y: 220)),
            packNode(at: CGPoint(x: 40, y: 300)),
            missingPackNode(at: CGPoint(x: 320, y: 300))
        ]

        var graph = WorkflowGraph()
        graph.nodes = nodes
        graph.edges = [
            WorkflowEdge(fromNode: nodes[0].id, fromPort: .out, toNode: nodes[1].id),
            WorkflowEdge(fromNode: nodes[1].id, fromPort: .out, toNode: nodes[2].id),
            WorkflowEdge(
                fromNode: nodes[2].id, fromPort: .truthy, toNode: nodes[3].id, toPort: "body"
            ),
            WorkflowEdge(
                fromNode: nodes[2].id, fromPort: .falsy, toNode: nodes[4].id, toPort: "in1"
            )
        ]
        if let digest = WorkflowOutputPort(rawValue: "digest") {
            graph.edges.append(
                WorkflowEdge(
                    fromNode: nodes[5].id, fromPort: digest, toNode: nodes[6].id, toPort: "city"
                )
            )
        }
        return graph
    }
}

#endif
