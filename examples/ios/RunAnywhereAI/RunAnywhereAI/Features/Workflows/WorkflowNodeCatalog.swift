//
//  WorkflowNodeCatalog.swift
//  RunAnywhereAI
//
//  One case per config arm in agent_workflow.proto, plus the port names commons
//  validates edges against. `ports_for()` in workflow_validator.cpp is the
//  authority: a socket the canvas draws that commons does not know about
//  produces a graph the backend rejects at save, so the two lists must match
//  exactly.
//

import RunAnywhere
import SwiftUI

enum WorkflowNodeCategory: String, CaseIterable, Identifiable {
    case trigger = "Trigger"
    case ai = "AI"
    case speech = "Speech"
    case knowledge = "Knowledge"
    case models = "Models"
    case logic = "Logic"
    case integration = "Integration"

    var id: String { rawValue }

    var accent: Color {
        switch self {
        case .trigger: return AppColors.success
        case .ai: return AppColors.brand
        case .speech: return AppColors.gradientEnd
        case .knowledge: return AppColors.warning
        case .models: return AppColors.statusGray
        case .logic: return AppColors.primaryPurple
        case .integration: return AppColors.info
        }
    }
}

/// Output socket names. "out" everywhere except Condition and Filter, which
/// branch into "true" and "false", and a pack node, whose outputs are whatever
/// the pack declared — an open set, which is why this is not an enum.
struct WorkflowOutputPort: RawRepresentable, Identifiable, Hashable {
    let rawValue: String

    private init(name: String) {
        rawValue = name
    }

    /// An empty port name is what a document written by an older writer leaves
    /// behind, and commons has no port by that name, so it is rejected here
    /// rather than drawn as a socket nothing can connect to.
    init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.init(name: rawValue)
    }

    var id: String { rawValue }

    static let out = WorkflowOutputPort(name: "out")
    static let truthy = WorkflowOutputPort(name: "true")
    static let falsy = WorkflowOutputPort(name: "false")

    var tint: Color {
        switch self {
        case .truthy: return AppColors.success
        case .falsy: return AppColors.warning
        default: return AppColors.brand
        }
    }
}

/// One input socket. Tool nodes grow one per declared argument and Merge grows
/// numbered ones, so the list belongs to a node and its settings rather than to
/// its kind alone.
struct WorkflowInputPort: Identifiable, Hashable {
    enum Role: Hashable {
        case flow
        case argument(required: Bool)
    }

    static let flowName = "in"

    let name: String
    let role: Role

    var id: String { name }

    var isArgument: Bool {
        if case .argument = role { return true }
        return false
    }

    var isRequired: Bool {
        if case .argument(let required) = role { return required }
        return false
    }

    static func flow(_ name: String = flowName) -> WorkflowInputPort {
        WorkflowInputPort(name: name, role: .flow)
    }
}

struct WorkflowNodeDescriptor {
    let title: String
    let systemImage: String
    let category: WorkflowNodeCategory
}

enum WorkflowNodeKind: String, CaseIterable, Identifiable, Codable {
    case manualTrigger
    case scheduleTrigger

    case llmGenerate
    case llmStructured
    case vision
    case embed
    case rerank

    case transcribe
    case speak
    case detectVoice
    case diarize
    case segment

    case ragQuery
    case ragIngest

    case loadModel

    case condition
    case filter
    case loopOverItems
    case code
    case setTransform
    case merge
    case splitOut
    case aggregate
    case wait

    case toolCall
    case httpRequest
    case fileRead
    case fileWrite

    case packNode

    var id: String { rawValue }

    var title: String { descriptor.title }
    var systemImage: String { descriptor.systemImage }
    var category: WorkflowNodeCategory { descriptor.category }

    var isTrigger: Bool { self == .manualTrigger || self == .scheduleTrigger }

