//
//  WorkflowCanvasSurface.swift
//  RunAnywhereAI
//
//  The graph viewport: grid, edges, live rope, marquee, and the node layer.
//
//  Coordinate model. Node positions live in graph space and are never stored
//  scaled. The camera maps graph→view once (`view = graph × zoom + pan`); the
//  node layer applies that same mapping as a single scaleEffect + offset, and
//  every gesture converts through the shared named coordinate space — which
//  sits on the unscaled container, so a location read there is view space by
//  construction regardless of the zoom.
//
//  The grid, every edge, and the dragged rope draw in one Canvas pass. Nodes
//  stay real views because they host controls; an edge per view is what makes
//  a graph editor drop frames while panning.
//

#if os(macOS)

import AppKit
import SwiftUI

struct WorkflowCanvasCamera: Equatable {
    var zoom = CGFloat(1)
    var pan = CGSize(width: 48, height: 48)

    func toView(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * zoom + pan.width, y: point.y * zoom + pan.height)
    }

    func toGraph(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - pan.width) / zoom, y: (point.y - pan.height) / zoom)
    }

    /// Rescale keeping the graph point under `viewPoint` stationary, which is
    /// what makes zooming at the cursor feel like zooming *into* that spot.
    mutating func magnify(by factor: CGFloat, about viewPoint: CGPoint) {
        let target = min(max(zoom * factor, WorkflowCanvasMetrics.minZoom), WorkflowCanvasMetrics.maxZoom)
        guard target != zoom else { return }
        let scale = target / zoom
        pan = CGSize(
            width: viewPoint.x - (viewPoint.x - pan.width) * scale,
            height: viewPoint.y - (viewPoint.y - pan.height) * scale
        )
        zoom = target
    }
}

struct WorkflowCanvasSurface: View {
    @Bindable var viewModel: WorkflowEditorViewModel
    @Binding var camera: WorkflowCanvasCamera
    @Binding var viewportSize: CGSize

    @State private var dragMode: CanvasDragMode?
    @State private var marqueeRect: CGRect?
    @State private var marqueeBase: Set<String> = []
    @State private var hoveredEdgeID: String?
    @FocusState private var isFocused: Bool

    static let coordinateSpace = "workflow-canvas"

    private enum CanvasDragMode: Equatable {
        case pan(startPan: CGSize)
        case marquee
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            drawing
                .gesture(tapGesture)
                .gesture(panOrMarqueeGesture)

            nodeLayer

