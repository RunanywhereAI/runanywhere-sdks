//
//  WorkflowNodeInspectorSections.swift
//  RunAnywhereAI
//
//  The per-kind controls of the node inspector, grouped the way the palette
//  groups them. Split out of WorkflowNodeInspector so no single builder carries
//  all 28 node types.
//

#if os(macOS)

import RunAnywhere
import SwiftUI

extension WorkflowNodeInspector {
    // MARK: - Trigger

    @ViewBuilder
    func triggerSections(_ node: WorkflowNode) -> some View {
        if node.kind == .scheduleTrigger {
            scheduleSection(node)
        }
        seedItemsSection
    }

    private static let intervalPresets = [60, 300, 900, 1800, 3600, 21_600, 43_200, 86_400]

    @ViewBuilder
    private func scheduleSection(_ node: WorkflowNode) -> some View {
        Section {
            Picker("Fires", selection: setting(\.scheduleKind, field: "scheduleKind")) {
                ForEach(RAScheduleKind.selectable, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }

            switch node.settings.scheduleKind {
            case .daily:
                dailyRows
            case .cron:
                TextField("Cron expression", text: setting(\.scheduleCron, field: "scheduleCron"))
            case .interval, .unspecified, .UNRECOGNIZED:
                intervalRows(node)
            }
        } header: {
            Text("Schedule")
        } footer: {
            scheduleFootnote(node)
        }
    }

    @ViewBuilder
    private func intervalRows(_ node: WorkflowNode) -> some View {
        let seconds = clampedSetting(
            \.scheduleIntervalSeconds, field: "scheduleIntervalSeconds", minimum: 1
        )
        Picker("Every", selection: seconds) {
            ForEach(Self.intervalPresets, id: \.self) { preset in
                Text(WorkflowScheduleFormat.interval(seconds: preset)).tag(preset)
            }
            let current = node.settings.scheduleIntervalSeconds
            if !Self.intervalPresets.contains(current) {
                Text(WorkflowScheduleFormat.interval(seconds: current)).tag(current)
            }
        }
        TextField("Interval (seconds)", value: seconds, format: .number)
    }

    @ViewBuilder private var dailyRows: some View {
        Picker("Hour", selection: clampedSetting(\.scheduleHour, field: "scheduleHour", maximum: 23)) {
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d", hour)).tag(hour)
            }
        }
        Picker(
            "Minute",
            selection: clampedSetting(\.scheduleMinute, field: "scheduleMinute", maximum: 59)
        ) {
            ForEach(0..<60, id: \.self) { minute in
                Text(String(format: "%02d", minute)).tag(minute)
            }
        }
    }

    private func scheduleFootnote(_ node: WorkflowNode) -> some View {
        let base = "Schedules fire while the app is running. There is no background " +
            "execution and no catch-up after a relaunch."
        let cron = node.settings.scheduleKind == .cron
            ? " This host does not parse cron, so a cron trigger is stored but never fires."
            : ""
        return footnote(base + cron)
    }

    private var seedItemsSection: some View {
        Section {
            codeEditor(setting(\.triggerItemsJSON, field: "triggerItemsJSON"), minHeight: 80)
        } header: {
            Text("Initial Items")
        } footer: {
            footnote(
                "A JSON array of seed items. Empty runs the workflow once with one empty item."
            )
        }
    }

    // MARK: - AI

    @ViewBuilder
    func aiSections(_ node: WorkflowNode) -> some View {
        switch node.kind {
        case .llmGenerate:
            promptSection(minHeight: 90)
            modelSection(.language)
            Section("Generation") { generationRows() }
        case .llmStructured:
            promptSection(minHeight: 70)
            Section {
                codeEditor(setting(\.jsonSchema, field: "jsonSchema"), minHeight: 140)
            } header: {
                Text("JSON Schema")
            } footer: {
                footnote("The answer is parsed against this schema, so downstream " +
                         "expressions address its fields directly.")
            }
            modelSection(.language)
            Section("Generation") { generationRows() }
        case .vision:
            promptSection(minHeight: 70)
            binaryKeySection("Image Attachment", hint: "The attachment on the incoming item " +
                             "holding the image bytes — a File Read node in binary mode makes one.")
            modelSection(.vision)
            Section("Generation") { generationRows() }
        case .embed:
            Section("Text") {
                TextField("Text expression", text: setting(\.textInput, field: "textInput"))
            }
            modelSection(.embedding)
        case .rerank:
            Section("Rerank") {
                TextField("Query", text: setting(\.rerankQuery, field: "rerankQuery"))
                TextField("Documents expression", text: setting(\.rerankDocuments, field: "rerankDocuments"))
                TextField(
                    "Top N",
                    value: clampedSetting(\.rerankTopN, field: "rerankTopN", minimum: 1),
                    format: .number
                )
            }
            modelSection(.rerank)
        default:
            EmptyView()
        }
    }

