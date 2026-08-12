//
//  WorkflowNodeSettings.swift
//  RunAnywhereAI
//
//  Every node type's parameters in one flat struct. A node reads only the
//  fields its kind owns; the rest stay at their defaults and never reach the
//  proto. Flat beats a per-kind enum here because the inspector needs a
//  writable key path per control, and key paths do not reach through enum
//  associated values.
//

import Foundation
import RunAnywhere

/// One editable key/value line in the inspector. Ordered, unlike the proto's
/// maps, because rows that reshuffle while being typed into are unusable.
struct WorkflowKeyValueRow: Identifiable, Equatable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }
}

/// One declared argument of a tool. Copied into the document when the user
/// picks the tool, so the node keeps its shape on a machine where that tool is
/// not registered.
struct WorkflowToolPort: Identifiable, Equatable, Hashable {
    var name: String
    var summary: String
    var required: Bool
    var type: RAToolArgumentType

    var id: String { name }

    init(name: String, summary: String = "", required: Bool = false, type: RAToolArgumentType = .string) {
        self.name = name
        self.summary = summary
        self.required = required
        self.type = type
    }
}

struct WorkflowNodeSettings: Equatable {
    var triggerItemsJSON = ""

    var scheduleKind: RAScheduleKind = .interval
    var scheduleIntervalSeconds = 3600
    var scheduleHour = 9
    var scheduleMinute = 0
    var scheduleCron = ""

    // A pack node's arguments are declared the same way a tool's are, so the two
    // share these three fields and every reshape, socket, and inspector row
    // built on them. `toolName` stays empty on a pack node; `packID` names it.
    var toolName = ""
    var toolArguments: [WorkflowKeyValueRow] = []
    var toolPorts: [WorkflowToolPort] = []

    var packID = ""
    var packOutputs: [String] = []
    /// Set when the referenced pack is not installed on this machine. The card
    /// draws a placeholder and validation reports it, but the document stays
    /// openable and editable.
    var packMissing = false

    var prompt = ""
    var systemPrompt = ""
    var modelID = ""
    var llmTemperature: Double?
    var llmMaxTokens: Int?
    var jsonSchema = ""

    var textInput = ""
    var binaryKey = ""
    var language = ""
    var voice = ""
    var vadThreshold: Double?
    var speakerCount: Int?

    var rerankQuery = ""
    var rerankDocuments = ""
    var rerankTopN = 3

    var ragQuestion = ""
    var embeddingModelID = ""
    var ragLLMModelID = ""
    var ragTopK = 4
    var documentID = ""

    var loadCategory: RAModelCategory?

    var conditionLeft = ""
    var conditionOperator: RAComparisonOperator = .equals
    var conditionRight = ""

    var loopItems = ""
    var loopBodyNodeIDs: [String] = []
    var loopMaxIterations = 0

    var codeSource = "return items;"

    var mergeInputCount = 2
    var mergeDeduplicate = false

    var fieldPath = ""
    var waitSeconds = 5

    var httpMethod: RAHttpMethod = .get
    var httpURL = ""
    var httpHeaders: [WorkflowKeyValueRow] = []
    var httpBody = ""
    var httpTimeoutMs = 0
    var httpAuthEnabled = false
    var httpAuthKind: RAHttpAuthKind = .bearer
    var httpAuthSecret = ""
    var httpAuthName = ""

    var filePath = ""
    var fileBinary = false
    var mimeType = ""
    var fileContent = ""
    var fileAppend = false

    var assignments: [WorkflowKeyValueRow] = []
    var keepOnlyAssigned = false

    /// The literal an unconnected argument port falls back to.
    func toolArgument(_ name: String) -> String {
        toolArguments.first { $0.key == name }?.value ?? ""
    }

    mutating func setToolArgument(_ name: String, to value: String) {
        if let index = toolArguments.firstIndex(where: { $0.key == name }) {
            toolArguments[index].value = value
        } else {
            toolArguments.append(WorkflowKeyValueRow(key: name, value: value))
        }
    }
}

/// Where a tool argument's value comes from.
enum WorkflowArgumentState: Equatable {
    case wired
    case literal
    case unset
    case missing
}

extension WorkflowToolPort {
    init(_ wire: RAToolArgumentPort) {
        self.init(
            name: wire.name,
            summary: wire.description_p,
            required: wire.required,
            type: wire.type
        )
    }

    var wire: RAToolArgumentPort {
        var port = RAToolArgumentPort()
        port.name = name
        port.description_p = summary
        port.required = required
        port.type = type
        return port
    }

    /// The tool registry publishes one JSON Schema object per tool, the same
    /// shape OpenAI, Anthropic, and MCP each use. Sorted by name so a port list
    /// is stable across reads of an unordered JSON object.
    static func ports(of definition: ToolDefinition) -> [WorkflowToolPort] {
        guard let schema = try? RAToolValue.parseObjectJSON(definition.parameters),
              let properties = schema["properties"]?.object else { return [] }
        let required = Set(schema["required"]?.array?.compactMap(\.string) ?? [])
        return properties.keys.sorted().map { name in
            let property = properties[name]?.object ?? [:]
            return WorkflowToolPort(
                name: name,
                summary: property["description"]?.string ?? "",
                required: required.contains(name),
                type: argumentType(property["type"]?.string)
            )
        }
    }

    private static func argumentType(_ jsonSchemaType: String?) -> RAToolArgumentType {
        switch jsonSchemaType {
        case "number", "integer": return .number
        case "boolean": return .boolean
        case "object": return .object
        case "array": return .array
        default: return .string
        }
    }

    var typeLabel: String { type.workflowLabel }
}

extension RAToolArgumentType {
    var workflowLabel: String {
        switch self {
        case .string: return "text"
        case .number: return "number"
        case .boolean: return "true/false"
        case .object: return "object"
        case .array: return "list"
        case .unspecified, .UNRECOGNIZED: return "value"
        }
    }

    static let workflowSelectable: [RAToolArgumentType] = [
        .string, .number, .boolean, .object, .array
    ]
}
