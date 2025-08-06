//
//  PulseConfiguration.swift
//  RunAnywhere SDK
//
//  Minimal Pulse framework configuration
//

import Foundation
import Pulse

/// Minimal Pulse framework configuration
internal final class PulseConfiguration {

    /// Configure Pulse with minimal settings
    static func configure(with config: Configuration) {
        // Basic LoggerStore configuration - 50MB storage, 7 days retention
        LoggerStore.shared.configuration = LoggerStore.Configuration(
            sizeLimit: 50_000_000, // 50MB
            maximumSessionAge: TimeInterval(7 * 24 * 60 * 60), // 7 days
            sweepInterval: TimeInterval(60 * 60) // 1 hour
        )

        // Enable network logging for model downloads
        NetworkLogger.Configuration.shared = NetworkLogger.Configuration(
            isEnabled: true,
            isFiltered: true,
            allowedHosts: Set([
                "huggingface.co",
                "*.huggingface.co",
                "github.com",
                "*.github.com",
                "githubusercontent.com",
                "*.githubusercontent.com"
            ]),
            blockedHosts: Set(), // No blocks for now
            sensitiveDataRedaction: .automatic
        )
    }
}
