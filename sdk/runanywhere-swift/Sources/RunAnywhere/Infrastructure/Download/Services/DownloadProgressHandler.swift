import Foundation

/// Handles download progress tracking and reporting
final class DownloadProgressHandler {

    func calculateSpeed(progress: Progress) -> String {
        guard progress.totalUnitCount > 0 else { return "0 B/s" }

        // This is a simplified calculation - in production, you'd track time elapsed
        let bytesPerSecond = Double(progress.completedUnitCount) / max(1, progress.estimatedTimeRemaining ?? 1)

        if bytesPerSecond < 1024 {
            return String(format: "%.0f B/s", bytesPerSecond)
        } else if bytesPerSecond < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1024)
        } else {
            return String(format: "%.1f MB/s", bytesPerSecond / (1024 * 1024))
        }
    }
}
