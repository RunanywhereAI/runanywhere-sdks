//
//  MemoryProfiler.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/27/25.
//

import Foundation
import UIKit
import os.log
import Combine

/// Advanced memory profiling tools for LLM frameworks
class MemoryProfiler: ObservableObject {
    static let shared = MemoryProfiler()
    
    // MARK: - Published Properties
    @Published var currentProfile = MemoryProfile()
    @Published var isProfileActive = false
    @Published var memorySnapshots: [MemorySnapshot] = []
    @Published var memoryLeaks: [MemoryLeak] = []
    
    // MARK: - Private Properties
    private let logger = os.Logger(subsystem: "com.runanywhere.ai", category: "MemoryProfiler")
    private var profilingTimer: Timer?
    private let queue = DispatchQueue(label: "com.runanywhere.memoryprofiler", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()
    
    // Memory tracking
    private var allocationTracking: [String: AllocationInfo] = [:]
    private var baselineMemory: Int64 = 0
    private let snapshotInterval: TimeInterval = 0.5
    
    // Memory thresholds
    private let warningThreshold: Double = 0.75 // 75% of available memory
    private let criticalThreshold: Double = 0.90 // 90% of available memory
    
    // MARK: - Initialization
    init() {
        setupMemoryMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Start memory profiling
    func startProfiling() {
        guard !isProfileActive else { return }
        
        isProfileActive = true
        baselineMemory = getCurrentMemoryUsage()
        memorySnapshots.removeAll()
        memoryLeaks.removeAll()
        
        logger.info("Started memory profiling. Baseline: \(ByteCountFormatter.string(fromByteCount: self.baselineMemory, countStyle: .memory))")
        
        // Start periodic snapshots
        profilingTimer = Timer.scheduledTimer(withTimeInterval: snapshotInterval, repeats: true) { [weak self] _ in
            self?.captureSnapshot()
        }
    }
    
    /// Stop memory profiling
    func stopProfiling() -> MemoryProfilingReport {
        isProfileActive = false
        profilingTimer?.invalidate()
        profilingTimer = nil
        
        logger.info("Stopped memory profiling")
        
        return generateReport()
    }
    
    /// Profile memory for specific operation
    func profileOperation<T>(
        name: String,
        operation: () async throws -> T
    ) async throws -> (result: T, profile: OperationMemoryProfile) {
        
        let startMemory = getCurrentMemoryUsage()
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Track allocation
        let allocationId = UUID().uuidString
        beginAllocationTracking(id: allocationId, name: name)
        
        do {
            let result = try await operation()
            
            let endMemory = getCurrentMemoryUsage()
            let endTime = CFAbsoluteTimeGetCurrent()
            
            // End tracking
            endAllocationTracking(id: allocationId)
            
            let profile = OperationMemoryProfile(
                operationName: name,
                memoryUsed: endMemory - startMemory,
                peakMemory: getPeakMemory(since: startTime),
                duration: endTime - startTime,
                allocations: getAllocations(for: allocationId)
            )
            
            logger.info("""
                Memory profile for '\(name)':
                - Memory used: \(ByteCountFormatter.string(fromByteCount: profile.memoryUsed, countStyle: .memory))
                - Peak memory: \(ByteCountFormatter.string(fromByteCount: profile.peakMemory, countStyle: .memory))
                - Duration: \(String(format: "%.2f", profile.duration))s
                """)
            
            return (result, profile)
            
        } catch {
            endAllocationTracking(id: allocationId)
            throw error
        }
    }
    
    /// Track model loading memory
    func trackModelLoading(
        framework: LLMFramework,
        modelSize: Int64
    ) -> ModelMemoryTracking {
        
        let tracking = ModelMemoryTracking(
            framework: framework,
            expectedSize: modelSize,
            startMemory: getCurrentMemoryUsage(),
            startTime: Date()
        )
        
        return tracking
    }
    
    /// Complete model loading tracking
    func completeModelTracking(_ tracking: ModelMemoryTracking) -> ModelMemoryProfile {
        let endMemory = getCurrentMemoryUsage()
        let actualMemoryUsed = endMemory - tracking.startMemory
        let loadTime = Date().timeIntervalSince(tracking.startTime)
        
        let profile = ModelMemoryProfile(
            framework: tracking.framework,
            expectedSize: tracking.expectedSize,
            actualMemoryUsed: actualMemoryUsed,
            memoryOverhead: actualMemoryUsed - tracking.expectedSize,
            loadTime: loadTime,
            compressionRatio: Double(tracking.expectedSize) / Double(actualMemoryUsed)
        )
        
        logger.info("""
            Model memory profile for \(tracking.framework.displayName):
            - Expected size: \(ByteCountFormatter.string(fromByteCount: tracking.expectedSize, countStyle: .memory))
            - Actual memory: \(ByteCountFormatter.string(fromByteCount: actualMemoryUsed, countStyle: .memory))
            - Overhead: \(ByteCountFormatter.string(fromByteCount: profile.memoryOverhead, countStyle: .memory))
            - Compression ratio: \(String(format: "%.2f", profile.compressionRatio))
            """)
        
        return profile
    }
    
    /// Detect memory leaks
    func detectLeaks() -> [MemoryLeak] {
        var detectedLeaks: [MemoryLeak] = []
        
        // Check for growing allocations
        for (id, allocation) in allocationTracking {
            if allocation.isActive && allocation.duration > 60 { // Active for > 60 seconds
                let growthRate = allocation.currentSize > allocation.initialSize ?
                    Double(allocation.currentSize - allocation.initialSize) / allocation.duration : 0
                
                if growthRate > 1_000_000 { // Growing > 1MB/sec
                    detectedLeaks.append(
                        MemoryLeak(
                            id: id,
                            name: allocation.name,
                            initialSize: allocation.initialSize,
                            currentSize: allocation.currentSize,
                            growthRate: growthRate,
                            duration: allocation.duration
                        )
                    )
                }
            }
        }
        
        memoryLeaks = detectedLeaks
        
        if !detectedLeaks.isEmpty {
            logger.warning("Detected \(detectedLeaks.count) potential memory leaks")
        }
        
        return detectedLeaks
    }
    
    /// Get memory recommendations
    func getRecommendations() -> [MemoryRecommendation] {
        var recommendations: [MemoryRecommendation] = []
        
        let currentUsage = getCurrentMemoryUsage()
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let usageRatio = Double(currentUsage) / Double(totalMemory)
        
        // High memory usage
        if usageRatio > warningThreshold {
            recommendations.append(
                MemoryRecommendation(
                    type: .reduceModelSize,
                    priority: .high,
                    title: "High Memory Usage",
                    description: "Consider using smaller or more quantized models",
                    estimatedSavings: Int64(Double(currentUsage) * 0.3)
                )
            )
        }
        
        // Memory fragmentation
        if hasHighFragmentation() {
            recommendations.append(
                MemoryRecommendation(
                    type: .defragment,
                    priority: .medium,
                    title: "Memory Fragmentation",
                    description: "Restart the app to defragment memory",
                    estimatedSavings: Int64(Double(currentUsage) * 0.1)
                )
            )
        }
        
        // Multiple models loaded
        if countLoadedModels() > 1 {
            recommendations.append(
                MemoryRecommendation(
                    type: .unloadUnusedModels,
                    priority: .medium,
                    title: "Multiple Models Loaded",
                    description: "Unload models not currently in use",
                    estimatedSavings: estimateModelMemory()
                )
            )
        }
        
        return recommendations
    }
    
    /// Export memory profile
    func exportProfile(format: MemoryExportFormat) throws -> Data {
        let report = generateReport()
        
        switch format {
        case .json:
            return try JSONEncoder().encode(report)
        case .csv:
            return generateCSV(from: report).data(using: .utf8)!
        case .markdown:
            return generateMarkdown(from: report).data(using: .utf8)!
        }
    }
    
    // MARK: - Private Methods
    
    private func setupMemoryMonitoring() {
        // Monitor app lifecycle
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)
        
        // Monitor thermal state
        ProcessInfo.processInfo.publisher(for: \.thermalState)
            .sink { [weak self] state in
                self?.handleThermalStateChange(state)
            }
            .store(in: &cancellables)
    }
    
    private func captureSnapshot() {
        let snapshot = MemorySnapshot(
            timestamp: Date(),
            usedMemory: getCurrentMemoryUsage(),
            availableMemory: getAvailableMemory(),
            wiredMemory: getWiredMemory(),
            compressedMemory: getCompressedMemory(),
            allocations: allocationTracking.count,
            largestAllocation: getLargestAllocation()
        )
        
        memorySnapshots.append(snapshot)
        
        // Keep only recent snapshots (last 5 minutes)
        let cutoff = Date().addingTimeInterval(-300)
        memorySnapshots = memorySnapshots.filter { $0.timestamp > cutoff }
        
        // Update current profile
        updateCurrentProfile(with: snapshot)
        
        // Check for issues
        checkMemoryHealth(snapshot)
    }
    
    private func getCurrentMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
    
    private func getAvailableMemory() -> Int64 {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let usedMemory = getCurrentMemoryUsage()
        return Int64(totalMemory) - usedMemory
    }
    
    private func getWiredMemory() -> Int64 {
        // Simplified - would need vm_statistics for accurate value
        return getCurrentMemoryUsage() / 4
    }
    
    private func getCompressedMemory() -> Int64 {
        // Simplified - would need vm_statistics for accurate value
        return getCurrentMemoryUsage() / 10
    }
    
    private func getLargestAllocation() -> AllocationInfo? {
        return allocationTracking.values.max { $0.currentSize < $1.currentSize }
    }
    
    private func getPeakMemory(since startTime: CFAbsoluteTime) -> Int64 {
        let relevantSnapshots = memorySnapshots.filter {
            $0.timestamp.timeIntervalSince1970 > startTime
        }
        
        return relevantSnapshots.map { $0.usedMemory }.max() ?? getCurrentMemoryUsage()
    }
    
    private func getAllocations(for id: String) -> [AllocationDetail] {
        // Simplified - would track actual allocations
        return []
    }
    
    private func beginAllocationTracking(id: String, name: String) {
        allocationTracking[id] = AllocationInfo(
            name: name,
            startTime: Date(),
            initialSize: getCurrentMemoryUsage(),
            currentSize: getCurrentMemoryUsage(),
            isActive: true
        )
    }
    
    private func endAllocationTracking(id: String) {
        allocationTracking[id]?.isActive = false
        allocationTracking[id]?.currentSize = getCurrentMemoryUsage()
    }
    
    private func updateCurrentProfile(with snapshot: MemorySnapshot) {
        currentProfile.currentUsage = snapshot.usedMemory
        currentProfile.availableMemory = snapshot.availableMemory
        currentProfile.usagePercentage = Double(snapshot.usedMemory) / Double(ProcessInfo.processInfo.physicalMemory)
        currentProfile.allocations = snapshot.allocations
        
        // Calculate trend
        if memorySnapshots.count > 10 {
            let recentSnapshots = Array(memorySnapshots.suffix(10))
            let averageUsage = recentSnapshots.map { $0.usedMemory }.reduce(0, +) / Int64(recentSnapshots.count)
            currentProfile.trend = snapshot.usedMemory > averageUsage ? .increasing : .decreasing
        }
    }
    
    private func checkMemoryHealth(_ snapshot: MemorySnapshot) {
        let usageRatio = Double(snapshot.usedMemory) / Double(ProcessInfo.processInfo.physicalMemory)
        
        if usageRatio > criticalThreshold {
            logger.critical("Critical memory usage: \(Int(usageRatio * 100))%")
            handleCriticalMemory()
        } else if usageRatio > warningThreshold {
            logger.warning("High memory usage: \(Int(usageRatio * 100))%")
        }
    }
    
    private func handleMemoryWarning() {
        logger.warning("Received system memory warning")
        
        // Capture diagnostic info
        let diagnostic = MemoryDiagnostic(
            timestamp: Date(),
            memoryUsage: getCurrentMemoryUsage(),
            largestAllocations: Array(allocationTracking.values.sorted { $0.currentSize > $1.currentSize }.prefix(5)),
            activeFrameworks: getActiveFrameworks()
        )
        
        // Save diagnostic
        saveDiagnostic(diagnostic)
        
        // Clear caches
        NotificationCenter.default.post(name: .clearModelCaches, object: nil)
    }
    
    private func handleThermalStateChange(_ state: ProcessInfo.ThermalState) {
        if state == .serious || state == .critical {
            logger.warning("Thermal state changed to \(String(describing: state))")
            // Reduce memory pressure
        }
    }
    
    private func handleCriticalMemory() {
        // Emergency memory reduction
        NotificationCenter.default.post(name: .emergencyMemoryReduction, object: nil)
    }
    
    private func hasHighFragmentation() -> Bool {
        // Simplified check - would need detailed allocation info
        return allocationTracking.count > 100
    }
    
    private func countLoadedModels() -> Int {
        // Check active frameworks
        return 1 // Simplified implementation
    }
    
    private func estimateModelMemory() -> Int64 {
        // Estimate based on typical model sizes
        return 1_000_000_000 // 1GB estimate
    }
    
    private func getActiveFrameworks() -> [LLMFramework] {
        // Get currently active frameworks
        return [LLMFramework.mock] // Simplified implementation
    }
    
    private func generateReport() -> MemoryProfilingReport {
        let peakUsage = memorySnapshots.map { $0.usedMemory }.max() ?? 0
        let averageUsage = memorySnapshots.isEmpty ? 0 :
            memorySnapshots.map { $0.usedMemory }.reduce(0, +) / Int64(memorySnapshots.count)
        
        return MemoryProfilingReport(
            startTime: memorySnapshots.first?.timestamp ?? Date(),
            endTime: Date(),
            baselineMemory: baselineMemory,
            peakMemory: peakUsage,
            averageMemory: averageUsage,
            snapshots: memorySnapshots,
            leaks: memoryLeaks,
            recommendations: getRecommendations()
        )
    }
    
    private func generateCSV(from report: MemoryProfilingReport) -> String {
        var csv = "Timestamp,Used Memory,Available Memory,Allocations\n"
        
        for snapshot in report.snapshots {
            csv += "\(snapshot.timestamp.timeIntervalSince1970),"
            csv += "\(snapshot.usedMemory),"
            csv += "\(snapshot.availableMemory),"
            csv += "\(snapshot.allocations)\n"
        }
        
        return csv
    }
    
    private func generateMarkdown(from report: MemoryProfilingReport) -> String {
        var markdown = "# Memory Profiling Report\n\n"
        
        markdown += "## Summary\n\n"
        markdown += "- Duration: \(report.endTime.timeIntervalSince(report.startTime))s\n"
        markdown += "- Baseline: \(ByteCountFormatter.string(fromByteCount: report.baselineMemory, countStyle: .memory))\n"
        markdown += "- Peak: \(ByteCountFormatter.string(fromByteCount: report.peakMemory, countStyle: .memory))\n"
        markdown += "- Average: \(ByteCountFormatter.string(fromByteCount: report.averageMemory, countStyle: .memory))\n"
        
        if !report.leaks.isEmpty {
            markdown += "\n## Potential Leaks\n\n"
            for leak in report.leaks {
                markdown += "- \(leak.name): \(ByteCountFormatter.string(fromByteCount: Int64(leak.growthRate), countStyle: .memory))/sec\n"
            }
        }
        
        if !report.recommendations.isEmpty {
            markdown += "\n## Recommendations\n\n"
            for rec in report.recommendations {
                markdown += "- **\(rec.title)**: \(rec.description)\n"
            }
        }
        
        return markdown
    }
    
    private func saveDiagnostic(_ diagnostic: MemoryDiagnostic) {
        // Save to file or analytics
    }
}

// MARK: - Supporting Types

enum MemoryExportFormat {
    case json
    case csv
    case markdown
}

struct MemoryProfile {
    var currentUsage: Int64 = 0
    var availableMemory: Int64 = 0
    var usagePercentage: Double = 0
    var allocations: Int = 0
    var trend: MemoryTrend = .stable
}

enum MemoryTrend {
    case increasing
    case decreasing
    case stable
}

struct MemorySnapshot: Codable {
    let timestamp: Date
    let usedMemory: Int64
    let availableMemory: Int64
    let wiredMemory: Int64
    let compressedMemory: Int64
    let allocations: Int
    let largestAllocation: AllocationInfo?
}

struct AllocationInfo: Codable {
    let name: String
    let startTime: Date
    let initialSize: Int64
    var currentSize: Int64
    var isActive: Bool
    
