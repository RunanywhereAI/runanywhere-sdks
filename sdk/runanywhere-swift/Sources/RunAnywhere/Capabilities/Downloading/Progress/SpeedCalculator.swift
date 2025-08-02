import Foundation

/// Calculates download speed and estimates time remaining
public class SpeedCalculator {

    // MARK: - Properties

    private var samples: [(bytes: Int64, timestamp: Date)] = []
    private let maxSamples = 20
    private let minSamplesForEstimate = 3

    // MARK: - Public Methods

    /// Add a data sample
    public func addSample(bytes: Int64, timestamp: Date = Date()) {
        samples.append((bytes: bytes, timestamp: timestamp))

        // Keep only recent samples
        if samples.count > maxSamples {
            samples.removeFirst()
        }
    }

    /// Calculate current download speed in bytes per second
    public func calculateSpeed() -> Double? {
        guard samples.count >= 2 else { return nil }

        let firstSample = samples.first!
        let lastSample = samples.last!

        let bytesDiff = lastSample.bytes - firstSample.bytes
        let timeDiff = lastSample.timestamp.timeIntervalSince(firstSample.timestamp)

        guard timeDiff > 0 else { return nil }

        return Double(bytesDiff) / timeDiff
    }

    /// Calculate smoothed download speed using moving average
    public func calculateSmoothedSpeed() -> Double? {
        guard samples.count >= minSamplesForEstimate else {
            return calculateSpeed()
        }

        // Calculate speeds for each interval
        var speeds: [Double] = []

        for i in 1..<samples.count {
            let prevSample = samples[i - 1]
            let currSample = samples[i]

            let bytesDiff = currSample.bytes - prevSample.bytes
            let timeDiff = currSample.timestamp.timeIntervalSince(prevSample.timestamp)

            if timeDiff > 0 {
                speeds.append(Double(bytesDiff) / timeDiff)
            }
        }

        guard !speeds.isEmpty else { return nil }

        // Return weighted average (more recent samples have higher weight)
        var weightedSum: Double = 0
        var totalWeight: Double = 0

        for (index, speed) in speeds.enumerated() {
            let weight = Double(index + 1)
            weightedSum += speed * weight
            totalWeight += weight
        }

        return weightedSum / totalWeight
    }

    /// Estimate time remaining based on current speed
    public func estimateTimeRemaining(
        currentBytes: Int64,
        totalBytes: Int64
    ) -> TimeInterval? {
        guard let speed = calculateSmoothedSpeed(),
              speed > 0,
              totalBytes > currentBytes else {
            return nil
        }

        let remainingBytes = totalBytes - currentBytes
        return TimeInterval(Double(remainingBytes) / speed)
    }

    /// Format speed as human-readable string
    public func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useKB, .useMB, .useGB]

        let bytesString = formatter.string(fromByteCount: Int64(bytesPerSecond))
        return "\(bytesString)/s"
    }

    /// Format time remaining as human-readable string
    public func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2

        return formatter.string(from: seconds) ?? "calculating..."
    }

    /// Reset all samples
    public func reset() {
        samples.removeAll()
    }
}
