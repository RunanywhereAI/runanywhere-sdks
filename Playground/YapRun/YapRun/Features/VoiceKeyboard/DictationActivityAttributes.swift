//
//  DictationActivityAttributes.swift
//  YapRun + YapRunActivity
//
//  Shared between the main app and the Widget/LiveActivity extension.
//  Defines the data contract for the Dynamic Island recording indicator.
//
//  TARGET MEMBERSHIP: YapRun (main app) + YapRunActivity (widget extension)
//

#if os(iOS)
import ActivityKit
import Foundation

struct DictationActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        var phase: String
        var elapsedSeconds: Int
        var transcript: String
        var wordCount: Int
    }

    var sessionId: String
}
#endif
