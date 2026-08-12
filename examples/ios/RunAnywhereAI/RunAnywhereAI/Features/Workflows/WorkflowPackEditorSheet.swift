//
//  WorkflowPackEditorSheet.swift
//  RunAnywhereAI
//
//  The two ways a pack gets made. Both declare the same metadata and the same
//  ports, so they share this sheet; what differs is the implementation and what
//  it is allowed to do.
//
//  A composite pack is the open graph, wrapped. It composes nodes the host
//  already has, so it grants nothing new and has no capabilities to declare. A
//  script pack carries JavaScript, which is why it declares what it may reach
//  and why the importer shows that list before anyone takes it.
//

#if os(macOS)

import RunAnywhere
import SwiftUI

struct WorkflowPackEditorSheet: View {
    var viewModel: WorkflowEditorViewModel
    let mode: WorkflowPackEditorMode

    @Environment(\.dismiss)
    private var dismiss
    @State private var draft = WorkflowPackDraft()
    @State private var isSaving = false

    var body: some View {
        WorkflowSheetShell(
            title: mode.title,
            message: message,
            confirm: isSaving ? "Saving…" : "Save Pack",
            isConfirmEnabled: blocker == nil && !isSaving,
            showsCancel: true
        ) {
            Form {
                identitySection
                inputsSection
                outputsSection
                if mode == .composite {
                    graphSection
                } else {
                    scriptSection
                    capabilitiesSection
                }
                if let blocker {
                    Section {
                        Label(blocker, systemImage: "exclamationmark.triangle.fill")
                            .appType(.caption)
                            .foregroundStyle(AppColors.warningText)
                    }
                }
            }
            .formStyle(.grouped)
        } onCancel: {
            dismiss()
        } onConfirm: {
            save()
        }
        .onAppear(perform: prefill)
    }

    private var message: String {
        mode == .composite
            ? "The open graph becomes the pack's body. It composes nodes this app already " +
                "has, so it grants nothing new and needs no capability review when shared."
            : "A script pack runs JavaScript through the same host engine a Code node uses. " +
                "Whoever imports it sees the capabilities declared here before enabling it."
    }

    private var blocker: String? {
        if mode == .composite, viewModel.graph.nodes.isEmpty {
            return "There is nothing on the canvas to turn into a pack."
        }
        return mode == .composite ? draft.validationMessage : draft.scriptValidationMessage
    }

    private func prefill() {
        guard draft.name.isEmpty else { return }
        if mode == .composite {
            draft.name = viewModel.workflowName
        }
    }

    private func save() {
        isSaving = true
        Task {
            let saved = mode == .composite
                ? await viewModel.saveAsPack(draft)
                : await viewModel.saveScriptPack(draft)
            isSaving = false
            if saved { dismiss() }
        }
    }

    // MARK: - Identity

    private var identitySection: some View {
        Section {
            TextField("Name", text: $draft.name)
            TextField("Description", text: $draft.summary, axis: .vertical)
                .lineLimit(2...4)
            TextField("Author", text: $draft.author)
            TextField("Version", text: $draft.version)
            TextField("Category", text: $draft.category)
            iconRow
            accentRow
        } header: {
            Text("Pack")
        } footer: {
            Text("A category matching a palette group (\(paletteGroups)) puts the pack in " +
                 "that group; any other name gets a group of its own.")
                .appType(.caption)
                .foregroundStyle(AppColors.mutedForeground)
        }
    }

    private var paletteGroups: String {
        WorkflowNodeCategory.allCases.map(\.rawValue).joined(separator: ", ")
    }

    private var iconRow: some View {
        LabeledContent("Icon") {
            HStack(spacing: Space.sm) {
                TextField("SF Symbol name", text: $draft.icon)
                Image(systemName: resolvedIcon)
                    .appType(.cardTitle)
                    .foregroundStyle(draft.accent.color)
                    .frame(width: 26, height: 26)
                    .background(
                        draft.accent.color.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    )
                    .help(resolvedIcon == draft.icon
                        ? draft.icon
                        : "This Mac has no symbol called \(draft.icon); showing the fallback.")
            }
        }
    }

    /// Resolved rather than shown raw: a symbol name this OS does not have draws
    /// nothing at all, which reads as a broken field rather than a bad name.
    private var resolvedIcon: String {
        var probe = RANodePack()
        probe.icon = draft.icon
        return probe.resolvedSymbol
    }

    private var accentRow: some View {
        Picker("Accent", selection: $draft.accent) {
            ForEach(WorkflowPackAccent.allCases) { accent in
                Label {
                    Text(accent.label)
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(accent.color)
                }
                .tag(accent)
            }
        }
    }

    // MARK: - Ports

