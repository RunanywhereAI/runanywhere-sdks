#if os(macOS)
//
//  MacTextInsertionService.swift
//  YapRun
//
//  Inserts text at the cursor position in any app via NSPasteboard + Cmd+V simulation.
//  Requires Accessibility permission.
//

import Cocoa
import os

struct MacTextInsertionService {

    private static let logger = Logger(subsystem: "com.runanywhere.yaprun", category: "TextInsertion")

    static func insertText(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Save current pasteboard
        let previousContents = pasteboard.string(forType: .string)

        // Set transcribed text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V (V key = virtual key code 0x09)
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgSessionEventTap)

        logger.info("Inserted \(text.count) characters via Cmd+V")

        // Restore previous pasteboard after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }
}

#endif
