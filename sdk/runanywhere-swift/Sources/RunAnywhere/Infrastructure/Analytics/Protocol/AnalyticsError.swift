//
//  AnalyticsError.swift
//  RunAnywhere SDK
//
//  Typed error enum for analytics-related errors
//

import Foundation

/// Errors that can occur during analytics operations
public enum AnalyticsError: Error, LocalizedError, Sendable {

    // MARK: - Initialization Errors

    /// Analytics service not initialized
    case notInitialized

    /// Failed to initialize analytics with underlying error
    case initializationFailed(underlying: Error)

    /// Invalid configuration provided
    case invalidConfiguration(reason: String)

    // MARK: - Tracking Errors

    /// Failed to track event
    case trackingFailed(eventType: String, reason: String)

    /// Event queue is full
    case queueFull(maxSize: Int)

    /// Invalid event data
    case invalidEventData(reason: String)

    // MARK: - Storage Errors

    /// Failed to persist analytics data
    case storageFailed(underlying: Error)

    /// Failed to retrieve analytics data
    case retrievalFailed(underlying: Error)

    /// Database error
    case databaseError(reason: String)

    // MARK: - Sync Errors

    /// Failed to sync analytics to remote
    case syncFailed(underlying: Error)

    /// Network unavailable for sync
    case networkUnavailable

    /// Remote server error
    case serverError(statusCode: Int, message: String?)

    // MARK: - Session Errors

    /// Invalid session ID
    case invalidSession(sessionId: String)

    /// Session already ended
    case sessionAlreadyEnded(sessionId: String)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Analytics service not initialized. Call initialize() first."
        case .initializationFailed(let error):
            return "Analytics initialization failed: \(error.localizedDescription)"
        case .invalidConfiguration(let reason):
            return "Invalid analytics configuration: \(reason)"
        case .trackingFailed(let eventType, let reason):
            return "Failed to track event '\(eventType)': \(reason)"
        case .queueFull(let maxSize):
            return "Analytics event queue is full (max: \(maxSize))"
        case .invalidEventData(let reason):
            return "Invalid event data: \(reason)"
        case .storageFailed(let error):
            return "Failed to store analytics data: \(error.localizedDescription)"
        case .retrievalFailed(let error):
            return "Failed to retrieve analytics data: \(error.localizedDescription)"
        case .databaseError(let reason):
            return "Analytics database error: \(reason)"
        case .syncFailed(let error):
            return "Failed to sync analytics: \(error.localizedDescription)"
        case .networkUnavailable:
            return "Network unavailable for analytics sync"
        case .serverError(let statusCode, let message):
            return "Analytics server error (\(statusCode)): \(message ?? "Unknown error")"
        case .invalidSession(let sessionId):
            return "Invalid analytics session: \(sessionId)"
        case .sessionAlreadyEnded(let sessionId):
            return "Analytics session already ended: \(sessionId)"
        }
    }
}
