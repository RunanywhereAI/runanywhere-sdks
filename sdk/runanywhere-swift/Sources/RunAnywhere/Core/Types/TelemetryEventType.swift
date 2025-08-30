//
//  TelemetryEventType.swift
//  RunAnywhere SDK
//
//  Telemetry event types
//

import Foundation

/// Standard telemetry event types
public enum TelemetryEventType: String, Codable {
    case modelLoaded = "model_loaded"
    case generationStarted = "generation_started"
    case generationCompleted = "generation_completed"
    case error = "error"
    case performance = "performance"
    case memory = "memory"
    case custom = "custom"
}
