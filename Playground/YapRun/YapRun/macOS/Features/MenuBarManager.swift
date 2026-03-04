#if os(macOS)
//
//  MenuBarManager.swift
//  YapRun
//
//  NSStatusItem-based menu bar icon with dropdown menu.
//

import AppKit

@MainActor
final class MenuBarManager {

    private var statusItem: NSStatusItem?
    private let onOpenHub: () -> Void
    private let onQuit: () -> Void

    init(onOpenHub: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onOpenHub = onOpenHub
        self.onQuit = onQuit
    }

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "YapRun")
        }

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open YapRun Hub", action: #selector(openHub), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit YapRun", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func openHub() {
        onOpenHub()
    }

    @objc private func quit() {
        onQuit()
    }
}

#endif
