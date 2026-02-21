//
//  SharedConstants.swift
//  YapRun + YapRunKeyboard
//
//  Shared between the main app and keyboard extension targets.
//  Contains all identifiers used for App Group IPC.
//

import Foundation

enum SharedConstants {
    // App Group identifier — must match both targets' entitlements exactly
    static let appGroupID = "group.com.runanywhere.yaprun"

    // URL scheme for keyboard → main app deep link (Flow Session trigger)
    static let urlScheme = "yaprun"
    static let startFlowURLString = "yaprun://startFlow"

    // App Group UserDefaults keys
    enum Keys {
        static let sessionState        = "sessionState"
        static let transcribedText     = "transcribedText"
        static let returnToAppScheme   = "returnToAppScheme"
        static let preferredSTTModelId = "preferredSTTModelId"
        static let dictationHistory    = "dictationHistory"
        static let audioLevel          = "audioLevel"
        static let lastInsertedText    = "lastInsertedText"
        static let lastHeartbeat           = "lastHeartbeat"
        static let hasCompletedOnboarding  = "hasCompletedOnboarding"
    }

    // Darwin inter-process notification names (CFNotificationCenter)
    enum DarwinNotifications {
        // app → keyboard
        static let transcriptionReady = "com.runanywhere.yaprun.keyboard.transcriptionReady"
        static let sessionReady       = "com.runanywhere.yaprun.session.ready"
        // keyboard → app
        static let startListening     = "com.runanywhere.yaprun.keyboard.startListening"
        static let stopListening      = "com.runanywhere.yaprun.keyboard.stopListening"
        static let cancelListening    = "com.runanywhere.yaprun.keyboard.cancelListening"
        static let endSession         = "com.runanywhere.yaprun.session.end"
    }

    // Curated map of host app bundle IDs → URL schemes for bounce-back
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
        "com.hammerandchisel.discord":      "discord://",
        "com.tinyspeck.chatlyio":          "slack://"
    ]
}