            edgeDeleteAffordance
        }
        .coordinateSpace(name: Self.coordinateSpace)
        .background(AppColors.background)
        .background(ScrollPinchCapture(onScroll: handleScroll, onMagnify: handleMagnify))
        .clipped()
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onDeleteCommand { withMotion { viewModel.deleteSelection() } }
        .onExitCommand {
            viewModel.cancelDraft()
            viewModel.clearSelection()
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            viewportSize = size
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                hoveredEdgeID = viewModel.draft == nil ? edgeID(at: location) : nil
            case .ended:
                hoveredEdgeID = nil
            }
        }
        // Selecting anything pulls key focus here so ⌫ deletes it immediately,
        // without an extra click on the canvas background.
        .onChange(of: viewModel.selectedNodeIDs) { _, ids in
            if !ids.isEmpty { isFocused = true }
        }
        .onChange(of: viewModel.selectedEdgeID) { _, id in
            if id != nil { isFocused = true }
        }
    }

    // MARK: - Drawing

    private var drawing: some View {
        Canvas { context, size in
            drawGrid(in: &context, size: size)
            for edge in viewModel.graph.edges {
                draw(edge, in: &context)
            }
            drawDraft(in: &context)
            drawMarquee(in: &context)
        }
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        let spacing = 24 * camera.zoom
        guard spacing > 8 else { return }

        let dot = AppColors.mutedForeground.opacity(0.22)
        let diameter = 1.6 * max(1, camera.zoom * 0.9)
        var x = camera.pan.width.truncatingRemainder(dividingBy: spacing)
        if x > 0 { x -= spacing }
        while x < size.width {
            var y = camera.pan.height.truncatingRemainder(dividingBy: spacing)
            if y > 0 { y -= spacing }
            while y < size.height {
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                    with: .color(dot)
                )
                y += spacing
            }
            x += spacing
        }
    }

    private func draw(_ edge: WorkflowEdge, in context: inout GraphicsContext) {
        guard let endpoints = endpoints(of: edge) else { return }
        let path = ropePath(from: endpoints.start, to: endpoints.end)
        let tint = edge.fromPort.tint
        let isSelected = viewModel.selectedEdgeID == edge.id
        let isHovered = hoveredEdgeID == edge.id

        // A wide faint pass under the line reads as a soft glow and keeps the
        // rope legible where it crosses the dot grid.
        context.stroke(
            path,
            with: .color(tint.opacity(isSelected ? 0.34 : 0.16)),
            style: StrokeStyle(lineWidth: (isSelected ? 8 : 6) * camera.zoom, lineCap: .round)
        )
        context.stroke(
            path,
            with: .color(tint.opacity(isSelected || isHovered ? 1 : 0.85)),
            style: StrokeStyle(
                lineWidth: (isSelected || isHovered ? 3 : 2) * camera.zoom,
                lineCap: .round
            )
        )

        drawDirectionArrow(on: endpoints, tint: tint, in: &context)
    }

    /// A small chevron at the rope's midpoint, pointing along the flow — the
    /// sockets mark the ends, this marks the direction.
    private func drawDirectionArrow(
        on endpoints: (start: CGPoint, end: CGPoint),
        tint: Color,
        in context: inout GraphicsContext
    ) {
        let controls = ropeControls(from: endpoints.start, to: endpoints.end)
        let mid = cubicPoint(0.5, endpoints.start, controls.0, controls.1, endpoints.end)
        let tangent = cubicTangent(0.5, endpoints.start, controls.0, controls.1, endpoints.end)
        let length = max(hypot(tangent.x, tangent.y), 0.001)
        let direction = CGPoint(x: tangent.x / length, y: tangent.y / length)
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let size = 4.5 * camera.zoom

        var arrow = Path()
        arrow.move(to: CGPoint(x: mid.x + direction.x * size, y: mid.y + direction.y * size))
        arrow.addLine(to: CGPoint(
            x: mid.x - direction.x * size + normal.x * size,
            y: mid.y - direction.y * size + normal.y * size
        ))
        arrow.addLine(to: CGPoint(
            x: mid.x - direction.x * size - normal.x * size,
            y: mid.y - direction.y * size - normal.y * size
        ))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(tint))
    }

    private func drawDraft(in context: inout GraphicsContext) {
        guard let draft = viewModel.draft,
              let source = viewModel.graph.node(draft.fromNode) else { return }

        let start = camera.toView(
            WorkflowCanvasMetrics.outputAnchor(of: source, port: draft.fromPort)
        )
        let snapped = draft.snappedTarget.flatMap { endpoint in
            viewModel.graph.node(endpoint.nodeID).flatMap {
                WorkflowCanvasMetrics.inputAnchor(of: $0, port: endpoint.port)
            }
        }
        let end = snapped.map(camera.toView) ?? camera.toView(draft.cursor)

        let tint = draft.fromPort.tint
        let path = ropePath(from: start, to: end)

        context.stroke(
            path,
            with: .color(tint.opacity(snapped == nil ? 0.55 : 0.95)),
            style: StrokeStyle(
                lineWidth: 2.5 * camera.zoom,
                lineCap: .round,
                dash: snapped == nil ? [6 * camera.zoom, 5 * camera.zoom] : []
            )
        )

        let radius = (snapped == nil ? 4 : 6.5) * camera.zoom
        context.fill(
            Path(ellipseIn: CGRect(
                x: end.x - radius, y: end.y - radius, width: radius * 2, height: radius * 2
            )),
            with: .color(tint.opacity(snapped == nil ? 0.6 : 1))
        )
    }

    private func drawMarquee(in context: inout GraphicsContext) {
        guard let rect = marqueeRect else { return }
        let path = Path(rect)
        context.fill(path, with: .color(AppColors.brand.opacity(0.08)))
        context.stroke(path, with: .color(AppColors.brand.opacity(0.7)), lineWidth: 1)
    }

    // MARK: - Edge geometry

    /// Both ends resolve through the same per-port geometry the sockets are
    /// drawn with, so a rope always lands on the dot it is attached to however
    /// many inputs the target grew.
    private func endpoints(of edge: WorkflowEdge) -> (start: CGPoint, end: CGPoint)? {
        guard let from = viewModel.graph.node(edge.fromNode),
              let to = viewModel.graph.node(edge.toNode),
              let inputAnchor = WorkflowCanvasMetrics.inputAnchor(of: to, port: edge.toPort)
        else { return nil }
        return (
            camera.toView(WorkflowCanvasMetrics.outputAnchor(of: from, port: edge.fromPort)),
            camera.toView(inputAnchor)
        )
    }

    /// Horizontal control points, so the curve reads as left-to-right flow
    /// even when the target sits above or behind the source.
    private func ropeControls(from start: CGPoint, to end: CGPoint) -> (CGPoint, CGPoint) {
        let reach = max(56 * camera.zoom, abs(end.x - start.x) * 0.45)
        return (
            CGPoint(x: start.x + reach, y: start.y),
            CGPoint(x: end.x - reach, y: end.y)
        )
    }

    private func ropePath(from start: CGPoint, to end: CGPoint) -> Path {
        let controls = ropeControls(from: start, to: end)
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: controls.0, control2: controls.1)
        return path
    }

    private func cubicPoint(
        _ at: CGFloat, _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint
    ) -> CGPoint {
        let rem = 1 - at
        let x = rem * rem * rem * p0.x + 3 * rem * rem * at * p1.x
            + 3 * rem * at * at * p2.x + at * at * at * p3.x
        let y = rem * rem * rem * p0.y + 3 * rem * rem * at * p1.y
            + 3 * rem * at * at * p2.y + at * at * at * p3.y
        return CGPoint(x: x, y: y)
    }

    private func cubicTangent(
        _ at: CGFloat, _ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint
    ) -> CGPoint {
        let rem = 1 - at
        let x = 3 * rem * rem * (p1.x - p0.x) + 6 * rem * at * (p2.x - p1.x)
            + 3 * at * at * (p3.x - p2.x)
        let y = 3 * rem * rem * (p1.y - p0.y) + 6 * rem * at * (p2.y - p1.y)
            + 3 * at * at * (p3.y - p2.y)
        return CGPoint(x: x, y: y)
    }

    /// Nearest edge within a click's tolerance, by sampling each rope. A few
    /// dozen samples across a handful of edges is nothing per click.
    private func edgeID(at point: CGPoint, tolerance: CGFloat = 7) -> String? {
        var best: (id: String, distance: CGFloat)?
        for edge in viewModel.graph.edges {
            guard let endpoints = endpoints(of: edge) else { continue }
            let controls = ropeControls(from: endpoints.start, to: endpoints.end)
            for step in 0...24 {
                let fraction = CGFloat(step) / 24
                let sample = cubicPoint(
                    fraction, endpoints.start, controls.0, controls.1, endpoints.end
                )
                let distance = hypot(sample.x - point.x, sample.y - point.y)
                if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                    best = (edge.id, distance)
                }
            }
        }
        return best?.id
    }

    private func edgeMidpoint(_ edgeID: String) -> CGPoint? {
        guard let edge = viewModel.graph.edges.first(where: { $0.id == edgeID }),
              let endpoints = endpoints(of: edge) else { return nil }
        let controls = ropeControls(from: endpoints.start, to: endpoints.end)
        return cubicPoint(0.5, endpoints.start, controls.0, controls.1, endpoints.end)
    }

    // MARK: - Node layer

    private var nodeLayer: some View {
        ZStack(alignment: .topLeading) {
            ForEach(viewModel.graph.nodes) { node in
                WorkflowNodeCard(viewModel: viewModel, node: node, camera: camera)
                    .offset(
                        x: node.position.x - WorkflowCanvasMetrics.socketMargin,
                        y: node.position.y
                    )
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        // Viewport-sized and pinned top-left — never a fixed canvas-sized
        // frame. A frame larger than the pane overflows, gets centred by the
        // parent, and puts graph origin off-screen; `offset` is a render
        // transform and grows no layout, so this frame stays pane-sized no
        // matter where nodes sit.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scaleEffect(camera.zoom, anchor: .topLeading)
        .offset(camera.pan)
        .motionAware(Motion.standardSpring, value: viewModel.graph.nodes.map(\.id))
    }

    @ViewBuilder private var edgeDeleteAffordance: some View {
        if let edgeID = viewModel.selectedEdgeID, let mid = edgeMidpoint(edgeID) {
            Button {
                withMotion { viewModel.deleteEdge(edgeID) }
            } label: {
                Image(systemName: "xmark")
                    .appType(.chip)
                    .foregroundStyle(AppColors.dangerText)
                    .frame(width: 22, height: 22)
                    .background(AppColors.surfaceFloating, in: Circle())
                    .overlay(Circle().strokeBorder(AppColors.danger, lineWidth: Stroke.regular))
            }
            .buttonStyle(.plain)
            .help("Remove this connection (⌫)")
            .position(mid)
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Gestures

    private var tapGesture: some Gesture {
        SpatialTapGesture(coordinateSpace: .local)
            .onEnded { value in
                isFocused = true
                if let edgeID = edgeID(at: value.location) {
                    viewModel.selectEdge(edgeID)
                } else {
                    viewModel.clearSelection()
                }
            }
    }

    /// One drag, two meanings, decided once at the first event: plain drag
    /// pans the camera, ⇧-drag sweeps a marquee. Both compute from values
    /// captured at drag start plus the cumulative translation.
    private var panOrMarqueeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                if dragMode == nil {
                    if NSEvent.modifierFlags.contains(.shift) {
                        dragMode = .marquee
                        marqueeBase = viewModel.selectedNodeIDs
                    } else {
                        dragMode = .pan(startPan: camera.pan)
                    }
                }
                switch dragMode {
                case .pan(let startPan):
                    camera.pan = CGSize(
                        width: startPan.width + value.translation.width,
                        height: startPan.height + value.translation.height
                    )
                case .marquee:
                    let rect = CGRect(
                        x: min(value.startLocation.x, value.location.x),
                        y: min(value.startLocation.y, value.location.y),
                        width: abs(value.translation.width),
                        height: abs(value.translation.height)
                    )
                    marqueeRect = rect
                    viewModel.setMarqueeSelection(nodeIDs(in: rect), base: marqueeBase)
                case nil:
                    break
                }
            }
            .onEnded { _ in
                dragMode = nil
                marqueeRect = nil
                marqueeBase = []
            }
    }

    private func nodeIDs(in viewRect: CGRect) -> Set<String> {
        Set(
            viewModel.graph.nodes.compactMap { node -> String? in
                let frame = WorkflowCanvasMetrics.cardFrame(of: node)
                let viewFrame = CGRect(
                    origin: camera.toView(frame.origin),
                    size: CGSize(width: frame.width * camera.zoom, height: frame.height * camera.zoom)
                )
                return viewFrame.intersects(viewRect) ? node.id : nil
            }
        )
    }

    // MARK: - Wheel and pinch

    /// Trackpad scroll pans; pinch, ⌘-scroll, and a clicky mouse wheel zoom
    /// at the cursor. The precise/imprecise split is what tells the two input
    /// devices apart.
    private func handleScroll(
        delta: CGSize, location: CGPoint, isPrecise: Bool, isCommandDown: Bool
    ) {
        if isCommandDown || !isPrecise {
            let factor = exp(delta.height * (isPrecise ? 0.012 : 0.05))
            camera.magnify(by: factor, about: location)
        } else {
            camera.pan.width += delta.width
            camera.pan.height += delta.height
        }
    }

    private func handleMagnify(factor: CGFloat, location: CGPoint) {
        camera.magnify(by: factor, about: location)
    }
}

// MARK: - Wheel/pinch capture

/// Routes scroll-wheel and pinch events over the canvas into SwiftUI.
///
/// SwiftUI has no scroll-wheel API on macOS, and an NSView placed in the
/// hierarchy to receive them would also swallow the clicks SwiftUI needs. So
/// the view is transparent to hit-testing and listens through a local event
/// monitor instead, claiming only scroll and magnify events whose location
/// falls inside its own bounds — events over the palette or the inspector
/// pass through untouched.
private struct ScrollPinchCapture: NSViewRepresentable {
    let onScroll: (_ delta: CGSize, _ location: CGPoint, _ isPrecise: Bool, _ isCommandDown: Bool) -> Void
    let onMagnify: (_ factor: CGFloat, _ location: CGPoint) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onScroll = onScroll
        view.onMagnify = onMagnify
        return view
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        view.onScroll = onScroll
        view.onMagnify = onMagnify
    }

    final class CaptureView: NSView {
        var onScroll: ((CGSize, CGPoint, Bool, Bool) -> Void)?
        var onMagnify: ((CGFloat, CGPoint) -> Void)?
        private var monitor: Any?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.scrollWheel, .magnify]
            ) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let location = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(location) else { return event }

                switch event.type {
                case .scrollWheel:
                    self.onScroll?(
                        CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY),
                        location,
                        event.hasPreciseScrollingDeltas,
                        event.modifierFlags.contains(.command)
                    )
                    return nil
                case .magnify:
                    self.onMagnify?(1 + event.magnification, location)
                    return nil
                default:
                    return event
                }
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            removeMonitor()
        }
    }
}

/// Ropes into a named tool argument, into a numbered Merge input, and out of a
/// pack's named output — the geometry a fixed anchor used to get wrong.
#Preview("Per-port edges") {
    @Previewable @State var camera = WorkflowCanvasCamera()
    @Previewable @State var viewportSize = CGSize.zero
    let viewModel = WorkflowEditorViewModel()
    viewModel.packStore.seedForPreview([WorkflowPreviewFixtures.installedPack])
    viewModel.mutate { $0 = WorkflowPreviewFixtures.cardGallery }

    return WorkflowCanvasSurface(
        viewModel: viewModel,
        camera: $camera,
        viewportSize: $viewportSize
    )
    .frame(width: 1240, height: 620)
}

#endif
