//
//  WorkflowPackCatalog.swift
//  RunAnywhereAI
//
//  How an installed NodePack becomes a card, a palette row, and a set of
//  sockets. A pack node's shape is mirrored from the pack at drop time, exactly
//  the way a tool node mirrors its tool's arguments, so a document that
//  references a pack this machine does not have still opens with the right shape.
//

import Foundation
import RunAnywhere
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What a card and a palette row need in order to draw a node. A built-in kind
/// answers from its own descriptor; a pack node answers from the installed pack,
/// or reports the id it could not find.
struct WorkflowNodePresentation {
    let title: String
    let systemImage: String
    let accent: Color
    let missingPackID: String?

    var isMissing: Bool { missingPackID != nil }
}

enum WorkflowPackCatalog {
    static let fallbackSymbol = "shippingbox.fill"
    static let missingSymbol = "questionmark.square.dashed"

    /// Accent for a pack that declared none. `accent_rgb` of 0 is
    /// indistinguishable from unset in proto3, and a pure-black card reads as a
    /// rendering fault rather than a choice.
    static let fallbackAccent = AppColors.primaryPurple

    static func presentation(
        of node: WorkflowNode,
        packs: [String: RANodePack]
    ) -> WorkflowNodePresentation {
        guard node.kind == .packNode else {
            return WorkflowNodePresentation(
                title: node.kind.title,
                systemImage: node.kind.systemImage,
                accent: node.kind.category.accent,
                missingPackID: nil
            )
        }
        guard let pack = packs[node.settings.packID] else {
            return WorkflowNodePresentation(
                title: "Missing Node Pack",
                systemImage: missingSymbol,
                accent: AppColors.warning,
                missingPackID: node.settings.packID
            )
        }
        return WorkflowNodePresentation(
            title: pack.name.isEmpty ? pack.id : pack.name,
            systemImage: pack.resolvedSymbol,
            accent: pack.accent,
            missingPackID: nil
        )
    }

    /// The node settings a freshly dropped pack node starts with. Ports and
    /// outputs are copied now rather than looked up at run time; that copy is
    /// what keeps the card the right shape on a machine without the pack.
    static func settings(for pack: RANodePack) -> WorkflowNodeSettings {
        var settings = WorkflowNodeSettings()
        settings.packID = pack.id
        settings.toolPorts = pack.inputs.map(WorkflowToolPort.init)
        settings.packOutputs = pack.outputs
        settings.packMissing = false
        return settings
    }

    /// Re-mirror an existing node against the installed pack list. Values the
    /// user typed are kept; only the declared shape and the missing flag move,
    /// so this is reconciliation rather than an edit and takes no undo step.
    static func reconcile(_ settings: inout WorkflowNodeSettings, against pack: RANodePack?) -> Bool {
        guard let pack else {
            guard !settings.packMissing else { return false }
            settings.packMissing = true
            return true
        }
        let ports = pack.inputs.map(WorkflowToolPort.init)
        guard settings.packMissing || settings.toolPorts != ports
            || settings.packOutputs != pack.outputs else { return false }
        settings.packMissing = false
        settings.toolPorts = ports
        settings.packOutputs = pack.outputs
        return true
    }

    /// Pack ids are a filesystem path component in commons, which accepts
    /// 1-128 characters of `[A-Za-z0-9_-]` and rejects anything else outright.
    static func freshID(basedOn name: String) -> String {
        let slug = name.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let trimmed = String(slug).split(separator: "-").joined(separator: "-")
        let stem = trimmed.isEmpty ? "pack" : String(trimmed.prefix(48))
        return stem + "-" + UUID().uuidString.prefix(8).lowercased()
    }
}

// MARK: - Pack presentation

extension RANodePack {
    var accent: Color {
        accentRgb == 0 ? WorkflowPackCatalog.fallbackAccent : Color(hex: UInt(accentRgb))
    }

    /// An icon naming a symbol this OS does not have renders as nothing at all,
    /// so an unknown name falls back rather than leaving a blank header.
    var resolvedSymbol: String {
        guard !icon.isEmpty else { return WorkflowPackCatalog.fallbackSymbol }
        #if os(macOS)
        let exists = NSImage(systemSymbolName: icon, accessibilityDescription: nil) != nil
        #else
        let exists = UIImage(systemName: icon) != nil
        #endif
        return exists ? icon : WorkflowPackCatalog.fallbackSymbol
    }

    var displayName: String { name.isEmpty ? id : name }

    var paletteCategory: String {
        category.isEmpty ? "Node Packs" : category
    }

    /// A script pack carries JavaScript, so what it may reach has to be shown
    /// and agreed to. A composite pack composes nodes the host already has and
    /// grants nothing new, which is why it has no capability list to review.
    var isScript: Bool {
        if case .script = implementation { return true }
        return false
    }

    var subtitle: String {
        let version = self.version.isEmpty ? nil : "v\(self.version)"
        let author = self.author.isEmpty ? nil : self.author
        let kind = isScript ? "Script" : "Composite"
        return [author, version, kind].compactMap(\.self).joined(separator: " · ")
    }
}

extension RANodePackCapabilities {
    /// One line per capability the pack asked for. Empty means it asked for
    /// nothing, which is safe to enable without a prompt.
    var grantedSummaries: [String] {
        var summaries: [String] = []
        if network { summaries.append("Reach the network") }
        if filesystem { summaries.append("Read and write files") }
        if tools {
            summaries.append(
                toolNames.isEmpty
                    ? "Call any registered tool"
                    : "Call these tools: " + toolNames.joined(separator: ", ")
            )
        }
        return summaries
    }
}