    private var inputsSection: some View {
        Section {
            ForEach($draft.inputs) { $input in
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.sm) {
                        TextField("Name", text: $input.name)
                        Picker("", selection: $input.type) {
                            ForEach(RAToolArgumentType.workflowSelectable, id: \.self) { type in
                                Text(type.workflowLabel).tag(type)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        Button {
                            draft.inputs.removeAll { $0.id == input.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(AppColors.mutedForeground)
                        }
                        .buttonStyle(.plain)
                        .help("Remove this input")
                    }
                    TextField("What it is for", text: $input.summary)
                    Toggle("Required", isOn: $input.required)
                }
                .padding(.vertical, Space.hair)
            }

            Button {
                draft.inputs.append(WorkflowPackPortDraft())
            } label: {
                Label("Add Input", systemImage: "plus.circle")
            }
        } header: {
            Text("Inputs")
        } footer: {
            Text("Each input becomes a socket on the pack's card, wired on the canvas or " +
                 "typed into the inspector.")
                .appType(.caption)
                .foregroundStyle(AppColors.mutedForeground)
        }
    }

    private var outputsSection: some View {
        Section {
            ForEach($draft.outputs) { $output in
                HStack(spacing: Space.sm) {
                    TextField("Name", text: $output.name)
                    Button {
                        draft.outputs.removeAll { $0.id == output.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(AppColors.mutedForeground)
                    }
                    .buttonStyle(.plain)
                    .help("Remove this output")
                }
            }

            Button {
                draft.outputs.append(WorkflowPackOutputDraft())
            } label: {
                Label("Add Output", systemImage: "plus.circle")
            }
        } header: {
            Text("Outputs")
        } footer: {
            Text("Leave this empty for the single output named out that every other node has.")
                .appType(.caption)
                .foregroundStyle(AppColors.mutedForeground)
        }
    }

    // MARK: - Composite body

    private var graphSection: some View {
        Section {
            LabeledContent("Nodes", value: "\(viewModel.graph.nodes.count)")
            LabeledContent("Connections", value: "\(viewModel.graph.edges.count)")
            nodePicker("Entry node", selection: $draft.entryNodeID, automatic: "The graph's trigger")
            nodePicker("Exit node", selection: $draft.exitNodeID, automatic: "Last node in order")
        } header: {
            Text("Body")
        } footer: {
            Text("The pack captures the graph as it is now. Editing this workflow afterwards " +
                 "does not change the pack.")
                .appType(.caption)
                .foregroundStyle(AppColors.mutedForeground)
        }
    }

    private func nodePicker(
        _ title: String,
        selection: Binding<String>,
        automatic: String
    ) -> some View {
        Picker(title, selection: selection) {
            Text(automatic).tag("")
            ForEach(viewModel.graph.nodes) { node in
                Text(node.name).tag(node.id)
            }
        }
    }

    // MARK: - Script body

    private var scriptSection: some View {
        Section {
            TextEditor(text: $draft.script)
                .font(AppType.font(.mono))
                .scrollContentBackground(.hidden)
                .padding(Space.xs)
                .frame(minHeight: 160)
                .background(
                    AppColors.surfaceSunken,
                    in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                )
        } header: {
            Text("JavaScript")
        } footer: {
            Text("`items` is the input list; return the output list. Evaluated through the " +
                 "same host engine a Code node uses.")
                .appType(.caption)
                .foregroundStyle(AppColors.mutedForeground)
        }
    }

    private var capabilitiesSection: some View {
        Section {
            Toggle("Reach the network", isOn: $draft.allowsNetwork)
            Toggle("Read and write files", isOn: $draft.allowsFilesystem)
            Toggle("Call registered tools", isOn: $draft.allowsTools)
            if draft.allowsTools {
                TextField("Tool names, comma separated", text: $draft.toolNames)
                Text(draft.parsedToolNames.isEmpty
                    ? "Empty means any registered tool."
                    : "Limited to: " + draft.parsedToolNames.joined(separator: ", "))
                    .appType(.caption)
                    .foregroundStyle(AppColors.mutedForeground)
            }
        } header: {
            Text("Capabilities")
        } footer: {
            Text("Declared by the pack and shown to whoever imports it. Ask for nothing and " +
                 "the pack needs no review.")
                .appType(.caption)
                .foregroundStyle(AppColors.mutedForeground)
        }
    }
}

#Preview("Script pack editor") {
    WorkflowPackEditorSheet(viewModel: WorkflowEditorViewModel(), mode: .script)
}

#Preview("Save as node pack") {
    let viewModel = WorkflowEditorViewModel()
    viewModel.mutate { $0 = WorkflowPreviewFixtures.cardGallery }
    return WorkflowPackEditorSheet(viewModel: viewModel, mode: .composite)
}

#endif
