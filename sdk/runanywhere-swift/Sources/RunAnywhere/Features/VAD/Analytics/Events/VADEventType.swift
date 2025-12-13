//
//  VADEventType.swift
//  RunAnywhere SDK
//
//  VAD event type enumeration
//

import Foundation

// MARK: - VAD Event Type

/// VAD event types
public enum VADEventType: String {
    case detectionStarted = "vad_detection_started"
    case detectionCompleted = "vad_detection_completed"
    case speechActivityStarted = "vad_speech_activity_started"
    case speechActivityEnded = "vad_speech_activity_ended"
    case calibrationStarted = "vad_calibration_started"
    case calibrationCompleted = "vad_calibration_completed"
    case calibrationFailed = "vad_calibration_failed"
    case processingCompleted = "vad_processing_completed"
    case error = "vad_error"
}
