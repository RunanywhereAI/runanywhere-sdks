#if os(macOS)
//
//  MacPermissionService.swift
//  YapRun
//
//  Checks and requests microphone and accessibility permissions on macOS.
//

import AVFoundation
import AppKit
import ApplicationServices

struct MacPermissionService {

    // MARK: - Microphone

    static var microphoneState: MicPermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:                return .granted
        case .denied, .restricted:       return .denied
        case .notDetermined:             return .unknown
        @unknown default:                return .unknown
        }
    }

    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    // MARK: - Accessibility

    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}

#endif
