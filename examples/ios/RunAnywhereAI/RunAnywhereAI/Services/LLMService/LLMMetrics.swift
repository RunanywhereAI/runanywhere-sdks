//
//  LLMMetrics.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import Foundation

/// Performance metrics for LLM operations
struct PerformanceMetrics {
    let averageTokensPerSecond: Double
    let peakTokensPerSecond: Double
    let averageLatency: TimeInterval
    let p95Latency: TimeInterval
    let p99Latency: TimeInterval
    let totalTokensGenerated: Int
    let totalGenerations: Int
    let failureRate: Double
    let averageContextLength: Int
    let hardwareUtilization: HardwareUtilization
}

/// Hardware utilization metrics
struct HardwareUtilization {
    let cpuUsage: Double
    let gpuUsage: Double?
    let neuralEngineUsage: Double?
    let powerUsage: Double
    let thermalState: ThermalState
}

/// Thermal state of the device
enum ThermalState: String {
    case nominal = "nominal"
    case fair = "fair"
    case serious = "serious"
    case critical = "critical"
}

/// Memory usage statistics
struct MemoryStats {
    let modelMemory: Int64
    let contextMemory: Int64
    let peakMemory: Int64
    let availableMemory: Int64
    let memoryPressure: MemoryPressure
    let cacheSize: Int64
    
    var totalMemory: Int64 {
        modelMemory + contextMemory
    }
    
    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalMemory, countStyle: .memory)
    }
}

/// Memory pressure level
enum MemoryPressure: String {
    case normal = "normal"
    case warning = "warning"
    case urgent = "urgent"
    case critical = "critical"
}

/// Benchmark results for model performance
struct BenchmarkResults {
    let framework: String
    let model: String
    let device: String
    let timestamp: Date
    let promptProcessingSpeed: Double
    let generationSpeed: Double
    let firstTokenLatency: TimeInterval
    let memoryFootprint: Int64
    let energyEfficiency: Double
    let qualityScore: Double?
    let configurations: [String: Any]
}

/// Protocol for metrics collection
protocol LLMMetrics {
    /// Get current performance metrics
    func getPerformanceMetrics() -> PerformanceMetrics
    
    /// Get current memory usage
    func getMemoryUsage() -> MemoryStats
    
    /// Get benchmark results
    func getBenchmarkResults() -> BenchmarkResults
    
    /// Reset metrics collection
    func resetMetrics()
    
    /// Export metrics data
    func exportMetrics() -> Data?
    
    /// Subscribe to metrics updates
    func subscribeToMetrics(_ handler: @escaping (MetricsUpdate) -> Void) -> UUID
    
    /// Unsubscribe from metrics updates
    func unsubscribeFromMetrics(_ id: UUID)
}

/// Metrics update event
struct MetricsUpdate {
    let type: MetricsType
    let timestamp: Date
    let data: Any
}

/// Type of metrics update
enum MetricsType {
    case performance
    case memory
    case hardware
    case benchmark
}