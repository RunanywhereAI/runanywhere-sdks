//
//  WorkflowNodeCard.swift
//  RunAnywhereAI
//
//  One node on the canvas: category-tinted header, name, live parameter
//  summary, run status, and the sockets.
//
//  The card's frame is wider than the visible card by `socketMargin` on each
//  side, and the sockets sit inside that slack. SwiftUI does not hit-test
//  child content outside its parent's frame, so a socket hanging out of an
//  overlay renders but can never be grabbed — the slack keeps every grabbable
//  pixel inside the frame.
//
//  A node with more than one input (Merge, and a Tool node once its arguments
//  are known) grows a rail of labelled rows under the details band, one row per
//  input. Outputs stay centred on the details band regardless, so the main flow
//  through a tall tool node still lines up with everything else.
//

#if os(macOS)

import AppKit
import SwiftUI

struct WorkflowNodeCard: View {
    var viewModel: WorkflowEditorViewModel
    let node: WorkflowNode
    let camera: WorkflowCanvasCamera

    @State private var isHovered = false

    private let margin = WorkflowCanvasMetrics.socketMargin

    private var cardSize: CGSize { WorkflowCanvasMetrics.cardSize(of: node) }
    private var status: WorkflowNodeStatus { viewModel.status(of: node.id) }
    private var isSelected: Bool { viewModel.selectedNodeIDs.contains(node.id) }
    private var isSnapTarget: Bool { viewModel.draft?.snappedTarget?.nodeID == node.id }
    private var isDraftCandidate: Bool { viewModel.draftCandidateNodes.contains(node.id) }
    private var nodeIssues: [WorkflowIssue] { viewModel.issues(for: node.id) }
    private var outputPorts: [WorkflowOutputPort] { node.outputPorts }
    private var hasBranchingOutput: Bool { outputPorts.count > 1 }

    /// Title, symbol, and accent. A built-in kind answers from its descriptor;
    /// a pack node answers from the installed pack, or reports the id it could
    /// not find so the card can draw a placeholder instead of an empty header.
    private var presentation: WorkflowNodePresentation { viewModel.presentation(of: node) }

