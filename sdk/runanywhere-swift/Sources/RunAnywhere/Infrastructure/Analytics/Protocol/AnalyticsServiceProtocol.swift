//
//  AnalyticsServiceProtocol.swift
//  RunAnywhere SDK
//
//  Unified analytics protocol system - Simple and consistent across all services
//

import Foundation

// MARK: - Core Analytics Protocol

/// Base protocol for all analytics services in the SDK
public protocol AnalyticsService: Actor {
    associatedtype Event: AnalyticsEvent
    associatedtype Metrics: AnalyticsMetrics

    // Event tracking
    func track(event: Event) async
    func trackBatch(events: [Event]) async

    // Metrics
    func getMetrics() async -> Metrics
    func clearMetrics(olderThan: Date) async

    // Session management
    func startSession(metadata: SessionMetadata) async -> String
    func endSession(sessionId: String) async

    // Health
    func isHealthy() async -> Bool
}

// MARK: - Metrics System

/// Base protocol for analytics metrics
public protocol AnalyticsMetrics: Sendable {
    var totalEvents: Int { get }
    var startTime: Date { get }
    var lastEventTime: Date? { get }
}

// MARK: - Session Management

/// Simple session metadata
public struct SessionMetadata: Sendable {
    public let id: String
    public let modelId: String?
    public let type: String

    public init(
        id: String = UUID().uuidString,
        modelId: String? = nil,
        type: String = "default"
    ) {
        self.id = id
        self.modelId = modelId
        self.type = type
    }
}