    var duration: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
}

struct AllocationDetail: Codable {
    let size: Int64
    let type: String
    let stackTrace: [String]
}

struct OperationMemoryProfile {
    let operationName: String
    let memoryUsed: Int64
    let peakMemory: Int64
    let duration: TimeInterval
    let allocations: [AllocationDetail]
}

struct ModelMemoryTracking {
    let framework: LLMFramework
    let expectedSize: Int64
    let startMemory: Int64
    let startTime: Date
}

struct ModelMemoryProfile {
    let framework: LLMFramework
    let expectedSize: Int64
    let actualMemoryUsed: Int64
    let memoryOverhead: Int64
    let loadTime: TimeInterval
    let compressionRatio: Double
}

struct MemoryLeak: Identifiable, Codable {
    let id: String
    let name: String
    let initialSize: Int64
    let currentSize: Int64
    let growthRate: Double
    let duration: TimeInterval
}

struct MemoryRecommendation: Identifiable, Codable {
    var id = UUID()
    let type: RecommendationType
    let priority: Priority
    let title: String
    let description: String
    let estimatedSavings: Int64
    
    enum RecommendationType: String, Codable {
        case reduceModelSize
        case unloadUnusedModels
        case defragment
        case clearCaches
    }
    
    enum Priority: String, Codable {
        case low
        case medium
        case high
    }
}

struct MemoryProfilingReport: Codable {
    let startTime: Date
    let endTime: Date
    let baselineMemory: Int64
    let peakMemory: Int64
    let averageMemory: Int64
    let snapshots: [MemorySnapshot]
    let leaks: [MemoryLeak]
    let recommendations: [MemoryRecommendation]
}

struct MemoryDiagnostic {
    let timestamp: Date
    let memoryUsage: Int64
    let largestAllocations: [AllocationInfo]
    let activeFrameworks: [LLMFramework]
}

// MARK: - Extensions

extension Notification.Name {
    static let emergencyMemoryReduction = Notification.Name("emergencyMemoryReduction")
}

// Helper to get framework from service
extension LLMService {
    static var framework: LLMFramework {
        switch String(describing: self) {
        case "FoundationModelsService": return .foundationModels
        case "CoreMLService": return .coreML
        case "MLXService": return .mlx
        case "MLCService": return .mlc
        case "ONNXService": return .onnxRuntime
        case "ExecuTorchService": return .execuTorch
        case "LlamaCppService": return .llamaCpp
        case "TFLiteService": return .tensorFlowLite
        case "PicoLLMService": return .picoLLM
        case "SwiftTransformersService": return .swiftTransformers
        default: return .mock
        }
    }
}