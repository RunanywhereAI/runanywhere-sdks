//
//  DictationActivityAttributes.swift
//  RunAnywhereAI + RunAnywhereActivityExtension
//
//  Shared between the main app target and the Widget/LiveActivity extension target.
//  Defines the data contract for the Dynamic Island recording indicator.
//
//  TARGET MEMBERSHIP: RunAnywhereAI (main app) + RunAnywhereActivityExtension (widget extension)
//  The extension gets this file via the manual pbxproj wiring (same pattern as SharedConstants.swift).
//

import ActivityKit
import Foundation

/// The static attributes for a dictation flow session.
/// These do not change after the activity is started.
struct DictationActivityAttributes: ActivityAttributes {

    /// The dynamic / live state updated throughout the session.
    struct ContentState: Codable, Hashable {
        /// Current phase: "ready" | "listening" | "transcribing" | "done"
        var phase: String
        /// Seconds elapsed since session started
        var elapsedSeconds: Int
        /// Latest partial transcription (empty while recording/listening)
        var transcript: String
        /// Running total of words dictated in this session
        var wordCount: Int
    }

    /// Session identifier — set once at start
    var sessionId: String
}
