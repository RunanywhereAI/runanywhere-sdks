#if os(macOS)
//
//  MacHotkeyService.swift
//  YapRun
//
//  Global hotkey listener using CGEvent tap for push-to-talk dictation.
//  Requires Accessibility permission.
//

import Cocoa
import Combine
import os

@MainActor
final class MacHotkeyService {

    static let shared = MacHotkeyService()

    // MARK: - Events

    let hotkeyDown = PassthroughSubject<Void, Never>()
    let hotkeyUp = PassthroughSubject<Void, Never>()

    // MARK: - State

    private(set) var isInstalled = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnKeyDown = false
    private let logger = Logger(subsystem: "com.runanywhere.yaprun", category: "Hotkey")

    private init() {}

    // MARK: - Install / Uninstall

    func install() {
        guard !isInstalled else { return }
        guard AXIsProcessTrusted() else {
            logger.warning("Accessibility not granted — cannot install hotkey tap")
            return
        }

        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, _, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let service = Unmanaged<MacHotkeyService>.fromOpaque(userInfo).takeUnretainedValue()
                service.handleEvent(event)
                return Unmanaged.passRetained(event)
            },
            userInfo: userInfo
        ) else {
            logger.error("Failed to create CGEvent tap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        isInstalled = true
        logger.info("Global hotkey tap installed (Fn key)")
    }

    func uninstall() {
        guard isInstalled else { return }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        fnKeyDown = false
        isInstalled = false
        logger.info("Global hotkey tap uninstalled")
    }

    // MARK: - Event Handling

    private nonisolated func handleEvent(_ event: CGEvent) {
        let flags = event.flags
        let fnPressed = flags.contains(.maskSecondaryFn)

        Task { @MainActor in
            if fnPressed && !fnKeyDown {
                fnKeyDown = true
                hotkeyDown.send()
            } else if !fnPressed && fnKeyDown {
                fnKeyDown = false
                hotkeyUp.send()
            }
        }
    }
}

#endif