    /// The palette's fixed rows. A pack node is left out because there is no
    /// generic one to place: it only exists as an instance of an installed pack,
    /// which the palette lists separately from the pack itself.
    static var placeable: [WorkflowNodeKind] {
        allCases.filter { $0 != .packNode }
    }

    var outputPorts: [WorkflowOutputPort] {
        switch self {
        case .condition, .filter: return [.truthy, .falsy]
        default: return [.out]
        }
    }

    /// Exhaustive on purpose: a new proto arm does not compile until it has a
    /// title, a symbol, and a palette group.
    private var descriptor: WorkflowNodeDescriptor {
        switch self {
        case .manualTrigger:
            return .init(title: "Manual Trigger", systemImage: "play.circle.fill", category: .trigger)
        case .scheduleTrigger:
            return .init(title: "Schedule Trigger", systemImage: "clock.fill", category: .trigger)
        case .llmGenerate:
            return .init(title: "LLM Generate", systemImage: "brain.head.profile", category: .ai)
        case .llmStructured:
            return .init(title: "LLM Structured", systemImage: "curlybraces.square", category: .ai)
        case .vision:
            return .init(title: "Vision", systemImage: "eye", category: .ai)
        case .embed:
            return .init(
                title: "Embed",
                systemImage: "point.3.connected.trianglepath.dotted",
                category: .ai
            )
        case .rerank:
            return .init(title: "Rerank", systemImage: "list.number", category: .ai)
        case .transcribe:
            return .init(title: "Transcribe", systemImage: "waveform", category: .speech)
        case .speak:
            return .init(title: "Speak", systemImage: "speaker.wave.2.fill", category: .speech)
        case .detectVoice:
            return .init(title: "Detect Voice", systemImage: "mic.fill", category: .speech)
        case .diarize:
            return .init(title: "Diarize", systemImage: "person.2.wave.2", category: .speech)
        case .segment:
            return .init(title: "Segment", systemImage: "scissors", category: .speech)
        case .ragQuery:
            return .init(title: "RAG Query", systemImage: "text.magnifyingglass", category: .knowledge)
        case .ragIngest:
            return .init(title: "RAG Ingest", systemImage: "tray.and.arrow.down.fill", category: .knowledge)
        case .loadModel:
            return .init(title: "Load Model", systemImage: "shippingbox.fill", category: .models)
        case .condition:
            return .init(title: "Condition", systemImage: "arrow.triangle.branch", category: .logic)
        case .filter:
            return .init(
                title: "Filter",
                systemImage: "line.3.horizontal.decrease.circle",
                category: .logic
            )
        case .loopOverItems:
            return .init(
                title: "Loop Over Items",
                systemImage: "arrow.triangle.2.circlepath",
                category: .logic
            )
        case .code:
            return .init(title: "Code", systemImage: "curlybraces", category: .logic)
        case .setTransform:
            return .init(title: "Set / Transform", systemImage: "slider.horizontal.3", category: .logic)
        case .merge:
            return .init(title: "Merge", systemImage: "arrow.triangle.merge", category: .logic)
        case .splitOut:
            return .init(title: "Split Out", systemImage: "square.split.2x1", category: .logic)
        case .aggregate:
            return .init(title: "Aggregate", systemImage: "rectangle.compress.vertical", category: .logic)
        case .wait:
            return .init(title: "Wait", systemImage: "hourglass", category: .logic)
        case .toolCall:
            return .init(
                title: "Tool Call",
                systemImage: "wrench.and.screwdriver.fill",
                category: .integration
            )
        case .httpRequest:
            return .init(title: "HTTP Request", systemImage: "globe", category: .integration)
        case .fileRead:
            return .init(title: "File Read", systemImage: "doc.text", category: .integration)
        case .fileWrite:
            return .init(title: "File Write", systemImage: "doc.badge.plus", category: .integration)
        case .packNode:
            return .init(title: "Node Pack", systemImage: "shippingbox", category: .integration)
        }
    }
}
