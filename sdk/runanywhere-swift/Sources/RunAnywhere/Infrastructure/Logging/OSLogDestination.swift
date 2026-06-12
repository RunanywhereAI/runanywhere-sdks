//
//  OSLogDestination.swift
//  RunAnywhere SDK
//
//  Routes SDK logs into Apple's unified logging so simulator/device log capture
//  (subsystem com.runanywhere) can grep E2E catalog markers.
//

import Foundation
import os

/// Writes log entries to `os.Logger` under the shared RunAnywhere subsystem.
final class OSLogDestination: LogDestination, @unchecked Sendable {

    static let destinationID = "com.runanywhere.logging.oslog"

    let identifier: String = OSLogDestination.destinationID

    var isAvailable: Bool { true }

    private let loggers = OSAllocatedUnfairLock<[String: Logger]>(initialState: [:])

    func write(_ entry: RALogEntry) {
        let logger = loggers.withLock { cache -> Logger in
            if let existing = cache[entry.category] {
                return existing
            }
            // swiftlint:disable:next no_apple_logger
            let created = Logger(subsystem: "com.runanywhere", category: entry.category)
            cache[entry.category] = created
            return created
        }

        switch entry.level {
        case .trace:
            logger.trace("\(entry.message, privacy: .public)")
        case .debug:
            logger.debug("\(entry.message, privacy: .public)")
        case .info:
            logger.info("\(entry.message, privacy: .public)")
        case .warning:
            logger.warning("\(entry.message, privacy: .public)")
        case .error:
            logger.error("\(entry.message, privacy: .public)")
        case .fatal:
            logger.fault("\(entry.message, privacy: .public)")
        case .UNRECOGNIZED:
            logger.log("\(entry.message, privacy: .public)")
        }
    }

    func flush() {}
}
