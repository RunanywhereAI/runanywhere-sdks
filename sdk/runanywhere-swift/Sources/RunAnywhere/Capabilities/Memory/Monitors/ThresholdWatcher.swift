import Foundation

/// Watches memory thresholds and triggers callbacks when crossed
class ThresholdWatcher {
    private let logger: SDKLogger = SDKLogger(category: "ThresholdWatcher")
    private var memoryThreshold: Int64 = 500_000_000 // 500MB
    private var criticalThreshold: Int64 = 200_000_000 // 200MB
    private weak var memoryMonitor: MemoryMonitor?

    // Threshold state tracking
    private var thresholdStates: [MemoryThreshold: Bool] = [:]
    private var thresholdCallbacks: [MemoryThreshold: () -> Void] = [:]
    private var lastThresholdCheck: Date = Date()
    private var isWatching: Bool = false

    // Hysteresis to prevent threshold flapping
    private let thresholdHysteresis: Double = 0.1 // 10% buffer

    init() {
        // Initialize all thresholds as not crossed
        for threshold in MemoryThreshold.allCases {
            thresholdStates[threshold] = false
        }
    }

    func configure(memoryThreshold: Int64, criticalThreshold: Int64) {
        self.memoryThreshold = memoryThreshold
        self.criticalThreshold = criticalThreshold
    }

    func setMemoryMonitor(_ monitor: MemoryMonitor) {
        self.memoryMonitor = monitor
    }

    // MARK: - Threshold Watching

    func startWatching() {
        guard !isWatching else {
            logger.warning("Threshold watching already active")
            return
        }

        isWatching = true
        logger.info("Started threshold watching")

        // Reset threshold states
        for threshold in MemoryThreshold.allCases {
            thresholdStates[threshold] = false
        }
    }

    func stopWatching() {
        guard isWatching else { return }

        isWatching = false
        logger.info("Stopped threshold watching")
    }

    func setThresholdCallback(threshold: MemoryThreshold, callback: @escaping () -> Void) {
        thresholdCallbacks[threshold] = callback
        logger.debug("Set callback for threshold: \(threshold)")
    }

    func removeThresholdCallback(threshold: MemoryThreshold) {
        thresholdCallbacks.removeValue(forKey: threshold)
        logger.debug("Removed callback for threshold: \(threshold)")
    }

    // MARK: - Threshold Checking

    func checkThresholds(stats: MemoryMonitoringStats) {
        guard isWatching else { return }

        let checkTime = Date()
        defer { lastThresholdCheck = checkTime }

        for threshold in MemoryThreshold.allCases {
            checkThreshold(threshold, stats: stats, checkTime: checkTime)
        }
    }

    func checkThreshold(_ threshold: MemoryThreshold, stats: MemoryMonitoringStats, checkTime: Date) {
        let thresholdValue = threshold.threshold(memoryThreshold: memoryThreshold, criticalThreshold: criticalThreshold)
        let currentState = thresholdStates[threshold] ?? false
        let hysteresisBuffer = Int64(Double(thresholdValue) * thresholdHysteresis)

        let isAboveThreshold: Bool
        if currentState {
            // If already crossed, use hysteresis buffer to prevent flapping
            isAboveThreshold = stats.availableMemory < (thresholdValue + hysteresisBuffer)
        } else {
            // If not crossed, check against raw threshold
            isAboveThreshold = stats.availableMemory < thresholdValue
        }

        // Check for threshold crossing
        if isAboveThreshold && !currentState {
            // Threshold crossed (available memory dropped below threshold)
            thresholdStates[threshold] = true
            handleThresholdCrossed(threshold, stats: stats, checkTime: checkTime)
        } else if !isAboveThreshold && currentState {
            // Threshold uncrossed (available memory rose above threshold + hysteresis)
            thresholdStates[threshold] = false
            handleThresholdUncrossed(threshold, stats: stats, checkTime: checkTime)
        }
    }

    // MARK: - Threshold Events

    private func handleThresholdCrossed(_ threshold: MemoryThreshold, stats: MemoryMonitoringStats, checkTime: Date) {
        let thresholdValue = threshold.threshold(memoryThreshold: memoryThreshold, criticalThreshold: criticalThreshold)
        let availableString = ByteCountFormatter.string(fromByteCount: stats.availableMemory, countStyle: .memory)
        let thresholdString = ByteCountFormatter.string(fromByteCount: thresholdValue, countStyle: .memory)

        logger.warning("Memory threshold crossed: \(threshold) (available: \(availableString), threshold: \(thresholdString))")

        // Record threshold event
        recordThresholdEvent(
            threshold: threshold,
            crossed: true,
            stats: stats,
            timestamp: checkTime
        )

        // Trigger callback
        thresholdCallbacks[threshold]?()

        // Post notification
        postThresholdNotification(threshold: threshold, crossed: true, stats: stats)
    }

