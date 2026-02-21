#if os(macOS)
//
//  MacAppDelegate.swift
//  YapRun
//
//  NSApplicationDelegate managing agent app lifecycle, menu bar, and hub window.
//

import AppKit
import SwiftUI
import RunAnywhere
import ONNXRuntime
import os

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {

    private let logger = Logger(subsystem: "com.runanywhere.yaprun", category: "AppDelegate")
    private var menuBarManager: MenuBarManager?
    private var hubWindow: NSWindow?
    private var flowBarWindow: FlowBarWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize SDK
        Task { await initializeSDK() }

        // Menu bar
        menuBarManager = MenuBarManager(
            onOpenHub: { [weak self] in self?.showHub() },
            onQuit: { NSApp.terminate(nil) }
        )
        menuBarManager?.setup()
        logger.info("Menu bar set up")

        // Flow Bar
        if UserDefaults.standard.object(forKey: "showFlowBar") == nil {
            UserDefaults.standard.set(true, forKey: "showFlowBar")
        }
        if UserDefaults.standard.bool(forKey: "showFlowBar") {
            showFlowBar()
        }

        // Dictation Service (installs global hotkey if accessibility granted)
        MacDictationService.shared.start()

        // Show hub on first launch
        showHub()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MacDictationService.shared.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            showHub()
        }
        return true
    }

    // MARK: - SDK Initialization

    private func initializeSDK() async {
        do {
            ONNX.register(priority: 100)
            try RunAnywhere.initialize()
            logger.info("SDK initialized")

            ModelRegistry.registerAll()
            logger.info("ASR models registered")
        } catch {
            logger.error("SDK initialization failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Hub Window

    func showHub() {
        if let existing = hubWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "YapRun"
        window.center()
        window.minSize = NSSize(width: 640, height: 480)
        window.contentView = NSHostingView(rootView: MacHubView())
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(AppColors.backgroundPrimaryDark)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        hubWindow = window
    }

    // MARK: - Flow Bar

    func showFlowBar() {
        guard flowBarWindow == nil else {
            flowBarWindow?.orderFront(nil)
            return
        }
        let window = FlowBarWindow()
        window.orderFront(nil)
        flowBarWindow = window
    }

    func hideFlowBar() {
        flowBarWindow?.orderOut(nil)
        flowBarWindow = nil
    }
}

#endif
