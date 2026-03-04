#if os(macOS)
//
//  FlowBarWindow.swift
//  YapRun
//
//  Floating NSPanel that shows dictation state — always on top, all Spaces.
//

import AppKit
import SwiftUI

final class FlowBarWindow: NSPanel {

    private let hostingView: NSHostingView<FlowBarView>

    init() {
        let hosting = NSHostingView(rootView: FlowBarView())
        self.hostingView = hosting

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow

        // Prevent NSHostingView from driving window size (avoids constraint loop)
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 48)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting

        positionAtBottomCenter()
    }

    func positionAtBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let x = (screen.frame.width - frame.width) / 2
        let y: CGFloat = 60
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

#endif
