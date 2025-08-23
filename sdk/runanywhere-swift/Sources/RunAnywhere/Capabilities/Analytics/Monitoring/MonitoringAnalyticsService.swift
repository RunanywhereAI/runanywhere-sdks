//
//  MonitoringAnalyticsService.swift
//  RunAnywhere SDK
//
//  Monitoring and performance analytics service following unified pattern
//

import Foundation

// MARK: - Monitoring Event

/// Monitoring-specific analytics event
public struct MonitoringEvent: AnalyticsEvent {
    public let id: String
    public let type: String
    public let timestamp: Date
    public let sessionId: String?
    public let eventData: any AnalyticsEventData

    public init(
        type: MonitoringEventType,
        sessionId: String? = nil,
        eventData: any AnalyticsEventData
    ) {
        self.id = UUID().uuidString
        self.type = type.rawValue
        self.timestamp = Date()
        self.sessionId = sessionId
        self.eventData = eventData
    }
}

/// Monitoring event types
public enum MonitoringEventType: String {
    case performanceMetric = "monitoring_performance_metric"
    case memoryWarning = "monitoring_memory_warning"
    case memoryPressure = "monitoring_memory_pressure"
    case cpuThreshold = "monitoring_cpu_threshold"
    case diskSpaceWarning = "monitoring_disk_space_warning"
    case networkLatency = "monitoring_network_latency"
    case error = "monitoring_error"
}

// MARK: - Monitoring Metrics

/// Monitoring-specific metrics
public struct MonitoringMetrics: AnalyticsMetrics {
    public let totalEvents: Int
    public let startTime: Date
    public let lastEventTime: Date?
    public let averageCPUUsage: Double
    public let averageMemoryUsage: Double
    public let peakMemoryUsage: Double
    public let warningCount: Int

    public init() {
        self.totalEvents = 0
        self.startTime = Date()
        self.lastEventTime = nil
        self.averageCPUUsage = 0
        self.averageMemoryUsage = 0
        self.peakMemoryUsage = 0
        self.warningCount = 0
    }

    internal init(
        totalEvents: Int,
        startTime: Date,
        lastEventTime: Date?,
        averageCPUUsage: Double,
        averageMemoryUsage: Double,
        peakMemoryUsage: Double,
        warningCount: Int
    ) {
        self.totalEvents = totalEvents
        self.startTime = startTime
        self.lastEventTime = lastEventTime
        self.averageCPUUsage = averageCPUUsage
        self.averageMemoryUsage = averageMemoryUsage
        self.peakMemoryUsage = peakMemoryUsage
        self.warningCount = warningCount
    }
}

// MARK: - Monitoring Analytics Service