    private func promptSection(minHeight: CGFloat) -> some View {
        Section("Prompt") {
            codeEditor(setting(\.prompt, field: "prompt"), minHeight: minHeight, monospaced: false)
        }
    }

    private func modelSection(_ category: RAModelCategory) -> some View {
        Section {
            modelPicker("Model", category: category, selection: setting(\.modelID, field: "modelID"))
        } header: {
            Text("Model")
        } footer: {
            footnote("Downloaded \(category.workflowLabel.lowercased()) models only. " +
                     "The runner loads the model when the node runs.")
        }
    }

    private func binaryKeySection(_ title: String, hint: String) -> some View {
        Section {
            TextField("Attachment key", text: setting(\.binaryKey, field: "binaryKey"))
        } header: {
            Text(title)
        } footer: {
            footnote(hint)
        }
    }

    // MARK: - Speech

    @ViewBuilder
    func speechSections(_ node: WorkflowNode) -> some View {
        switch node.kind {
        case .transcribe:
            binaryKeySection("Audio Attachment", hint: audioHint)
            Section("Options") {
                TextField("Language (optional)", text: setting(\.language, field: "language"))
            }
            modelSection(.speechRecognition)
        case .speak:
            Section {
                TextField("Text expression", text: setting(\.textInput, field: "textInput"))
                TextField("Attachment key", text: setting(\.binaryKey, field: "binaryKey"))
                TextField("Voice (optional)", text: setting(\.voice, field: "voice"))
            } header: {
                Text("Speech")
            } footer: {
                footnote("The runner returns the audio as an attachment under this key. " +
                         "It does not play it — there is no audio output path in the runner.")
            }
            modelSection(.speechSynthesis)
        case .detectVoice:
            binaryKeySection("Audio Attachment", hint: audioHint)
            Section("Threshold") { thresholdRow }
        case .diarize:
            binaryKeySection("Audio Attachment", hint: audioHint)
            Section("Speakers") { speakerCountRow }
            modelSection(.speakerDiarization)
        case .segment:
            Section("Text") {
                TextField("Text expression", text: setting(\.textInput, field: "textInput"))
            }
            modelSection(.semanticSegmentation)
        default:
            EmptyView()
        }
    }

    private var audioHint: String {
        "The attachment on the incoming item holding the audio bytes — a File Read " +
            "node in binary mode makes one."
    }