    private func handleThresholdUncrossed(_ threshold: MemoryThreshold, stats: MemoryMonitoringStats, checkTime: Date) {
        let thresholdValue = threshold.threshold(memoryThreshold: memoryThreshold, criticalThreshold: criticalThreshold)
        let availableString = ByteCountFormatter.string(fromByteCount: stats.availableMemory, countStyle: .memory)
        let thresholdString = ByteCountFormatter.string(fromByteCount: thresholdValue, countStyle: .memory)

        logger.info("Memory threshold uncrossed: \(threshold) (available: \(availableString), threshold: \(thresholdString))")

        // Record threshold event
        recordThresholdEvent(
            threshold: threshold,
            crossed: false,
            stats: stats,
            timestamp: checkTime
        )

        // Post notification
        postThresholdNotification(threshold: threshold, crossed: false, stats: stats)
    }

    // MARK: - Threshold State

    func isThresholdCrossed(_ threshold: MemoryThreshold) -> Bool {
        return thresholdStates[threshold] ?? false
    }

    func getCrossedThresholds() -> [MemoryThreshold] {
        return thresholdStates.compactMap { threshold, crossed in
            crossed ? threshold : nil
        }
    }

    func getThresholdMargin(_ threshold: MemoryThreshold) -> Int64? {
        guard let monitor = memoryMonitor else { return nil }

        let thresholdValue = threshold.threshold(memoryThreshold: memoryThreshold, criticalThreshold: criticalThreshold)
        let availableMemory = monitor.getAvailableMemory()

        return availableMemory - thresholdValue
    }

    // MARK: - Threshold History

    private var thresholdEvents: [ThresholdEvent] = []
    private let maxHistoryEntries: Int = 100

    private func recordThresholdEvent(threshold: MemoryThreshold, crossed: Bool, stats: MemoryMonitoringStats, timestamp: Date) {
        let event = ThresholdEvent(
            threshold: threshold,
            crossed: crossed,
            availableMemory: stats.availableMemory,
            timestamp: timestamp
        )

        thresholdEvents.append(event)

        // Limit history size
        if thresholdEvents.count > maxHistoryEntries {
            thresholdEvents.removeFirst()
        }
    }

    func getThresholdHistory(threshold: MemoryThreshold? = nil, since: Date? = nil) -> [ThresholdEvent] {
        var filtered = thresholdEvents

        if let threshold = threshold {
            filtered = filtered.filter { $0.threshold == threshold }
        }

        if let since = since {
            filtered = filtered.filter { $0.timestamp >= since }
        }

        return filtered
    }

    func getLastThresholdCrossing(_ threshold: MemoryThreshold) -> ThresholdEvent? {
        return thresholdEvents
            .filter { $0.threshold == threshold && $0.crossed }
            .last
    }

    // MARK: - Statistics

    func getThresholdStatistics() -> ThresholdStatistics {
        let now = Date()
        let last24Hours = now.addingTimeInterval(-24 * 3600)
        let recentEvents = thresholdEvents.filter { $0.timestamp >= last24Hours }

        let crossingsByThreshold = Dictionary(grouping: recentEvents.filter { $0.crossed }) { $0.threshold }
        let crossingCounts = crossingsByThreshold.mapValues { $0.count }

        let currentlyCrossed = getCrossedThresholds()

        return ThresholdStatistics(
            currentlyCrossedThresholds: currentlyCrossed,
            crossingsLast24Hours: crossingCounts,
            totalEventsRecorded: thresholdEvents.count,
            lastCheckTime: lastThresholdCheck
        )
    }

    // MARK: - Notifications

    private func postThresholdNotification(threshold: MemoryThreshold, crossed: Bool, stats: MemoryMonitoringStats) {
        let thresholdInfo = ThresholdNotificationInfo(
            threshold: threshold,
            crossed: crossed,
            availableMemory: stats.availableMemory,
            timestamp: Date()
        )

        let userInfo: [String: Any] = [
            "thresholdInfo": thresholdInfo
        ]

        let notificationName: Notification.Name = crossed ? .memoryThresholdCrossed : .memoryThresholdUncrossed

        NotificationCenter.default.post(
            name: notificationName,
            object: self,
            userInfo: userInfo
        )
    }
}

// MARK: - Threshold Event

/// Information for threshold crossing notifications
struct ThresholdNotificationInfo: Sendable {
    let threshold: MemoryThreshold
    let crossed: Bool
    let availableMemory: Int64
    let timestamp: Date

    var availableMemoryString: String {
        ByteCountFormatter.string(fromByteCount: availableMemory, countStyle: .memory)
    }
}

/// Record of a threshold crossing event
struct ThresholdEvent: Sendable {
    let threshold: MemoryThreshold
    let crossed: Bool // true = crossed, false = uncrossed
    let availableMemory: Int64
    let timestamp: Date

    var availableMemoryString: String {
        ByteCountFormatter.string(fromByteCount: availableMemory, countStyle: .memory)
    }
}

/// Statistics about threshold behavior
struct ThresholdStatistics: Sendable {
    let currentlyCrossedThresholds: [MemoryThreshold]
    let crossingsLast24Hours: [MemoryThreshold: Int]
    let totalEventsRecorded: Int
    let lastCheckTime: Date

    var hasActiveCrossings: Bool {
        !currentlyCrossedThresholds.isEmpty
    }

    var mostFrequentThreshold: MemoryThreshold? {
        crossingsLast24Hours.max { $0.value < $1.value }?.key
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let memoryThresholdCrossed: Notification.Name = Notification.Name("MemoryThresholdCrossed")
    static let memoryThresholdUncrossed: Notification.Name = Notification.Name("MemoryThresholdUncrossed")
}
