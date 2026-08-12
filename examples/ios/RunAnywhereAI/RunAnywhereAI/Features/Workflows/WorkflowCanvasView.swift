//
//  WorkflowCanvasView.swift
//  RunAnywhereAI
//
//  The workflow builder shell: palette, canvas, inspector, and the toolbar
//  that saves and runs. The canvas itself lives in WorkflowCanvasSurface;
//  this view owns the camera and everything that floats above the graph.
//

#if os(macOS)

import RunAnywhere
import SwiftUI
import UniformTypeIdentifiers

struct WorkflowCanvasView: View {
    @State private var viewModel = WorkflowEditorViewModel()
    @State private var camera = WorkflowCanvasCamera()
    @State private var viewportSize = CGSize.zero
    @State private var isShowingIssues = false
    @State private var isImporting = false
    @State private var exportRequest: WorkflowExportRequest?
    @State private var packEditor: WorkflowPackEditorMode?
    @Environment(\.undoManager)
    private var undoManager

    var body: some View {
        HSplitView {
            WorkflowPalette(viewModel: viewModel) { item in
                addFromPalette(item)
            } onLoad: { workflowID in
                open(workflowID)
            } onExport: { workflowID in
                exportRequest = WorkflowExportRequest(selection: [workflowID])
            }
            .frame(minWidth: 200, idealWidth: 224, maxWidth: 280)

            canvas
                .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            WorkflowInspectorPane(viewModel: viewModel, onReveal: center(on:))
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 440)
        }
        .navigationTitle("Workflows")
        .toolbar { toolbarContent }
        .task {
            // Idempotent: the scheduler is app-owned, so opening the editor
            // only makes sure it is up, never restarts it.
            WorkflowScheduler.shared.start()
            await viewModel.refreshLibrary()
            await viewModel.refreshCatalogs()
            viewModel.scheduleValidation()
        }
        .onAppear { viewModel.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in viewModel.undoManager = manager }
        .alert(
            "Workflow",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) { viewModel.errorMessage = nil } },
            message: { Text(viewModel.errorMessage ?? "") }
        )
        .alert(
            "Node Packs",
            isPresented: Binding(
                get: { viewModel.packStore.errorMessage != nil },
                set: { if !$0 { viewModel.packStore.errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) { viewModel.packStore.errorMessage = nil } },
            message: { Text(viewModel.packStore.errorMessage ?? "") }
        )
        .modifier(WorkflowBundleTransfer(
            viewModel: viewModel,
            isImporting: $isImporting,
            exportRequest: $exportRequest,
            packEditor: $packEditor
        ))
    }

    // MARK: - Canvas + overlays

    private var canvas: some View {
        WorkflowCanvasSurface(
            viewModel: viewModel,
            camera: $camera,
            viewportSize: $viewportSize
        )
        .dropDestination(for: WorkflowPaletteItem.self) { items, location in
            var placed = false
            for item in items {
                let position = camera.toGraph(location)
                let centered = CGPoint(
                    x: position.x - WorkflowCanvasMetrics.defaultCardSize.width / 2,
                    y: position.y - WorkflowCanvasMetrics.defaultCardSize.height / 2
                )
                let added = withMotion(Motion.bouncy) { place(item, at: centered) }
                if added != nil { placed = true }
            }
            return placed
        }
        .overlay(alignment: .bottomLeading) { zoomControls }
        .overlay(alignment: .top) { statusStrip }
        .overlay(alignment: .bottom) { hintCapsule }
    }

    private var zoomControls: some View {
        HStack(spacing: Space.hair) {
            zoomButton("minus", "Zoom out (⌘−)") {
                withMotion(Motion.snappy) { camera.magnify(by: 1 / 1.2, about: viewportCenter) }
            }
            .keyboardShortcut("-", modifiers: .command)

            Text(Double(camera.zoom).formatted(.percent.precision(.fractionLength(0))))
                .appType(.monoMetric)
                .foregroundStyle(AppColors.foreground)
                .frame(width: 48)

            zoomButton("plus", "Zoom in (⌘+)") {
                withMotion(Motion.snappy) { camera.magnify(by: 1.2, about: viewportCenter) }
            }
            .keyboardShortcut("=", modifiers: .command)

            Divider().frame(height: 14)

            zoomButton("arrow.down.left.and.arrow.up.right", "Fit to content (⇧⌘0)") {
                fitToContent()
            }
            .keyboardShortcut("0", modifiers: [.command, .shift])

            zoomButton("1.circle", "Actual size (⌘0)") {
                withMotion(Motion.gentle) {
                    camera.magnify(by: 1 / camera.zoom, about: viewportCenter)
                }
            }
            .keyboardShortcut("0", modifiers: .command)
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xs)
        .raSurface(.floating, radius: Radius.pill)
        .padding(Space.md)
    }

    private func zoomButton(
        _ symbol: String, _ help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .appType(.caption)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder private var statusStrip: some View {
        HStack(spacing: Space.sm) {
            if !viewModel.issues.isEmpty {
                issuesChip
            }
            runChip
        }
        .padding(.top, Space.md)
        .motionAware(Motion.standardSpring, value: viewModel.issues)
        .motionAware(Motion.standardSpring, value: viewModel.runPhase)
    }

    private var issuesChip: some View {
        Button {
            isShowingIssues = true
        } label: {
            Label(
                "\(viewModel.issues.count) problem\(viewModel.issues.count == 1 ? "" : "s")",
                systemImage: "exclamationmark.triangle.fill"
            )
            .appType(.chip)
            .foregroundStyle(AppColors.warningText)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .raSurface(.floating, radius: Radius.pill)
        .popover(isPresented: $isShowingIssues, arrowEdge: .bottom) {
            issuesList
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var issuesList: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            ForEach(viewModel.issues) { issue in
                Button {
                    isShowingIssues = false
                    if let nodeID = issue.nodeID {
                        viewModel.select(nodeID, additive: false)
                        center(on: nodeID)
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
        .padding(Space.lg)
        .frame(minWidth: 260, maxWidth: 360, alignment: .leading)
    }

    @ViewBuilder private var runChip: some View {
        switch viewModel.runPhase {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: Space.sm) {
                Circle()
                    .fill(AppColors.brand)
                    .frame(width: Control.dot, height: Control.dot)
                    .phaseAnimator([0.3, 1.0]) { view, opacity in
                        view.opacity(opacity)
                    } animation: { _ in .easeInOut(duration: 0.6) }
                Text("Running…")
                    .appType(.chip)
                    .foregroundStyle(AppColors.foreground)
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)
            .raSurface(.floating, radius: Radius.pill)
            .transition(.move(edge: .top).combined(with: .opacity))
        case let .finished(state, duration):
            Label(finishSummary(state, duration), systemImage: finishSymbol(state))
                .appType(.chip)
                .foregroundStyle(finishColor(state))
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.xs)
                .raSurface(.floating, radius: Radius.pill)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func finishSummary(_ state: RAWorkflowRunState, _ duration: TimeInterval) -> String {
        let seconds = duration.formatted(.number.precision(.fractionLength(1)))
        switch state {
        case .succeeded: return "Finished in \(seconds)s"
        case .failed: return "Failed after \(seconds)s"
        case .cancelled: return "Cancelled"
        case .running, .unspecified, .UNRECOGNIZED: return "Run ended"
        }
    }

    private func finishSymbol(_ state: RAWorkflowRunState) -> String {
        switch state {
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "flag.checkered"
        }
    }

    private func finishColor(_ state: RAWorkflowRunState) -> Color {
        switch state {
        case .succeeded: return AppColors.successText
        case .failed: return AppColors.dangerText
        default: return AppColors.mutedForeground
        }
    }

    @ViewBuilder private var hintCapsule: some View {
        if viewModel.draft != nil {
            hint("link", "Drop on a highlighted input · ⎋ cancels")
        } else if viewModel.graph.nodes.count <= 1 && viewModel.graph.edges.isEmpty {
            hint("hand.draw", "Drag nodes in from the palette, then drag an output dot to an input")
        }
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .appType(.caption)
            .foregroundStyle(AppColors.mutedForeground)
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.xs)
            .raSurface(.floating, radius: Radius.pill)
            .padding(.bottom, Space.md)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                viewModel.newWorkflow()
                fitToContent()
            } label: {
                Label("New", systemImage: "doc.badge.plus")
            }
            .help("New workflow")

            Menu {
                Button("Export…") {
                    exportRequest = WorkflowExportRequest(selection: [viewModel.workflowID])
                }
                Button("Import…") { isImporting = true }
                Divider()
                Button("Save as Node Pack…") { packEditor = .composite }
                Button("New Script Pack…") { packEditor = .script }
            } label: {
                Label("Share", systemImage: "shippingbox")
            }
            .help("Export or import a bundle, or turn this graph into a node pack")
        }

        ToolbarItem(placement: .principal) {
            TextField("Workflow name", text: $viewModel.workflowName)
                .textFieldStyle(.roundedBorder)
                .appType(.body)
                .frame(width: 220)
        }

        ToolbarItemGroup {
            Button {
                viewModel.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .help("Undo (⌘Z)")
            .disabled(!viewModel.canUndo)

            Button {
                viewModel.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .help("Redo (⇧⌘Z)")
            .disabled(!viewModel.canRedo)

            Button {
                Task { await viewModel.save() }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .help("Save workflow (⌘S)")
            .keyboardShortcut("s", modifiers: .command)

            if viewModel.isRunning {
                Button {
                    viewModel.cancelRun()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Cancel the run")
            } else {
                Button {
                    Task { await viewModel.run() }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .help("Save and run (⌘R)")
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel.graph.nodes.isEmpty)
            }
        }
    }

    // MARK: - Camera moves

    private var viewportCenter: CGPoint {
        CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
    }

    private func fitToContent() {
        guard let bounds = viewModel.graph.boundingRect(), viewportSize != .zero else {
            withMotion(Motion.gentle) { camera = WorkflowCanvasCamera() }
            return
        }
        let padded = bounds.insetBy(dx: -64, dy: -64)
        let zoom = min(
            max(
                min(viewportSize.width / padded.width, viewportSize.height / padded.height),
                WorkflowCanvasMetrics.minZoom
            ),
            1.25
        )
        withMotion(Motion.gentle) {
            camera.zoom = zoom
            camera.pan = CGSize(
                width: viewportCenter.x - padded.midX * zoom,
                height: viewportCenter.y - padded.midY * zoom
            )
        }
    }

    private func center(on nodeID: String) {
        guard let node = viewModel.graph.node(nodeID) else { return }
        let frame = WorkflowCanvasMetrics.cardFrame(of: node)
        withMotion(Motion.gentle) {
            camera.pan = CGSize(
                width: viewportCenter.x - frame.midX * camera.zoom,
                height: viewportCenter.y - frame.midY * camera.zoom
            )
        }
    }

    private func addFromPalette(_ item: WorkflowPaletteItem) {
        let center = camera.toGraph(viewportCenter)
        let cascade = CGFloat(viewModel.graph.nodes.count % 5) * 28
        let position = CGPoint(
            x: center.x - WorkflowCanvasMetrics.defaultCardSize.width / 2 + cascade,
            y: center.y - WorkflowCanvasMetrics.defaultCardSize.height / 2 + cascade
        )
        withMotion(Motion.bouncy) {
            _ = place(item, at: position)
        }
    }

    /// A pack node's shape is mirrored from the pack right here, at drop time,
    /// the same way a tool node mirrors its tool's arguments.
    private func place(_ item: WorkflowPaletteItem, at position: CGPoint) -> WorkflowNode? {
        switch item {
        case .kind(let kind):
            return viewModel.addNode(kind, at: position)
        case .pack(let id):
            guard let pack = viewModel.packStore.pack(id) else {
                viewModel.errorMessage = "That node pack is no longer installed."
                return nil
            }
            return viewModel.addPackNode(pack, at: position)
        }
    }

    private func open(_ workflowID: String) {
        Task {
            await viewModel.load(id: workflowID)
            fitToContent()
        }
    }
}

#Preview {
    NavigationStack {
        WorkflowCanvasView()
    }
    .frame(width: 1280, height: 800)
}

#endif
