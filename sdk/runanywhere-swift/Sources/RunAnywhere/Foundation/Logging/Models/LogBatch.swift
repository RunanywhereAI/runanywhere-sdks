//
//  LogBatch.swift
//  RunAnywhere SDK
//
//  Log batch for remote submission
//

import Foundation

/// Log batch for remote submission
internal struct LogBatch: Encodable {
    let logs: [LogEntry]
    let sessionId: String
    let sdkVersion: String
}
