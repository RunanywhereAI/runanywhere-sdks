import Foundation
#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Monitors system memory usage and provides real-time statistics
class MemoryMonitor {
    private let logger = SDKLogger(category: "MemoryMonitor")
    private var monitoringTimer: Timer?
    private var thresholdWatcher: ThresholdWatcher?
    private var isMonitoring = false
    private var config = MemoryService.Config()

    // Monitoring callbacks
    private var statisticsCallback: ((MemoryMonitoringStats) -> Void)?
    private var thresholdCallbacks: [MemoryThreshold: () -> Void] = [:]

    init() {
        thresholdWatcher = ThresholdWatcher()
        setupThresholdWatcher()
    }

    deinit {
        stopMonitoring()
    }

    func configure(_ config: MemoryService.Config) {
        self.config = config
        thresholdWatcher?.configure(config)
    }

    // MARK: - Monitoring Control

    func startMonitoring(callback: @escaping (MemoryMonitoringStats) -> Void) {
        guard !isMonitoring else {
            logger.warning("Memory monitoring already active")
            return
        }

        statisticsCallback = callback
        isMonitoring = true

        logger.info("Starting memory monitoring with \(config.monitoringInterval)s interval")

        monitoringTimer = Timer.scheduledTimer(withTimeInterval: config.monitoringInterval, repeats: true) { [weak self] _ in
            self?.performMonitoringCheck()
        }

        thresholdWatcher?.startWatching()

        // Perform initial check
        performMonitoringCheck()
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        thresholdWatcher?.stopWatching()

        logger.info("Stopped memory monitoring")
    }

    func setThresholdCallback(threshold: MemoryThreshold, callback: @escaping () -> Void) {
        thresholdCallbacks[threshold] = callback
        thresholdWatcher?.setThresholdCallback(threshold: threshold, callback: callback)
    }

    // MARK: - Memory Information

    func getTotalMemory() -> Int64 {
        return Int64(ProcessInfo.processInfo.physicalMemory)
    }

    func getAvailableMemory() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if result == KERN_SUCCESS {
            let totalMemory = ProcessInfo.processInfo.physicalMemory
            let usedMemory = info.resident_size
            return Int64(totalMemory) - Int64(usedMemory)
        }

