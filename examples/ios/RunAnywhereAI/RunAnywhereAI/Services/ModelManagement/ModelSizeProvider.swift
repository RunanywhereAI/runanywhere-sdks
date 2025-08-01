//
//  ModelSizeProvider.swift
//  RunAnywhereAI
//
//  Provides abstracted model size calculation
//

import Foundation

// MARK: - Model Size Provider Protocol

protocol ModelSizeProvider {
    func calculateSize(at url: URL) -> Int64
    func estimateSize(from sizeString: String) -> Int64
}

// MARK: - Base Model Size Provider

class BaseModelSizeProvider: ModelSizeProvider {

    func calculateSize(at url: URL) -> Int64 {
        let fileManager = FileManager.default

        // Check if it's a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }

        if isDirectory.boolValue {
            // Calculate directory size recursively
            return calculateDirectorySize(at: url)
        } else {
            // Single file size
            do {
                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                return attributes[.size] as? Int64 ?? 0
            } catch {
                print("Error getting file size: \(error)")
                return 0
            }
        }
    }

    func estimateSize(from sizeString: String) -> Int64 {
        // Parse various size formats
        let cleanedString = sizeString.trimmingCharacters(in: .whitespaces)

        // Try to extract number and unit
        let pattern = #"(\d+\.?\d*)\s*([KMGT]?B)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: cleanedString, options: [], range: NSRange(cleanedString.startIndex..., in: cleanedString)),
              let numberRange = Range(match.range(at: 1), in: cleanedString),
              let unitRange = Range(match.range(at: 2), in: cleanedString) else {
            return parseSimpleSize(sizeString)
        }

        let numberString = String(cleanedString[numberRange])
        let unit = String(cleanedString[unitRange]).uppercased()

        guard let value = Double(numberString) else {
            return parseSimpleSize(sizeString)
        }

        let multiplier: Double
        switch unit {
        case "B":
            multiplier = 1
        case "KB":
            multiplier = 1_000
        case "MB":
            multiplier = 1_000_000
        case "GB":
            multiplier = 1_000_000_000
        case "TB":
            multiplier = 1_000_000_000_000
        default:
            multiplier = 1
        }

        return Int64(value * multiplier)
    }

    private func calculateDirectorySize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])

                // Skip directories in size calculation
                if resourceValues.isDirectory == true {
                    continue
                }

                if let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            } catch {
                print("Error calculating size for \(fileURL): \(error)")
            }
        }

        return totalSize
    }

    private func parseSimpleSize(_ sizeString: String) -> Int64 {
        // Fallback parser for simple formats
        if sizeString.hasSuffix("GB") {
            let value = Double(sizeString.dropLast(2).trimmingCharacters(in: .whitespaces)) ?? 0
            return Int64(value * 1_000_000_000)
        } else if sizeString.hasSuffix("MB") {
            let value = Double(sizeString.dropLast(2).trimmingCharacters(in: .whitespaces)) ?? 0
            return Int64(value * 1_000_000)
        } else if sizeString.hasSuffix("KB") {
            let value = Double(sizeString.dropLast(2).trimmingCharacters(in: .whitespaces)) ?? 0
            return Int64(value * 1_000)
        }

        // Try to parse as raw number (assume MB if no unit)
        if let value = Double(sizeString.trimmingCharacters(in: .whitespaces)) {
            return Int64(value * 1_000_000)
        }

        return 0
    }
}

// MARK: - MLPackage Size Provider

class MLPackageSizeProvider: BaseModelSizeProvider {

    override func calculateSize(at url: URL) -> Int64 {
        // For .mlpackage, we calculate the entire directory size
        return super.calculateSize(at: url)
    }

    override func estimateSize(from sizeString: String) -> Int64 {
        // MLPackage sizes are often given with a tilde
        let cleanedString = sizeString.replacingOccurrences(of: "~", with: "")
        return super.estimateSize(from: cleanedString)
    }
}

// MARK: - Model Size Manager

class ModelSizeManager {
    static let shared = ModelSizeManager()

    private let providers: [LLMFramework: ModelSizeProvider] = [
        .swiftTransformers: MLPackageSizeProvider(),
        .coreML: MLPackageSizeProvider()
    ]

    private let defaultProvider = BaseModelSizeProvider()

    private init() {}

    /// Get the size provider for a specific framework
    func getProvider(for framework: LLMFramework) -> ModelSizeProvider {
        return providers[framework] ?? defaultProvider
    }

    /// Calculate actual size of a model at a given path
    func calculateSize(at url: URL, framework: LLMFramework? = nil) -> Int64 {
        if let framework = framework,
           let provider = providers[framework] {
            return provider.calculateSize(at: url)
        }

        // Try to determine format from URL
        let format = ModelFormat.from(extension: url.pathExtension)
        let formatManager = ModelFormatManager.shared
        let handler = formatManager.getHandler(for: url, format: format)

        return handler.calculateModelSize(at: url)
    }

    /// Estimate size from a size string
    func estimateSize(from sizeString: String, framework: LLMFramework? = nil) -> Int64 {
        if let framework = framework,
           let provider = providers[framework] {
            return provider.estimateSize(from: sizeString)
        }

        return defaultProvider.estimateSize(from: sizeString)
    }
}

// MARK: - Extensions

extension ModelInfo {
    /// Get the actual size of this model if it's downloaded
    var actualSize: Int64? {
        guard let path = path else { return nil }

        let url = URL(fileURLWithPath: path)
        return ModelSizeManager.shared.calculateSize(at: url, framework: framework)
    }

    /// Get the estimated size in bytes
    var estimatedSizeInBytes: Int64 {
        return ModelSizeManager.shared.estimateSize(from: size, framework: framework)
    }
}