    private var thresholdRow: some View {
        let value = setting(\.vadThreshold, field: "vadThreshold")
        return Group {
            Toggle("Override threshold", isOn: Binding(
                get: { value.wrappedValue != nil },
                set: { value.wrappedValue = $0 ? 0.5 : nil }
            ))
            if let threshold = value.wrappedValue {
                LabeledContent("Threshold") {
                    HStack(spacing: Space.sm) {
                        Slider(value: Binding(
                            get: { threshold },
                            set: { value.wrappedValue = $0 }
                        ), in: 0...1)
                        Text(threshold.formatted(.number.precision(.fractionLength(2))))
                            .appType(.monoMetric)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var speakerCountRow: some View {
        let value = setting(\.speakerCount, field: "speakerCount")
        return Group {
            Toggle("Known speaker count", isOn: Binding(
                get: { value.wrappedValue != nil },
                set: { value.wrappedValue = $0 ? 2 : nil }
            ))
            if value.wrappedValue != nil {
                TextField(
                    "Speakers",
                    value: Binding(
                        get: { value.wrappedValue ?? 2 },
                        set: { value.wrappedValue = max(1, $0) }
                    ),
                    format: .number
                )
            }
        }
    }

    // MARK: - Knowledge

    @ViewBuilder
    func knowledgeSections(_ node: WorkflowNode) -> some View {
        if node.kind == .ragQuery {
            Section("Question") {
                TextField("Question", text: setting(\.ragQuestion, field: "ragQuestion"))
                TextField(
                    "Top K",
                    value: clampedSetting(\.ragTopK, field: "ragTopK", minimum: 1),
                    format: .number
                )
            }
        } else {
            Section("Document") {
                TextField("Text expression", text: setting(\.textInput, field: "textInput"))
                TextField("Document id", text: setting(\.documentID, field: "documentID"))
            }
        }

        Section {
            modelPicker(
                "Embedding",
                category: .embedding,
                selection: setting(\.embeddingModelID, field: "embeddingModelID")
            )
            modelPicker(
                "Language",
                category: .language,
                selection: setting(\.ragLLMModelID, field: "ragLLMModelID")
            )
        } header: {
            Text("Models")
        } footer: {
            footnote("A RAG session needs both an embedding model and a language model.")
        }
    }

    // MARK: - Models

    @ViewBuilder
    func modelSections(_ node: WorkflowNode) -> some View {
        Section {
            Picker("Category", selection: Binding(
                get: { node.settings.loadCategory ?? .language },
                set: { newValue in
                    viewModel.updateNode(nodeID, coalescing: "loadCategory") {
                        $0.settings.loadCategory = newValue
                    }
                }
            )) {
                ForEach(RAModelCategory.workflowSelectable, id: \.self) { category in
                    Text(category.workflowLabel).tag(category)
                }
            }
            modelPicker(
                "Model",
                category: node.settings.loadCategory ?? .language,
                selection: setting(\.modelID, field: "modelID"),
                automaticLabel: "Choose a model"
            )
        } header: {
            Text("Load")
        } footer: {
            footnote("Brings the model up before later nodes need it, so a long first " +
                     "load is a step you can watch rather than an unexplained pause.")
        }
    }

    // MARK: - Logic

    @ViewBuilder
    func logicSections(_ node: WorkflowNode) -> some View {
        switch node.kind {
        case .condition:
            Section {
                comparisonRows()
            } header: {
                Text("Test")
            } footer: {
                footnote("Items flow out of the true or false port depending on the test.")
            }
        case .filter:
            Section {
                comparisonRows()
            } header: {
                Text("Test")
            } footer: {
                footnote("Each item is tested on its own; matching items leave by true " +
                         "and the rest by false. Use {{ item.field }} to address the item.")
            }
        case .loopOverItems:
            loopSections(node)
        case .code:
            Section {
                codeEditor(setting(\.codeSource, field: "codeSource"), minHeight: 140)
            } header: {
                Text("JavaScript")
            } footer: {
                footnote("`items` is the input list; return the output list.")
            }
        case .merge:
            mergeSection
        default:
            listShapeSections(node)
        }
    }

    @ViewBuilder
    private func listShapeSections(_ node: WorkflowNode) -> some View {
        switch node.kind {
        case .setTransform:
            Section("Fields") {
                keyValueEditor(
                    \.assignments,
                    field: "assignments",
                    keyTitle: "Field",
                    valueTitle: "Expression",
                    addLabel: "Add Field"
                )
                Toggle(
                    "Keep only assigned fields",
                    isOn: setting(\.keepOnlyAssigned, field: "keepOnlyAssigned")
                )
            }
        case .splitOut:
            Section {
                TextField("List field", text: setting(\.fieldPath, field: "fieldPath"))
            } header: {
                Text("Split Out")
            } footer: {
                footnote("One output item per element of this list field.")
            }
        case .aggregate:
            Section {
                TextField("Field", text: setting(\.fieldPath, field: "fieldPath"))
            } header: {
                Text("Aggregate")
            } footer: {
                footnote("Collapses every input item into one, gathering this field.")
            }
        case .wait:
            Section("Wait") {
                TextField(
                    "Seconds",
                    value: clampedSetting(\.waitSeconds, field: "waitSeconds"),
                    format: .number
                )
            }
        default:
            EmptyView()
        }
    }

    private var mergeSection: some View {
        Section {
            Picker(
                "Inputs",
                selection: clampedSetting(
                    \.mergeInputCount, field: "mergeInputCount", minimum: 1, maximum: 8
                )
            ) {
                ForEach(1...8, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            Toggle("Drop duplicate items", isOn: setting(\.mergeDeduplicate, field: "mergeDeduplicate"))
        } header: {
            Text("Merge")
        } footer: {
            footnote("Branches concatenate in port order. Removing an input drops any " +
                     "connection that landed on it.")
        }
    }

    @ViewBuilder
    private func loopSections(_ node: WorkflowNode) -> some View {
        Section {
            TextField("Items expression", text: setting(\.loopItems, field: "loopItems"))
            TextField(
                "Max iterations",
                value: clampedSetting(\.loopMaxIterations, field: "loopMaxIterations"),
                format: .number
            )
        } header: {
            Text("Loop")
        } footer: {
            footnote("0 iterations means the runner's built-in cap applies.")
        }

        Section("Body Nodes") {
            let candidates = viewModel.graph.nodes.filter {
                $0.id != nodeID && !$0.kind.isTrigger
            }
            if candidates.isEmpty {
                footnote("Add other nodes first, then choose which ones run per item.")
            } else {
                ForEach(candidates) { candidate in
                    Toggle(candidate.name, isOn: Binding(
                        get: { node.settings.loopBodyNodeIDs.contains(candidate.id) },
                        set: { include in
                            viewModel.updateNode(nodeID, coalescing: "loopBody") { current in
                                current.settings.loopBodyNodeIDs.removeAll { $0 == candidate.id }
                                if include {
                                    current.settings.loopBodyNodeIDs.append(candidate.id)
                                }
                            }
                        }
                    ))
                }
            }
        }
    }

    // MARK: - Integration

    @ViewBuilder
    func integrationSections(_ node: WorkflowNode) -> some View {
        switch node.kind {
        case .toolCall:
            toolSections(node)
        case .httpRequest:
            httpSections(node)
        case .fileRead:
            Section("File") {
                TextField("Path", text: setting(\.filePath, field: "filePath"))
                Toggle("Read as binary", isOn: setting(\.fileBinary, field: "fileBinary"))
                if node.settings.fileBinary {
                    TextField("Attachment key", text: setting(\.binaryKey, field: "binaryKey"))
                    TextField("MIME type", text: setting(\.mimeType, field: "mimeType"))
                }
            }
        case .fileWrite:
            Section("File") {
                TextField("Path", text: setting(\.filePath, field: "filePath"))
                TextField("Attachment key (optional)", text: setting(\.binaryKey, field: "binaryKey"))
                Toggle("Append", isOn: setting(\.fileAppend, field: "fileAppend"))
            }
            Section {
                codeEditor(setting(\.fileContent, field: "fileContent"), minHeight: 90, monospaced: false)
            } header: {
                Text("Content")
            } footer: {
                footnote("Ignored when an attachment key names binary data on the incoming item.")
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Tool arguments

    @ViewBuilder
    private func toolSections(_ node: WorkflowNode) -> some View {
        Section("Tool") {
            if viewModel.availableTools.isEmpty {
                TextField("Tool name", text: setting(\.toolName, field: "toolName"))
            } else {
                toolPicker(node)
            }
        }

        if node.settings.toolPorts.isEmpty {
            Section {
                keyValueEditor(
                    \.toolArguments,
                    field: "toolArguments",
                    keyTitle: "Argument",
                    valueTitle: "Expression",
                    addLabel: "Add Argument"
                )
            } header: {
                Text("Arguments")
            } footer: {
                footnote("This tool declares no arguments the editor can read, so " +
                         "name them here instead.")
            }
        } else {
            Section {
                ForEach(node.settings.toolPorts) { port in
                    argumentRow(node, port)
                }
            } header: {
                Text("Arguments")
            } footer: {
                footnote("Each argument is a socket on the card. Wire one to take its " +
                         "value from another node, or leave it unwired and type a value here.")
            }
        }
    }

    private func toolPicker(_ node: WorkflowNode) -> some View {
        let known = viewModel.availableTools.map(\.name)
        return Picker("Tool", selection: Binding(
            get: { node.settings.toolName },
            set: { viewModel.selectTool(named: $0, for: nodeID) }
        )) {
            Text("Choose…").tag("")
            ForEach(known, id: \.self) { name in
                Text(name).tag(name)
            }
            if !node.settings.toolName.isEmpty, !known.contains(node.settings.toolName) {
                Text("\(node.settings.toolName) (not registered)").tag(node.settings.toolName)
            }
        }
    }

    /// Shared with the pack inspector: a pack declares its inputs exactly the
    /// way a tool declares its arguments, so one row serves both.
    func argumentRow(_ node: WorkflowNode, _ port: WorkflowToolPort) -> some View {
        let state = viewModel.toolArgumentState(node, port: port)
        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Text(port.name)
                    .appType(.cardTitle)
                Text(port.typeLabel)
                    .appType(.chip)
                    .foregroundStyle(AppColors.mutedForeground)
                Spacer(minLength: 0)
                argumentStateLabel(state, required: port.required)
            }

            if state == .wired {
                footnote("Wired on the canvas. A value typed here would be ignored.")
            } else {
                TextField("Value or {{ expression }}", text: literalBinding(port.name))
            }

            if !port.summary.isEmpty {
                footnote(port.summary)
            }
        }
        .padding(.vertical, Space.hair)
    }

    @ViewBuilder
    private func argumentStateLabel(_ state: WorkflowArgumentState, required: Bool) -> some View {
        switch state {
        case .wired:
            Label("Wired", systemImage: "link")
                .appType(.chip)
                .foregroundStyle(AppColors.brand)
        case .literal:
            Label("Literal", systemImage: "textformat")
                .appType(.chip)
                .foregroundStyle(AppColors.mutedForeground)
        case .missing:
            Label("Required", systemImage: "exclamationmark.triangle.fill")
                .appType(.chip)
                .foregroundStyle(AppColors.warningText)
        case .unset:
            Text(required ? "Required" : "Optional")
                .appType(.chip)
                .foregroundStyle(AppColors.mutedForeground)
        }
    }

    private func literalBinding(_ name: String) -> Binding<String> {
        Binding(
            get: { viewModel.graph.node(nodeID)?.settings.toolArgument(name) ?? "" },
            set: { newValue in
                viewModel.updateNode(nodeID, coalescing: "toolArgument.\(name)") {
                    $0.settings.setToolArgument(name, to: newValue)
                }
            }
        )
    }

    // MARK: - HTTP

    @ViewBuilder
    private func httpSections(_ node: WorkflowNode) -> some View {
        Section {
            Picker("Method", selection: setting(\.httpMethod, field: "httpMethod")) {
                ForEach(RAHttpMethod.selectable, id: \.self) { method in
                    Text(method.label).tag(method)
                }
            }
            TextField("URL", text: setting(\.httpURL, field: "httpURL"))
            TextField(
                "Timeout (ms)",
                value: clampedSetting(\.httpTimeoutMs, field: "httpTimeoutMs"),
                format: .number
            )
        } header: {
            Text("Request")
        } footer: {
            footnote("Timeout 0 uses the default.")
        }

        Section("Headers") {
            keyValueEditor(
                \.httpHeaders,
                field: "httpHeaders",
                keyTitle: "Header",
                valueTitle: "Value",
                addLabel: "Add Header"
            )
        }

        httpAuthSection(node)

        if node.settings.httpMethod != .get {
            Section("Body") {
                codeEditor(setting(\.httpBody, field: "httpBody"), minHeight: 80)
            }
        }
    }

    @ViewBuilder
    private func httpAuthSection(_ node: WorkflowNode) -> some View {
        Section {
            Toggle("Authenticate", isOn: setting(\.httpAuthEnabled, field: "httpAuthEnabled"))
            if node.settings.httpAuthEnabled {
                Picker("Kind", selection: setting(\.httpAuthKind, field: "httpAuthKind")) {
                    ForEach(RAHttpAuthKind.selectable, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                if node.settings.httpAuthKind != .bearer {
                    TextField(
                        node.settings.httpAuthKind == .header ? "Header name" : "Parameter name",
                        text: setting(\.httpAuthName, field: "httpAuthName")
                    )
                }
                SecureField("Secret", text: setting(\.httpAuthSecret, field: "httpAuthSecret"))
            }
        } header: {
            Text("Authentication")
        } footer: {
            footnote("The secret is stored in the workflow document, not the keychain. " +
                     "Treat a saved workflow as you would a file holding the key itself.")
        }
    }
}

#endif
