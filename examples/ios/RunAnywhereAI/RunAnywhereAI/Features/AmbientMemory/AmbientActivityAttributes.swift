//
//  AmbientActivityAttributes.swift
//  RunAnywhereAI + RunAnywhereActivityExtension
//
//  Data contract for the Ambient Memory Lab's Live Activity.
//
//  Deliberately carries no transcript, summary, speaker name, or memory text.
//  The Lock Screen and Dynamic Island are visible to anyone holding the phone,
//  so the ambient surface shows only that recording is happening, for how
//  long, and how much it has captured.
//
//  TARGET MEMBERSHIP: RunAnywhereAI (main app) + RunAnywhereActivityExtension
//  (widget extension), wired manually in the pbxproj like
//  DictationActivityAttributes.swift.
//

#if os(iOS)
import ActivityKit
#endif
import Foundation

#if os(iOS)
@available(iOS 16.1, *)
struct AmbientActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "preparing" | "listening" | "speech" | "processing" | "paused"
        var phase: String
        var elapsedSeconds: Int
        /// Number of speech segments captured so far.
        var segmentCount: Int
        /// Number of action items found so far.
        var actionItemCount: Int
        /// Set when the session stopped itself (thermal, storage, interruption)
        /// so the user is not left believing it is still recording.
        var isStopped: Bool
    }

    /// Session identifier — set once at start.
    var sessionId: String
}
#endif