    var body: some View {
        card
            .frame(width: cardSize.width, height: cardSize.height)
            .frame(width: cardSize.width + margin * 2, height: cardSize.height)
            .overlay(socketLayer)
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 0) {
            header
            details
            if WorkflowCanvasMetrics.hasRail(node) {
                portRail
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .background(
            AppColors.surface,
            in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(outlineColor, style: outlineStyle)
        )
        .overlay(runningPulse)
        .overlay(alignment: .topTrailing) { issueBadge }
        .shadow(
            color: Color.black.opacity(isSelected || isHovered ? 0.22 : 0.12),
            radius: isSelected || isHovered ? 11 : 6,
            y: 3
        )
        .scaleEffect(isSnapTarget ? 1.03 : 1)
        .motionAware(Motion.snappy, value: isSnapTarget)
        .motionAware(Motion.microFade, value: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onHover { isHovered = $0 }
        .gesture(selectTap)
        .gesture(moveDrag)
        .contextMenu {
            if !node.kind.isTrigger {
                Button("Duplicate") {
                    viewModel.select(node.id, additive: false)
                    withMotion { viewModel.duplicateSelection() }
                }
                Divider()
            }
            Button("Delete", role: .destructive) {
                viewModel.select(node.id, additive: false)
                withMotion { viewModel.deleteSelection() }
            }
        }
        .motionAware(Motion.standardSpring, value: status)
    }

    private var header: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: presentation.systemImage)
                .appType(.chip)
                .foregroundStyle(presentation.accent)
                .frame(width: 20, height: 20)
                .background(
                    presentation.accent.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                )

            Text(presentation.title.uppercased())
                .appType(.overline)
                .foregroundStyle(AppColors.mutedForeground)
                .lineLimit(1)

            Spacer(minLength: 0)

            statusBadge
        }
        .padding(.horizontal, Space.md)
        .frame(height: WorkflowCanvasMetrics.headerHeight)
        .frame(maxWidth: .infinity)
        .background(presentation.accent.opacity(0.10))
    }

    private var details: some View {
        let height = WorkflowCanvasMetrics.detailsHeight(of: node)
        return VStack(alignment: .leading, spacing: Space.hair) {
            Text(node.name)
                .appType(.cardTitle)
                .foregroundStyle(AppColors.foreground)
                .lineLimit(1)

            Text(summaryText)
                .appType(.caption)
                .foregroundStyle(summaryColor)
                .lineLimit(2)

            if presentation.isMissing {
                Label("Install the pack to run this node", systemImage: "shippingbox.badge.clock")
                    .appType(.chip)
                    .foregroundStyle(AppColors.warningText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.trailing, hasBranchingOutput ? Self.captionWidth + Space.md : 0)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
    }

    // MARK: - Input rail

    private var portRail: some View {
        VStack(spacing: 0) {
            ForEach(node.inputPorts) { port in
                railRow(port)
            }
        }
        .padding(.top, WorkflowCanvasMetrics.railTopPadding)
        .padding(.bottom, WorkflowCanvasMetrics.railBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surfaceSunken)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.borderSubtle)
                .frame(height: Hairline.width)
        }
    }

    private func railRow(_ port: WorkflowInputPort) -> some View {
        HStack(spacing: Space.xs) {
            Text(port.name)
                .appType(.chip)
                .foregroundStyle(
                    port.isArgument ? AppColors.foreground : AppColors.mutedForeground
                )
                .lineLimit(1)

            Spacer(minLength: Space.xs)

            portStateBadge(port)
        }
        .padding(.leading, Space.md)
        .padding(.trailing, Space.sm)
        .frame(height: WorkflowCanvasMetrics.portRowHeight)
    }

    @ViewBuilder
    private func portStateBadge(_ port: WorkflowInputPort) -> some View {
        if let argument = node.argumentPorts.first(where: { $0.name == port.name }) {
            switch viewModel.toolArgumentState(node, port: argument) {
            case .wired:
                badge("link", AppColors.brand, "Wired from another node")
            case .literal:
                badge("textformat", AppColors.mutedForeground, "Set in the inspector")
            case .missing:
                badge("exclamationmark.triangle.fill", AppColors.warning, "Required and not set")
            case .unset:
                Text(argument.typeLabel)
                    .appType(.chip)
                    .foregroundStyle(AppColors.mutedForeground.opacity(0.7))
            }
        } else if viewModel.graph.isInputConnected(node.id, port: port.name) {
            badge("link", AppColors.brand, "Connected")
        }
    }

    private func badge(_ symbol: String, _ tint: Color, _ help: String) -> some View {
        Image(systemName: symbol)
            .appType(.chip)
            .foregroundStyle(tint)
            .help(help)
    }

    private var summaryText: String {
        if case .failed(let message) = status { return message }
        return node.parameterSummary
    }

    private var summaryColor: Color {
        if case .failed = status { return AppColors.dangerText }
        return presentation.isMissing ? AppColors.warningText : AppColors.mutedForeground
    }

    @ViewBuilder private var statusBadge: some View {
        switch status {
        case .idle:
            EmptyView()
        case .running:
            // A pulsing dot rather than a spinner: it reads at a glance across
            // a whole graph and does not fight the header's own motion.
            Circle()
                .fill(AppColors.brand)
                .frame(width: Control.dot, height: Control.dot)
                .phaseAnimator([0.35, 1.0]) { view, opacity in
                    view.opacity(opacity)
                } animation: { _ in .easeInOut(duration: 0.6) }
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .appType(.chip)
                .foregroundStyle(AppColors.success)
                .transition(.scale.combined(with: .opacity))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .appType(.chip)
                .foregroundStyle(AppColors.danger)
                .transition(.scale.combined(with: .opacity))
        case .skipped:
            Image(systemName: "minus.circle")
                .appType(.chip)
                .foregroundStyle(AppColors.mutedForeground)
        }
    }

    @ViewBuilder private var runningPulse: some View {
        if status == .running {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(AppColors.brand, lineWidth: Stroke.emphasis)
                .phaseAnimator([0.25, 0.9]) { view, opacity in
                    view.opacity(opacity)
                } animation: { _ in .easeInOut(duration: 0.6) }
        }
    }

    @ViewBuilder private var issueBadge: some View {
        if !nodeIssues.isEmpty, status == .idle {
            Image(systemName: "exclamationmark.triangle.fill")
                .appType(.chip)
                .foregroundStyle(AppColors.warning)
                .padding(Space.xs)
                .help(nodeIssues.map(\.message).joined(separator: "\n"))
        }
    }

    private var outlineColor: Color {
        if isSnapTarget { return AppColors.success }
        if isSelected { return AppColors.brand }
        if presentation.isMissing { return AppColors.warning }
        switch status {
        case .idle:
            return isDraftCandidate ? AppColors.success.opacity(0.55) : AppColors.border
        case .running: return AppColors.brand.opacity(0.7)
        case .succeeded: return AppColors.success.opacity(0.7)
        case .failed: return AppColors.danger.opacity(0.8)
        case .skipped: return AppColors.border
        }
    }

    /// A missing pack is drawn dashed. It is the one card whose contents are a
    /// stand-in rather than the node itself, and a dashed edge says "placeholder"
    /// at a glance across a whole graph where a tint alone does not.
    private var outlineStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: isSelected || isSnapTarget || status == .running
                ? Stroke.emphasis
                : Stroke.regular,
            dash: presentation.isMissing ? [5, 4] : []
        )
    }

    // MARK: - Gestures

    private var selectTap: some Gesture {
        TapGesture().onEnded {
            viewModel.select(node.id, additive: NSEvent.modifierFlags.contains(.shift))
        }
    }

    /// Position at drag start plus cumulative translation, computed in the
    /// view model from origins captured on the first event. Never
    /// `current + translation`: translation is cumulative, so adding it to a
    /// position that already moved compounds every frame and the node shoots
    /// off the canvas.
    ///
    /// Translation is read in the canvas's named space — outside the layer's
    /// scaleEffect, so it arrives in view points and one division by the zoom
    /// converts it, at any zoom level.
    private var moveDrag: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(WorkflowCanvasSurface.coordinateSpace))
            .onChanged { value in
                viewModel.beginNodeDrag(anchor: node.id)
                viewModel.dragSelection(by: CGSize(
                    width: value.translation.width / camera.zoom,
                    height: value.translation.height / camera.zoom
                ))
            }
            .onEnded { _ in
                viewModel.endNodeDrag()
            }
    }

    // MARK: - Sockets

    private var socketLayer: some View {
        ZStack(alignment: .topLeading) {
            ForEach(node.inputPorts) { port in
                if let offset = WorkflowCanvasMetrics.inputOffsetY(of: node, port: port.name) {
                    inputSocket(port)
                        .position(x: margin, y: offset)
                }
            }

            // One socket per output, and a caption beside it once there is more
            // than one — a bare dot cannot say which branch it is.
            ForEach(outputPorts) { port in
                let offset = WorkflowCanvasMetrics.outputOffsetY(of: node, port: port)
                outputSocket(port)
                    .position(x: margin + cardSize.width, y: offset)
                if hasBranchingOutput {
                    portCaption(port.rawValue, tint: port.tint)
                        .position(
                            x: margin + cardSize.width - 12 - Self.captionWidth / 2,
                            y: offset
                        )
                }
            }
        }
    }

    /// Captions are right-aligned into a fixed box so a pack's long output name
    /// truncates instead of running back across the summary text.
    private static let captionWidth: CGFloat = 44

    private func portCaption(_ label: String, tint: Color) -> some View {
        Text(label)
            .appType(.chip)
            .foregroundStyle(tint)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: Self.captionWidth, alignment: .trailing)
            .allowsHitTesting(false)
    }

    /// The input is a drop target resolved by proximity, not a control, so it
    /// draws state but never intercepts the pointer.
    private func inputSocket(_ port: WorkflowInputPort) -> some View {
        let diameter = WorkflowCanvasMetrics.socketDiameter
        let endpoint = WorkflowEndpoint(nodeID: node.id, port: port.name)
        let isTarget = viewModel.draft?.snappedTarget == endpoint
        let isCandidate = viewModel.draftCandidates.contains(endpoint)
        let connected = viewModel.graph.isInputConnected(node.id, port: port.name)
        let ring = port.isRequired && !connected ? AppColors.warning : AppColors.border

        return Circle()
            .fill(isTarget ? AppColors.success : connected ? AppColors.brand : AppColors.surface)
            .overlay(
                Circle().strokeBorder(
                    isTarget
                        ? AppColors.success
                        : isCandidate ? AppColors.success.opacity(0.8) : ring,
                    lineWidth: Stroke.emphasis
                )
            )
            .frame(
                width: isTarget ? diameter + 5 : diameter,
                height: isTarget ? diameter + 5 : diameter
            )
            .motionAware(Motion.snappy, value: isTarget)
            .allowsHitTesting(false)
    }

    private func outputSocket(_ port: WorkflowOutputPort) -> some View {
        let diameter = WorkflowCanvasMetrics.socketDiameter
        let isDragSource = viewModel.draft?.fromNode == node.id
            && viewModel.draft?.fromPort == port
        let connected = viewModel.graph.isOutputConnected(node.id, port: port)

        return Circle()
            .fill(connected || isDragSource ? port.tint : AppColors.surface)
            .overlay(Circle().strokeBorder(port.tint, lineWidth: Stroke.emphasis))
            .frame(
                width: isDragSource ? diameter + 4 : diameter,
                height: isDragSource ? diameter + 4 : diameter
            )
            .motionAware(Motion.snappy, value: isDragSource)
            // A 14pt dot is a hard grab, and missing it starts a node drag
            // instead — a generous invisible target is kinder than precision.
            .contentShape(Circle().inset(by: -10))
            .gesture(ropeDrag(port))
            .help(port == .out
                ? "Drag to another node's input"
                : "Drag the \(port.rawValue) branch to another node's input")
    }

    /// The rope. The pointer's location in the canvas space converts straight
    /// to graph coordinates through the camera, so snapping and the drawn
    /// curve share one number at every zoom level.
    private func ropeDrag(_ port: WorkflowOutputPort) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(WorkflowCanvasSurface.coordinateSpace))
            .onChanged { value in
                viewModel.updateDraft(
                    from: node.id,
                    port: port,
                    cursor: camera.toGraph(value.location),
                    snapDistance: WorkflowCanvasMetrics.snapRadius / camera.zoom
                )
            }
            .onEnded { _ in
                withMotion(Motion.snappy) { viewModel.completeDraft() }
            }
    }
}

/// Every card shape that is easy to get wrong: a tool node grown by its
/// arguments, a Merge with numbered inputs, a branching Condition, a pack node
/// with two named outputs, and a pack node whose pack is not installed.
#Preview("Card shapes") {
    let viewModel = WorkflowEditorViewModel()
    viewModel.packStore.seedForPreview([WorkflowPreviewFixtures.installedPack])
    viewModel.mutate { $0 = WorkflowPreviewFixtures.cardGallery }

    return ZStack(alignment: .topLeading) {
        AppColors.background
        ForEach(viewModel.graph.nodes) { node in
            WorkflowNodeCard(viewModel: viewModel, node: node, camera: WorkflowCanvasCamera())
                .offset(
                    x: node.position.x - WorkflowCanvasMetrics.socketMargin,
                    y: node.position.y
                )
        }
    }
    .frame(width: 1180, height: 480)
}

#endif
