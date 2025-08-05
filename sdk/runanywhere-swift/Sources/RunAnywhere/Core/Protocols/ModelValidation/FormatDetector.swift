import Foundation

/// Protocol for detecting model formats from files
public protocol FormatDetector {
    /// Detects the model format from a file URL
    /// - Parameter url: The URL of the file to analyze
    /// - Returns: The detected model format, or nil if format cannot be determined
    func detectFormat(at url: URL) -> ModelFormat?
}
