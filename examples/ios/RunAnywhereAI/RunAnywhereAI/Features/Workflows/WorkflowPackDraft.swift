//
//  WorkflowPackDraft.swift
//  RunAnywhereAI
//
//  What the two pack-creation flows fill in before a NodePack exists. Both a
//  composite pack turned out of the current graph and a hand-written script pack
//  declare the same metadata and the same ports, so they share one draft and one
//  form; only the implementation arm and the capability block differ.
//

import Foundation
import RunAnywhere
import SwiftUI

/// A declared port being edited. `WorkflowToolPort` keys identity off its name,
/// which changes on every keystroke while the user names it, so the draft keeps
/// its own stable identity and converts on the way out.
struct WorkflowPackPortDraft: Identifiable, Equatable {
    let id = UUID()
    var name = ""
    var summary = ""
    var required = false
    var type: RAToolArgumentType = .string

    var port: WorkflowToolPort {
        WorkflowToolPort(name: name, summary: summary, required: required, type: type)
    }
}

struct WorkflowPackOutputDraft: Identifiable, Equatable {
    let id = UUID()
    var name = ""
}

/// The swatches a pack may pick from, stored in `accent_rgb`. A free colour
/// picker would let a pack choose a card that reads as broken next to every
/// other card, so the choice is the design system's own accents.
enum WorkflowPackAccent: UInt32, CaseIterable, Identifiable {
    case purple = 0x8B_5C_F6
    case brand = 0xFF_69_00
    case blue = 0x3B_82_F6
    case green = 0x26_9B_57
    case amber = 0xF5_9E_0B
    case red = 0xFB_2C_36
    case slate = 0x64_74_8B

    var id: UInt32 { rawValue }

    var color: Color { Color(hex: UInt(rawValue)) }

    var label: String {
        switch self {
        case .purple: return "Purple"
        case .brand: return "Orange"
        case .blue: return "Blue"
        case .green: return "Green"
        case .amber: return "Amber"
        case .red: return "Red"
        case .slate: return "Slate"
        }
    }
}

struct WorkflowPackDraft: Equatable {
    var name = ""
    var summary = ""
    var author = ""
    var version = "1.0.0"
    var category = WorkflowNodeCategory.integration.rawValue
    var icon = WorkflowPackCatalog.fallbackSymbol
    var accent: WorkflowPackAccent = .purple

    var inputs: [WorkflowPackPortDraft] = []
    var outputs: [WorkflowPackOutputDraft] = []

    /// Empty entry means the composite's own trigger; empty exit means the last
    /// node in topological order. Both are what most packs want.
    var entryNodeID = ""
    var exitNodeID = ""

    var script = "return items;"
    var allowsNetwork = false
    var allowsFilesystem = false
    var allowsTools = false
    var toolNames = ""

    /// A problem the user has to fix, or nil when the draft is ready to save.
    var validationMessage: String? {
        if name.trimmed.isEmpty { return "Give the pack a name." }
        let inputNames = inputs.map { $0.name.trimmed }
        if inputNames.contains(where: \.isEmpty) { return "Every input needs a name." }
        if Set(inputNames).count != inputNames.count { return "Input names have to be unique." }
        let outputNames = outputs.map { $0.name.trimmed }
        if outputNames.contains(where: \.isEmpty) { return "Every output needs a name." }
        if Set(outputNames).count != outputNames.count { return "Output names have to be unique." }
        return nil
    }

    var scriptValidationMessage: String? {
        if let message = validationMessage { return message }
        if script.trimmed.isEmpty { return "A script pack needs a body." }
        return nil
    }

    // MARK: - Building the pack

    func compositePack(id: String, graph: RAWorkflowDocument) -> RANodePack {
        var pack = basePack(id: id)
        var composite = RACompositeImplementation()
        composite.graph = graph
        composite.entryNodeID = entryNodeID
        composite.exitNodeID = exitNodeID
        pack.composite = composite
        return pack
    }

    func scriptPack(id: String) -> RANodePack {
        var pack = basePack(id: id)
        var script = RAScriptImplementation()
        script.source = self.script
        pack.script = script

        var capabilities = RANodePackCapabilities()
        capabilities.network = allowsNetwork
        capabilities.filesystem = allowsFilesystem
        capabilities.tools = allowsTools
        capabilities.toolNames = allowsTools ? parsedToolNames : []
        pack.capabilities = capabilities
        return pack
    }

    var parsedToolNames: [String] {
        toolNames
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func basePack(id: String) -> RANodePack {
        var pack = RANodePack()
        pack.id = id
        pack.name = name.trimmed
        pack.description_p = summary.trimmed
        pack.author = author.trimmed
        pack.version = version.trimmed
        pack.category = category.trimmed
        pack.icon = icon.trimmed
        pack.accentRgb = accent.rawValue
        pack.inputs = inputs.map { draft in
            var normalized = draft
            normalized.name = draft.name.trimmed
            return normalized.port.wire
        }
        pack.outputs = outputs.map { $0.name.trimmed }
        return pack
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
