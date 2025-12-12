//
//  AnalyticsService.swift
//  RunAnywhere SDK
//
//  Core analytics service protocol defining the interface for analytics capabilities
//

import Foundation

// MARK: - Core Analytics Protocol

/// Base protocol for all analytics services in the SDK
/// Provides a unified interface for event tracking, metrics collection, and session management
public protocol AnalyticsService: Actor {
    associatedtype Event: AnalyticsEvent
    associatedtype Metrics: AnalyticsMetrics

    // MARK: - Event Tracking

    /// Track a single analytics event
    func track(event: Event) async

    /// Track a batch of analytics events for efficiency
    func trackBatch(events: [Event]) async

    // MARK: - Metrics

    /// Get current analytics metrics
    func getMetrics() async -> Metrics

    /// Clear metrics older than specified date
    func clearMetrics(olderThan: Date) async

    // MARK: - Session Management

    /// Start a new analytics session
    /// - Parameter metadata: Session metadata including ID, model ID, and type
    /// - Returns: The session ID
    func startSession(metadata: SessionMetadata) async -> String

    /// End an analytics session
    /// - Parameter sessionId: The session ID to end
    func endSession(sessionId: String) async

    // MARK: - Health

    /// Check if the analytics service is healthy
    func isHealthy() async -> Bool
}
