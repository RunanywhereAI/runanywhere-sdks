//
//  SharedConstants.swift
//  RunAnywhereAI + RunAnywhereKeyboard
//
//  Shared between the main app and keyboard extension targets.
//  Contains all identifiers used for App Group IPC.
//

import Foundation

enum SharedConstants {
    // App Group identifier — must match both targets' entitlements exactly
    static let appGroupID = "group.com.runanywhere.runanywhereai"

    // URL scheme for keyboard → main app deep link (WisprFlow Flow Session trigger)
    static let urlScheme = "runanywhere"
    static let startFlowURLString = "runanywhere://startFlow"

    // App Group UserDefaults keys
    enum Keys {
        static let sessionState = "sessionState"               // FlowSessionState raw value
        static let transcribedText = "transcribedText"         // Final transcription result
        static let returnToAppScheme = "returnToAppScheme"     // Host app URL scheme for bounce-back
        static let preferredSTTModelId = "preferredSTTModelId" // User's chosen STT model
        static let dictationHistory = "dictationHistory"       // JSON-encoded [TranscriptionEntry]
    }

    // Darwin inter-process notification names (CFNotificationCenter)
    // These fire instantly across process boundaries with no polling
    enum DarwinNotifications {
        static let stopRecording = "com.runanywhere.keyboard.stopRecording"
        static let transcriptionReady = "com.runanywhere.keyboard.transcriptionReady"
    }

    // Curated map of host app bundle IDs → URL schemes for bounce-back (WisprFlow approach).
    // For apps not in this list the user must switch back manually — this is a known iOS constraint.
    static let knownAppSchemes: [String: String] = [
        "com.apple.MobileSMS":             "sms://",
        "com.apple.mobilesafari":          "https://www.google.com",
        "com.apple.mobilemail":            "message://",
        "com.apple.Notes":                 "mobilenotes://",
        "com.apple.reminders":             "x-apple-reminder://",
        "com.google.Gmail":                "googlegmail://",
        "com.google.chrome.app":           "googlechrome://",
        "com.atebits.Tweetie2":            "twitter://",
        "com.burbn.instagram":             "instagram://",
        "com.hammerandchisel.discord":     "discord://",
        "com.tinyspeck.chatlyio":          "slack://"
    ]
}
