//
//  WorkflowNodeInspector.swift
//  RunAnywhereAI
//
//  The right-hand pane: typed controls for the selected node, connection and
//  multi-selection summaries, and the workflow overview when nothing is
//  selected. Every edit funnels through the view model's coalescing update so
//  a typed sentence is one undo step, not thirty.
//
//  The per-kind controls live in WorkflowNodeInspectorSections.swift; this file
//  holds the shell, the bindings, and the controls those sections share.
//

#if os(macOS)

import RunAnywhere
import SwiftUI

struct WorkflowInspectorPane: View {
    var viewModel: WorkflowEditorViewModel
    let onReveal: (String) -> Void

    var body: some View {
        Group {
            if let node = viewModel.singleSelectedNode {
                WorkflowNodeInspector(viewModel: viewModel, nodeID: node.id)
                    .id(node.id)
            } else if viewModel.selectedNodeIDs.count > 1 {
                multiSelection
            } else if let edgeID = viewModel.selectedEdgeID {
                edgeInspector(edgeID)
            } else {
                overview
            }
        }
        .background(AppColors.background)
    }

    // MARK: - Overview (nothing selected)

    private var overview: some View {
        Form {
            Section("Workflow") {
                LabeledContent("Nodes", value: "\(viewModel.graph.nodes.count)")
                LabeledContent("Connections", value: "\(viewModel.graph.edges.count)")
            }

            if !viewModel.issues.isEmpty {
                Section("Problems") {
                    ForEach(viewModel.issues) { issue in
                        Button {
                            if let nodeID = issue.nodeID {
                                viewModel.select(nodeID, additive: false)
                                onReveal(nodeID)
                            }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(AppColors.warning)
                                Text(issue.message)
                                    .foregroundStyle(AppColors.foreground)
                                    .multilineTextAlignment(.leading)
                            }
                            .appType(.caption)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(issue.nodeID == nil)
                    }
                }
            }

            Section {
                Text("Select a node to edit it. Drag from an output dot to " +
                     "an input dot to connect nodes; ⇧-drag on the canvas to " +
                     "select several at once.")
                    .appType(.caption)
                    .foregroundStyle(AppColors.mutedForeground)
                expressionHelp
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Edge selected

    private func edgeInspector(_ edgeID: String) -> some View {
        Form {
            Section("Connection") {
                if let edge = viewModel.graph.edges.first(where: { $0.id == edgeID }) {
                    LabeledContent("From") {
                        HStack(spacing: Space.xs) {
                            Circle()
                                .fill(edge.fromPort.tint)
                                .frame(width: Control.dot, height: Control.dot)
                            Text(nodeName(edge.fromNode) + portSuffix(edge.fromPort))
                        }
                    }
                    LabeledContent("To", value: nodeName(edge.toNode))
                    LabeledContent("Into", value: edge.toPort)

                    Button("Remove Connection", role: .destructive) {
                        withMotion { viewModel.deleteEdge(edgeID) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func nodeName(_ id: String) -> String {
        viewModel.graph.node(id)?.name ?? "?"
    }

    private func portSuffix(_ port: WorkflowOutputPort) -> String {
        port == .out ? "" : " (\(port.rawValue))"
    }

    // MARK: - Multiple nodes selected

    private var multiSelection: some View {
        Form {
            Section {
                LabeledContent("Selected", value: "\(viewModel.selectedNodeIDs.count) nodes")
                Button("Duplicate") {
                    withMotion { viewModel.duplicateSelection() }
                }
                Button("Delete", role: .destructive) {
                    withMotion { viewModel.deleteSelection() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var expressionHelp: some View {
        Text("Fields accept expressions: {{ Node Name.field }} reads an " +
             "earlier node's output, and {{ item.field }} reads the current " +
             "item inside a loop.")
            .appType(.caption)
            .foregroundStyle(AppColors.mutedForeground)
    }
}

// MARK: - Single node

struct WorkflowNodeInspector: View {
    var viewModel: WorkflowEditorViewModel
    let nodeID: String

    var node: WorkflowNode? {
        viewModel.graph.node(nodeID)
    }

    var body: some View {
        if let node {
            Form {
                identitySection(node)
                configSections(node)
                issuesSection
                outputSection
            }
            .formStyle(.grouped)
        }
    }

    // MARK: - Bindings

    func setting<Value: Equatable>(
        _ keyPath: WritableKeyPath<WorkflowNodeSettings, Value>,
        field: String
    ) -> Binding<Value> {
        Binding(
            get: {
                (viewModel.graph.node(nodeID)?.settings ?? WorkflowNodeSettings())[keyPath: keyPath]
            },
            set: { newValue in
                viewModel.updateNode(nodeID, coalescing: field) { node in
                    node.settings[keyPath: keyPath] = newValue
                }
            }
        )
    }

    /// A whole-number field that can never be dragged below `minimum`, which is
    /// what keeps a Merge from claiming zero inputs mid-typing.
    func clampedSetting(
        _ keyPath: WritableKeyPath<WorkflowNodeSettings, Int>,
        field: String,
        minimum: Int = 0,
        maximum: Int = .max
    ) -> Binding<Int> {
        Binding(
            get: {
                (viewModel.graph.node(nodeID)?.settings ?? WorkflowNodeSettings())[keyPath: keyPath]
            },
            set: { newValue in
                viewModel.updateNode(nodeID, coalescing: field) { node in
                    node.settings[keyPath: keyPath] = min(maximum, max(minimum, newValue))
                }
            }
        )
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { viewModel.graph.node(nodeID)?.name ?? "" },
            set: { newValue in
                viewModel.updateNode(nodeID, coalescing: "name") { $0.name = newValue }
            }
        )
    }

    // MARK: - Sections

    private func identitySection(_ node: WorkflowNode) -> some View {
        let presentation = viewModel.presentation(of: node)
        return Section {
            HStack(spacing: Space.sm) {
                Image(systemName: presentation.systemImage)
                    .appType(.caption)
                    .foregroundStyle(presentation.accent)
                    .frame(width: 26, height: 26)
                    .background(
                        presentation.accent.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: Space.hair) {
                    TextField("Name", text: nameBinding)
                        .textFieldStyle(.plain)
                        .appType(.cardTitle)
                    Text(presentation.title)
                        .appType(.caption)
                        .foregroundStyle(AppColors.mutedForeground)
                }
            }
        } footer: {
            Text("The name is how expressions refer to this node.")
                .appType(.caption)
                .foregroundStyle(AppColors.mutedForeground)
        }
    }

    /// Dispatch by category so no single builder carries every kind. A pack node
    /// is dispatched by kind first: its controls come from the installed pack,
    /// not from the category it happens to sit in.
    @ViewBuilder
    private func configSections(_ node: WorkflowNode) -> some View {
        if node.kind == .packNode {
            packSections(node)
        } else {
            builtInSections(node)
        }
    }

    @ViewBuilder
    private func builtInSections(_ node: WorkflowNode) -> some View {
        switch node.kind.category {
        case .trigger: triggerSections(node)
        case .ai: aiSections(node)
        case .speech: speechSections(node)
        case .knowledge: knowledgeSections(node)
        case .models: modelSections(node)
        case .logic: logicSections(node)
        case .integration: integrationSections(node)
        }
    }

    @ViewBuilder private var issuesSection: some View {
        let issues = viewModel.issues(for: nodeID)
        if !issues.isEmpty {
            Section("Problems") {
                ForEach(issues) { issue in
                    Label {
                        Text(issue.message).appType(.caption)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppColors.warning)
                    }
                }
            }
        }
    }

    @ViewBuilder private var outputSection: some View {
        if let output = viewModel.nodeOutputs[nodeID] {
            Section("Last Output") {
                ScrollView {
                    Text(output)
                        .appType(.mono)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }
        }
    }

    // MARK: - Shared controls

    func codeEditor(
        _ text: Binding<String>, minHeight: CGFloat, monospaced: Bool = true
    ) -> some View {
        TextEditor(text: text)
            .font(AppType.font(monospaced ? .mono : .body))
            .scrollContentBackground(.hidden)
            .padding(Space.xs)
            .frame(minHeight: minHeight)
            .background(
                AppColors.surfaceSunken,
                in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
            )
    }

    func footnote(_ text: String) -> some View {
        Text(text)
            .appType(.caption)
            .foregroundStyle(AppColors.mutedForeground)
    }

    /// Every model dropdown in the inspector, filtered to one category. An id
    /// the registry no longer knows stays selectable and is labelled as such,
    /// so opening a workflow on another machine does not silently retarget it.
    func modelPicker(
        _ title: String,
        category: RAModelCategory,
        selection: Binding<String>,
        automaticLabel: String = "Automatic (currently loaded)"
    ) -> some View {
        let models = viewModel.models(for: category)
        let knownIDs = models.map(\.id)
        let current = selection.wrappedValue
        return Picker(title, selection: selection) {
            Text(automaticLabel).tag("")
            ForEach(models, id: \.id) { model in
                Text(model.name).tag(model.id)
            }
            if !current.isEmpty, !knownIDs.contains(current) {
                Text("\(current) (not downloaded)").tag(current)
            }
        }
    }

    func comparisonRows() -> some View {
        Group {
            TextField("Left value", text: setting(\.conditionLeft, field: "conditionLeft"))
            Picker("Comparison", selection: setting(\.conditionOperator, field: "conditionOperator")) {
                ForEach(RAComparisonOperator.selectable, id: \.self) { comparison in
                    Text(comparison.label).tag(comparison)
                }
            }
            if node?.settings.conditionOperator != .isEmpty {
                TextField("Right value", text: setting(\.conditionRight, field: "conditionRight"))
            }
        }
    }

    func generationRows() -> some View {
        Group {
            TextField(
                "System prompt",
                text: setting(\.systemPrompt, field: "systemPrompt"),
                axis: .vertical
            )
            .lineLimit(2...5)

            temperatureRow
            maxTokensRow
        }
    }

    private var temperatureRow: some View {
        let value = setting(\.llmTemperature, field: "llmTemperature")
        return Group {
            Toggle("Override temperature", isOn: Binding(
                get: { value.wrappedValue != nil },
                set: { value.wrappedValue = $0 ? 0.7 : nil }
            ))
            if let temperature = value.wrappedValue {
                LabeledContent("Temperature") {
                    HStack(spacing: Space.sm) {
                        Slider(value: Binding(
                            get: { temperature },
                            set: { value.wrappedValue = $0 }
                        ), in: 0...2)
                        Text(temperature.formatted(.number.precision(.fractionLength(2))))
                            .appType(.monoMetric)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var maxTokensRow: some View {
        let value = setting(\.llmMaxTokens, field: "llmMaxTokens")
        return Group {
            Toggle("Override max tokens", isOn: Binding(
                get: { value.wrappedValue != nil },
                set: { value.wrappedValue = $0 ? 256 : nil }
            ))
            if value.wrappedValue != nil {
                let tokens = Binding(
                    get: { value.wrappedValue ?? 256 },
                    set: { value.wrappedValue = max(1, $0) }
                )
                TextField("Max tokens", value: tokens, format: .number)
            }
        }
    }

    @ViewBuilder
    func keyValueEditor(
        _ keyPath: WritableKeyPath<WorkflowNodeSettings, [WorkflowKeyValueRow]>,
        field: String,
        keyTitle: String,
        valueTitle: String,
        addLabel: String
    ) -> some View {
        let rows = setting(keyPath, field: field)

        ForEach(rows) { $row in
            HStack(spacing: Space.sm) {
                TextField(keyTitle, text: $row.key)
                    .frame(maxWidth: 110)
                TextField(valueTitle, text: $row.value)
                Button {
                    rows.wrappedValue.removeAll { $0.id == row.id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(AppColors.mutedForeground)
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
        }

        Button {
            rows.wrappedValue.append(WorkflowKeyValueRow())
        } label: {
            Label(addLabel, systemImage: "plus.circle")
        }
    }
}

#endif
