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
        static let sessionState        = "sessionState"          // FlowSessionPhase raw value
        static let transcribedText     = "transcribedText"       // Final transcription result
        static let returnToAppScheme   = "returnToAppScheme"     // Host app URL scheme for bounce-back
        static let preferredSTTModelId = "preferredSTTModelId"   // User's chosen STT model
        static let dictationHistory    = "dictationHistory"      // JSON-encoded [DictationEntry]
        static let audioLevel          = "audioLevel"            // Float 0–1, updated ~10×/s during listening
        static let lastInsertedText    = "lastInsertedText"      // String, for undo button after insertion
        static let lastHeartbeat       = "lastHeartbeat"         // Double unix timestamp, written every 1s while session is active
    }

    // Darwin inter-process notification names (CFNotificationCenter)
    // These fire instantly across process boundaries with no polling.
    enum DarwinNotifications {
        // app → keyboard
        static let transcriptionReady = "com.runanywhere.keyboard.transcriptionReady"
        static let sessionReady       = "com.runanywhere.session.ready"
        // keyboard → app
        static let startListening     = "com.runanywhere.keyboard.startListening"
        static let stopListening      = "com.runanywhere.keyboard.stopListening"
        static let cancelListening    = "com.runanywhere.keyboard.cancelListening"
        static let endSession         = "com.runanywhere.session.end"
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
