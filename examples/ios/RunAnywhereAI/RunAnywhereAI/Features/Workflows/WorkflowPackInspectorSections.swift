//
//  WorkflowPackInspectorSections.swift
//  RunAnywhereAI
//
//  The inspector for a pack node. Its inputs are the pack's declared inputs, so
//  they reuse the argument rows a tool node's arguments already use; what is
//  specific here is the pack's identity, what a script pack may reach, and the
//  placeholder shown when the pack is not installed.
//

#if os(macOS)

import RunAnywhere
import SwiftUI

extension WorkflowNodeInspector {
    // MARK: - Node packs

    /// A pack node's arguments are the pack's declared inputs, so they reuse the
    /// same rows a tool node's arguments do — wired on the canvas or typed here.
    @ViewBuilder
    func packSections(_ node: WorkflowNode) -> some View {
        if let pack = viewModel.packStore.pack(node.settings.packID) {
            installedPackSection(pack)
        } else {
            missingPackSection(node)
        }

        if node.settings.toolPorts.isEmpty {
            Section {
                footnote("This pack declares no inputs.")
            } header: {
                Text("Inputs")
            }
        } else {
            Section {
                ForEach(node.settings.toolPorts) { port in
                    argumentRow(node, port)
                }
            } header: {
                Text("Inputs")
            } footer: {
                footnote("Each input is a socket on the card. Wire one to take its " +
                         "value from another node, or leave it unwired and type a value here.")
            }
        }

        Section {
            if node.settings.packOutputs.isEmpty {
                footnote("One output, named out.")
            } else {
                ForEach(node.settings.packOutputs, id: \.self) { output in
                    LabeledContent("Output", value: output)
                }
            }
        } header: {
            Text("Outputs")
        } footer: {
            footnote("Ports are copied from the pack when the node is placed, so the " +
                     "card keeps its shape on a machine without the pack installed.")
        }
    }

    private func installedPackSection(_ pack: RANodePack) -> some View {
        Section {
            LabeledContent("Pack", value: pack.displayName)
            if !pack.author.isEmpty { LabeledContent("Author", value: pack.author) }
            if !pack.version.isEmpty { LabeledContent("Version", value: pack.version) }
            LabeledContent("Kind", value: pack.isScript ? "Script" : "Composite")
            if !pack.description_p.isEmpty { footnote(pack.description_p) }
        } header: {
            Text("Node Pack")
        } footer: {
            packCapabilityFootnote(pack)
        }
    }

    @ViewBuilder
    private func packCapabilityFootnote(_ pack: RANodePack) -> some View {
        let granted = pack.capabilities.grantedSummaries
        if pack.isScript, !granted.isEmpty {
            footnote("Runs JavaScript and may: " + granted.joined(separator: "; ") + ".")
        } else if pack.isScript {
            footnote("Runs JavaScript and asked for no extra access.")
        } else {
            footnote("Composes nodes this app already has, so it grants nothing new.")
        }
    }

    /// The document stays openable and editable with a pack it cannot resolve.
    /// Commons reports the same thing in the problem list; neither is fatal.
    private func missingPackSection(_ node: WorkflowNode) -> some View {
        Section {
            Label {
                Text("This node references a pack that is not installed.")
                    .appType(.caption)
            } icon: {
                Image(systemName: "shippingbox.badge.clock")
                    .foregroundStyle(AppColors.warning)
            }
            LabeledContent("Pack id") {
                Text(node.settings.packID.isEmpty ? "—" : node.settings.packID)
                    .appType(.mono)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Missing Node Pack")
        } footer: {
            footnote("Import the bundle that carries this pack, or delete the node. " +
                     "The rest of the workflow still saves and runs.")
        }
    }
}

#endif