        // Fallback calculation
        return Int64(ProcessInfo.processInfo.physicalMemory / 2)
    }

    func getUsedMemory() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }

    func getMemoryPressureLevel() -> MemoryPressureLevel? {
        let available = getAvailableMemory()

        if available < config.criticalThreshold {
            return .critical
        } else if available < config.memoryThreshold {
            return .warning
        }

        return nil
    }

    func getCurrentStats() -> MemoryMonitoringStats {
        let totalMemory = getTotalMemory()
        let availableMemory = getAvailableMemory()
        let usedMemory = getUsedMemory()
        let pressureLevel = getMemoryPressureLevel()

        return MemoryMonitoringStats(
            totalMemory: totalMemory,
            availableMemory: availableMemory,
            usedMemory: usedMemory,
            pressureLevel: pressureLevel,
            timestamp: Date()
        )
    }

    // MARK: - Memory Trends

    private var memoryHistory: [MemoryMonitoringStats] = []
    private let maxHistoryEntries = 100

    func getMemoryTrend(duration: TimeInterval) -> MemoryUsageTrend? {
        let cutoffTime = Date().addingTimeInterval(-duration)
        let recentHistory = memoryHistory.filter { $0.timestamp >= cutoffTime }

        guard recentHistory.count >= 2 else { return nil }

        let firstEntry = recentHistory.first!
        let lastEntry = recentHistory.last!

        let memoryDelta = lastEntry.availableMemory - firstEntry.availableMemory
        let timeDelta = lastEntry.timestamp.timeIntervalSince(firstEntry.timestamp)

        guard timeDelta > 0 else { return nil }

        let rate = Double(memoryDelta) / timeDelta // bytes per second

        return MemoryUsageTrend(
            direction: memoryDelta > 0 ? .increasing : .decreasing,
            rate: abs(rate),
            confidence: calculateTrendConfidence(entries: recentHistory)
        )
    }

    func getAverageMemoryUsage(duration: TimeInterval) -> Double? {
        let cutoffTime = Date().addingTimeInterval(-duration)
        let recentHistory = memoryHistory.filter { $0.timestamp >= cutoffTime }

        guard !recentHistory.isEmpty else { return nil }

        let totalUsage = recentHistory.map { Double($0.usedMemory) }.reduce(0, +)
        return totalUsage / Double(recentHistory.count)
    }

    // MARK: - Private Implementation

    private func performMonitoringCheck() {
        let stats = getCurrentStats()

        // Store in history
        memoryHistory.append(stats)
        if memoryHistory.count > maxHistoryEntries {
            memoryHistory.removeFirst()
        }

        // Log memory status
        logMemoryStatus(stats)

        // Notify callback
        statisticsCallback?(stats)

        // Check thresholds
        thresholdWatcher?.checkThresholds(stats: stats)
    }

    private func setupThresholdWatcher() {
        thresholdWatcher?.setMemoryMonitor(self)
    }

    private func logMemoryStatus(_ stats: MemoryMonitoringStats) {
        let availableString = ByteCountFormatter.string(fromByteCount: stats.availableMemory, countStyle: .memory)
        let usedString = ByteCountFormatter.string(fromByteCount: stats.usedMemory, countStyle: .memory)
        let usagePercent = String(format: "%.1f", stats.usedMemoryPercentage)

        let pressureInfo = stats.pressureLevel != nil ? " [PRESSURE: \(stats.pressureLevel!)]" : ""

        logger.debug("Memory: \(usedString) used, \(availableString) available (\(usagePercent)%)\(pressureInfo)")

        if let pressureLevel = stats.pressureLevel {
            logger.warning("Memory pressure detected: \(pressureLevel)")
        }
    }

    private func calculateTrendConfidence(entries: [MemoryMonitoringStats]) -> Double {
        guard entries.count >= 3 else { return 0.5 }

        // Calculate consistency of trend direction
        var consistent = 0
        var total = 0

        for i in 1..<entries.count {
            let delta = entries[i].availableMemory - entries[i-1].availableMemory
            let previousDelta = i > 1 ? entries[i-1].availableMemory - entries[i-2].availableMemory : delta

            if (delta > 0 && previousDelta > 0) || (delta < 0 && previousDelta < 0) {
                consistent += 1
            }
            total += 1
        }

        return total > 0 ? Double(consistent) / Double(total) : 0.5
    }
}

/// Memory monitoring statistics
struct MemoryMonitoringStats {
    let totalMemory: Int64
    let availableMemory: Int64
    let usedMemory: Int64
    let pressureLevel: MemoryPressureLevel?
    let timestamp: Date

    var usedMemoryPercentage: Double {
        return Double(usedMemory) / Double(totalMemory) * 100
    }

    var availableMemoryPercentage: Double {
        return Double(availableMemory) / Double(totalMemory) * 100
    }
}

/// Memory usage trend information
struct MemoryUsageTrend {
    let direction: TrendDirection
    let rate: Double // bytes per second
    let confidence: Double // 0.0 to 1.0

    enum TrendDirection {
        case increasing
        case decreasing
        case stable
    }

    var rateString: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return "\(formatter.string(fromByteCount: Int64(rate), countStyle: .memory))/s"
    }
}

/// Memory threshold definitions
enum MemoryThreshold: CaseIterable {
    case warning
    case critical
    case low
    case veryLow

    func threshold(for config: MemoryService.Config) -> Int64 {
        switch self {
        case .warning:
            return config.memoryThreshold
        case .critical:
            return config.criticalThreshold
        case .low:
            return config.memoryThreshold / 2
        case .veryLow:
            return config.criticalThreshold / 2
        }
    }
}
