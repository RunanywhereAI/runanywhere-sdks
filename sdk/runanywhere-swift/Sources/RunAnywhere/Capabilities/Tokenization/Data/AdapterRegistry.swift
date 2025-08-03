import Foundation

/// Registry for tokenizer adapter types
class AdapterRegistry {
    private var adapters: [TokenizerFormat: TokenizerAdapter.Type] = [:]
    private let lock = NSLock()
    private let logger = SDKLogger(category: "AdapterRegistry")

    init() {
        registerDefaultAdapters()
    }

    // MARK: - Adapter Management

    func registerAdapter(_ adapterType: TokenizerAdapter.Type, for format: TokenizerFormat) {
        lock.lock()
        defer { lock.unlock() }

        adapters[format] = adapterType
        logger.info("Registered adapter for format: \(format)")
    }

    func getAdapter(for format: TokenizerFormat) -> TokenizerAdapter.Type? {
        lock.lock()
        defer { lock.unlock() }

        return adapters[format]
    }

    func unregisterAdapter(for format: TokenizerFormat) {
        lock.lock()
        defer { lock.unlock() }

        adapters.removeValue(forKey: format)
        logger.info("Unregistered adapter for format: \(format)")
    }

    func isFormatSupported(_ format: TokenizerFormat) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return adapters[format] != nil
    }

    func getAvailableFormats() -> [TokenizerFormat] {
        lock.lock()
        defer { lock.unlock() }

        return Array(adapters.keys)
    }

    // MARK: - Registry Information

    func getStatistics() -> AdapterRegistryStatistics {
        lock.lock()
        defer { lock.unlock() }

        let supportedFormats = Array(adapters.keys)
        let adapterCount = adapters.count

        return AdapterRegistryStatistics(
            adapterCount: adapterCount,
            supportedFormats: supportedFormats,
            registrationTime: Date()
        )
    }

    func getAdapterInfo(for format: TokenizerFormat) -> AdapterInfo? {
        lock.lock()
        defer { lock.unlock() }

        guard let adapterType = adapters[format] else {
            return nil
        }

        return AdapterInfo(
            format: format,
            adapterType: String(describing: adapterType),
            capabilities: getAdapterCapabilities(adapterType),
            isAvailable: true
        )
    }

    func getAllAdapterInfo() -> [AdapterInfo] {
        lock.lock()
        defer { lock.unlock() }

        return adapters.compactMap { format, adapterType in
            AdapterInfo(
                format: format,
                adapterType: String(describing: adapterType),
                capabilities: getAdapterCapabilities(adapterType),
                isAvailable: true
            )
        }
    }

    // MARK: - Validation

    func validateAdapter(_ adapterType: TokenizerAdapter.Type, for format: TokenizerFormat) -> AdapterValidationResult {
        var issues: [String] = []
        var isValid = true

        // Check if adapter implements required methods
        // This is a compile-time check in Swift, but we can add runtime validations

        // Check if adapter can handle the format
        // This would require adding format compatibility to the adapter protocol

        // For now, assume all registered adapters are valid
        if !isValid {
            issues.append("Adapter validation failed")
        }

        return AdapterValidationResult(
            isValid: isValid,
            format: format,
            adapterType: String(describing: adapterType),
            issues: issues
        )
    }

    func validateAllAdapters() -> [AdapterValidationResult] {
        lock.lock()
        defer { lock.unlock() }

        return adapters.map { format, adapterType in
            validateAdapter(adapterType, for: format)
        }
    }

    // MARK: - Default Adapters

    private func registerDefaultAdapters() {
        // Register built-in adapter types
        // In a real implementation, these would be concrete adapter classes

        logger.info("Registering default tokenizer adapters")

        // Note: These would be actual adapter implementations
        // registerAdapter(HuggingFaceAdapter.self, for: .huggingFace)
        // registerAdapter(SentencePieceAdapter.self, for: .sentencePiece)
        // registerAdapter(WordPieceAdapter.self, for: .wordPiece)
        // registerAdapter(BPEAdapter.self, for: .bpe)
        // registerAdapter(CoreMLAdapter.self, for: .coreML)
        // registerAdapter(TFLiteAdapter.self, for: .tflite)

        logger.info("Default adapters registration completed")
    }

    // MARK: - Adapter Discovery

    func discoverAvailableAdapters() -> [TokenizerFormat] {
        // This could scan for available adapter implementations
        // For now, return registered formats
        return getAvailableFormats()
    }

    func findBestAdapter(for requirements: AdapterRequirements) -> TokenizerFormat? {
        lock.lock()
        defer { lock.unlock() }

        // Score adapters based on requirements
        var bestFormat: TokenizerFormat?
        var bestScore: Double = 0

        for (format, _) in adapters {
            let score = calculateAdapterScore(format: format, requirements: requirements)
            if score > bestScore {
                bestScore = score
                bestFormat = format
            }
        }

        return bestFormat
    }

    // MARK: - Private Implementation

    private func getAdapterCapabilities(_ adapterType: TokenizerAdapter.Type) -> [String] {
        // This would inspect the adapter type to determine capabilities
        // For now, return basic capabilities
        return ["encode", "decode", "batch_encode"]
    }

    private func calculateAdapterScore(format: TokenizerFormat, requirements: AdapterRequirements) -> Double {
        var score: Double = 1.0

        // Prefer exact format match
        if let preferredFormat = requirements.preferredFormat, preferredFormat == format {
            score += 2.0
        }

        // Consider performance requirements
        switch requirements.performanceRequirement {
        case .high:
            // Some formats are generally faster
            switch format {
            case .sentencePiece, .wordPiece:
                score += 1.0
            default:
                break
            }
        case .medium, .low:
            break
        }

        // Consider memory requirements
        switch requirements.memoryRequirement {
        case .low:
            // Some formats use less memory
            switch format {
            case .wordPiece, .tflite:
                score += 1.0
            default:
                break
            }
        case .medium, .high:
            break
        }

        return score
    }
}

// MARK: - Registry Data Structures

struct AdapterRegistryStatistics {
    let adapterCount: Int
    let supportedFormats: [TokenizerFormat]
    let registrationTime: Date
}

struct AdapterInfo {
    let format: TokenizerFormat
    let adapterType: String
    let capabilities: [String]
    let isAvailable: Bool
}

struct AdapterValidationResult {
    let isValid: Bool
    let format: TokenizerFormat
    let adapterType: String
    let issues: [String]
}

struct AdapterRequirements {
    let preferredFormat: TokenizerFormat?
    let performanceRequirement: PerformanceRequirement
    let memoryRequirement: MemoryRequirement
    let batchSizeRequirement: Int?
    let maxSequenceLength: Int?

    enum PerformanceRequirement {
        case low
        case medium
        case high
    }

    enum MemoryRequirement {
        case low
        case medium
        case high
    }
}

// MARK: - Registry Events

extension Notification.Name {
    static let tokenizerAdapterRegistered = Notification.Name("TokenizerAdapterRegistered")
    static let tokenizerAdapterUnregistered = Notification.Name("TokenizerAdapterUnregistered")
}

// MARK: - Thread-Safe Access

extension AdapterRegistry {
    func withRegistryAccess<T>(_ block: ([TokenizerFormat: TokenizerAdapter.Type]) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }

        return try block(adapters)
    }
}