/// Monitoring analytics service using unified pattern
public actor MonitoringAnalyticsService: AnalyticsService {

    // MARK: - Type Aliases
    public typealias Event = MonitoringEvent
    public typealias Metrics = MonitoringMetrics

    // MARK: - Properties

    private let queueManager: AnalyticsQueueManager
    private let logger: SDKLogger
    private var currentSession: SessionInfo?
    private var events: [MonitoringEvent] = []

    private struct SessionInfo {
        let id: String
        let modelId: String?
        let startTime: Date
    }

    private var metrics = MonitoringMetrics()
    private var cpuSamples: [Double] = []
    private var memorySamples: [Double] = []
    private var peakMemory: Double = 0
    private var warningCount = 0

    // MARK: - Initialization

    public init(queueManager: AnalyticsQueueManager = .shared) {
        self.queueManager = queueManager
        self.logger = SDKLogger(category: "MonitoringAnalytics")
    }

    // MARK: - Analytics Service Protocol

    public func track(event: MonitoringEvent) async {
        events.append(event)
        await queueManager.enqueue(event)
        await processEvent(event)
    }

    public func trackBatch(events: [MonitoringEvent]) async {
        self.events.append(contentsOf: events)
        await queueManager.enqueueBatch(events)
        for event in events {
            await processEvent(event)
        }
    }

    public func getMetrics() async -> MonitoringMetrics {
        return MonitoringMetrics(
            totalEvents: events.count,
            startTime: metrics.startTime,
            lastEventTime: events.last?.timestamp,
            averageCPUUsage: cpuSamples.isEmpty ? 0 : cpuSamples.reduce(0, +) / Double(cpuSamples.count),
            averageMemoryUsage: memorySamples.isEmpty ? 0 : memorySamples.reduce(0, +) / Double(memorySamples.count),
            peakMemoryUsage: peakMemory,
            warningCount: warningCount
        )
    }

    public func clearMetrics(olderThan date: Date) async {
        events.removeAll { event in
            event.timestamp < date
        }
    }

    public func startSession(metadata: SessionMetadata) async -> String {
        let sessionInfo = SessionInfo(
            id: metadata.id,
            modelId: metadata.modelId,
            startTime: Date()
        )
        currentSession = sessionInfo
        return metadata.id
    }

    public func endSession(sessionId: String) async {
        if currentSession?.id == sessionId {
            currentSession = nil
        }
    }

    public func isHealthy() async -> Bool {
        return true
    }

    // MARK: - Monitoring-Specific Methods

    /// Track performance metrics
    public func trackPerformance(
        cpuUsage: Double,
        memoryUsage: Double,
        diskUsage: Double? = nil
    ) async {
        cpuSamples.append(cpuUsage)
        memorySamples.append(memoryUsage)

        if memoryUsage > peakMemory {
            peakMemory = memoryUsage
        }

        // Keep only last 1000 samples
        if cpuSamples.count > 1000 {
            cpuSamples.removeFirst()
        }
        if memorySamples.count > 1000 {
            memorySamples.removeFirst()
        }

        let eventData = PerformanceMetricsData(
            operationName: "system_monitoring",
            durationMs: 0, // Not applicable for periodic monitoring
            success: true,
            errorCode: nil
        )

        let event = MonitoringEvent(
            type: .performanceMetric,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    /// Track memory warning
    public func trackMemoryWarning(level: String, availableMemory: Int) async {
        warningCount += 1

        let eventData = MemoryWarningData(
            warningLevel: level,
            availableMemoryMB: availableMemory
        )
        let event = MonitoringEvent(
            type: .memoryWarning,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    /// Track memory pressure
    public func trackMemoryPressure(pressure: String, recommendation: String) async {
        warningCount += 1

        let eventData = PerformanceMetricsData(
            operationName: "memory_pressure",
            durationMs: 0,
            success: false,
            errorCode: pressure
        )
        let event = MonitoringEvent(
            type: .memoryPressure,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    /// Track CPU threshold exceeded
    public func trackCPUThreshold(usage: Double, threshold: Double) async {
        warningCount += 1

        let eventData = CPUThresholdData(
            cpuUsage: usage,
            threshold: threshold
        )
        let event = MonitoringEvent(
            type: .cpuThreshold,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    /// Track disk space warning
    public func trackDiskSpaceWarning(availableSpace: Int, requiredSpace: Int) async {
        warningCount += 1

        let eventData = DiskSpaceWarningData(
            availableSpaceMB: availableSpace,
            requiredSpaceMB: requiredSpace
        )
        let event = MonitoringEvent(
            type: .diskSpaceWarning,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    /// Track network latency
    public func trackNetworkLatency(endpoint: String, latency: TimeInterval) async {
        let eventData = NetworkLatencyData(
            endpoint: endpoint,
            latencyMs: latency * 1000
        )
        let event = MonitoringEvent(
            type: .networkLatency,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    /// Track error
    public func trackError(error: Error, context: AnalyticsContext) async {
        let eventData = ErrorEventData(
            error: error.localizedDescription,
            context: context
        )
        let event = MonitoringEvent(
            type: .error,
            sessionId: currentSession?.id,
            eventData: eventData
        )

        await track(event: event)
    }

    // MARK: - Private Methods

    private func processEvent(_ event: MonitoringEvent) async {
        // Custom processing for monitoring events if needed
    }
}
