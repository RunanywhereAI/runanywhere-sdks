import Foundation

/// Detects tokenizer formats from model information and files
class TokenizerFormatDetector {
    private let logger = SDKLogger(category: "FormatDetector")

    // File patterns for different tokenizer formats
    private let formatPatterns: [TokenizerFormat: [String]] = [
        .huggingFace: ["tokenizer.json", "tokenizer_config.json"],
        .sentencePiece: ["tokenizer.model", "spiece.model", "*.model"],
        .wordPiece: ["vocab.txt", "vocab.json"],
        .bpe: ["vocab.json", "merges.txt", "encoder.json", "merges.bpe"],
        .tflite: ["vocab.txt", "labels.txt"],
        .coreML: ["vocab.plist", "tokenizer.mlmodel"]
    ]

    // Model format to default tokenizer format mapping
    private let defaultFormatMapping: [ModelFormat: TokenizerFormat] = [
        .tflite: .tflite,
        .mlmodel: .coreML,
        .mlpackage: .coreML,
        .onnx: .wordPiece,
        .ort: .wordPiece,
        .safetensors: .huggingFace,
        .bin: .huggingFace,
        .weights: .huggingFace,
        .gguf: .sentencePiece,
        .ggml: .sentencePiece
    ]

    func detectFormat(for model: ModelInfo) throws -> TokenizerFormat {
        logger.debug("Detecting tokenizer format for model: \(model.name)")

        // 1. Check explicit tokenizer format in model metadata
        if let explicitFormat = model.tokenizerFormat {
            logger.debug("Using explicit tokenizer format: \(explicitFormat)")
            return explicitFormat
        }

        // 2. Try to detect from model files if available locally
        if let modelPath = model.localPath {
            if let detectedFormat = try detectFormatFromFiles(at: modelPath) {
                logger.debug("Detected tokenizer format from files: \(detectedFormat)")
                return detectedFormat
            }
        }

        // 3. Try to detect from model metadata/description
        if let metadataFormat = detectFormatFromMetadata(model) {
            logger.debug("Detected tokenizer format from metadata: \(metadataFormat)")
            return metadataFormat
        }

        // 4. Use default format based on model format
        if let defaultFormat = defaultFormatMapping[model.format] {
            logger.debug("Using default tokenizer format for \(model.format): \(defaultFormat)")
            return defaultFormat
        }

        // 5. Fall back to most common format
        logger.warning("Could not detect tokenizer format for model \(model.name), using HuggingFace as fallback")
        return .huggingFace
    }

    func detectFormatFromFiles(at path: URL) throws -> TokenizerFormat? {
        let fileManager = FileManager.default

        // Ensure path exists
        guard fileManager.fileExists(atPath: path.path) else {
            logger.debug("Path does not exist: \(path.path)")
            return nil
        }

        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory)

        let searchPaths: [URL]
        if isDirectory.boolValue {
            searchPaths = [path]
        } else {
            // If it's a file, search in its parent directory
            searchPaths = [path.deletingLastPathComponent(), path]
        }

        // Get all files in search paths
        var allFiles: [String] = []
        for searchPath in searchPaths {
            do {
                let files = try fileManager.contentsOfDirectory(atPath: searchPath.path)
                allFiles.append(contentsOf: files.map { $0.lowercased() })
            } catch {
                logger.debug("Could not read directory \(searchPath.path): \(error)")
                continue
            }
        }

        // Check each format's patterns
        for (format, patterns) in formatPatterns {
            if matchesPatterns(files: allFiles, patterns: patterns) {
                logger.debug("Matched format \(format) with patterns: \(patterns)")
                return format
            }
        }

        // Special case: check file extensions
        if let detectedFormat = detectFromFileExtensions(files: allFiles) {
            return detectedFormat
        }

        logger.debug("No tokenizer format detected from files")
        return nil
    }

    func detectFormatFromMetadata(_ model: ModelInfo) -> TokenizerFormat? {
        // Check model description for hints
        if let description = model.metadata?.description?.lowercased() {
            if description.contains("huggingface") || description.contains("transformers") {
                return .huggingFace
            } else if description.contains("sentencepiece") || description.contains("llama") {
                return .sentencePiece
            } else if description.contains("wordpiece") || description.contains("bert") {
                return .wordPiece
            } else if description.contains("bpe") || description.contains("gpt") {
                return .bpe
            }
        }

        // Check model name for hints
        let modelName = model.name.lowercased()
        if modelName.contains("llama") || modelName.contains("mistral") || modelName.contains("codellama") {
            return .sentencePiece
        } else if modelName.contains("bert") || modelName.contains("roberta") {
            return .wordPiece
        } else if modelName.contains("gpt") {
            return .bpe
        }

        return nil
    }

    func detectSupportedFormats(at path: URL) -> [TokenizerFormat] {
        var supportedFormats: [TokenizerFormat] = []

        for format in TokenizerFormat.allCases {
            do {
                if let _ = try detectFormatFromFiles(at: path),
                   let specificFormat = try detectSpecificFormat(format, at: path),
                   specificFormat == format {
                    supportedFormats.append(format)
                }
            } catch {
                continue
            }
        }

        return supportedFormats
    }

    // MARK: - Private Implementation

    private func matchesPatterns(files: [String], patterns: [String]) -> Bool {
        for pattern in patterns {
            if pattern.contains("*") {
                // Handle wildcard patterns
                let regex = pattern.replacingOccurrences(of: "*", with: ".*")
                for file in files {
                    if file.range(of: regex, options: .regularExpression) != nil {
                        return true
                    }
                }
            } else {
                // Exact match
                if files.contains(pattern.lowercased()) {
                    return true
                }
            }
        }
        return false
    }

    private func detectFromFileExtensions(files: [String]) -> TokenizerFormat? {
        for file in files {
            let url = URL(fileURLWithPath: file)
            let ext = url.pathExtension.lowercased()

            switch ext {
            case "model":
                if file.contains("tokenizer") || file.contains("spiece") {
                    return .sentencePiece
                }
            case "json":
                if file.contains("tokenizer") {
                    return .huggingFace
                } else if file.contains("vocab") {
                    return .wordPiece
                } else if file.contains("encoder") {
                    return .bpe
                }
            case "txt":
                if file.contains("vocab") {
                    return .wordPiece
                } else if file.contains("merges") {
                    return .bpe
                }
            case "bpe":
                return .bpe
            case "plist":
                if file.contains("vocab") {
                    return .coreML
                }
            case "mlmodel":
                if file.contains("tokenizer") {
                    return .coreML
                }
            default:
                continue
            }
        }

        return nil
    }

    private func detectSpecificFormat(_ format: TokenizerFormat, at path: URL) throws -> TokenizerFormat? {
        let patterns = formatPatterns[format] ?? []
        let fileManager = FileManager.default

        let files = try fileManager.contentsOfDirectory(atPath: path.path)
        let lowercaseFiles = files.map { $0.lowercased() }

        if matchesPatterns(files: lowercaseFiles, patterns: patterns) {
            return format
        }

        return nil
    }
}

// MARK: - TokenizerFormat Extensions

extension TokenizerFormat {
    /// Priority order for format detection (higher = more specific)
    var detectionPriority: Int {
        switch self {
        case .huggingFace: return 100
        case .sentencePiece: return 90
        case .wordPiece: return 80
        case .bpe: return 70
        case .coreML: return 60
        case .tflite: return 50
        case .custom: return 10
        }
    }

    /// File patterns that uniquely identify this format
    var uniquePatterns: [String] {
        switch self {
        case .huggingFace: return ["tokenizer.json"]
        case .sentencePiece: return ["tokenizer.model", "spiece.model"]
        case .wordPiece: return ["vocab.txt"]
        case .bpe: return ["merges.txt", "merges.bpe"]
        case .coreML: return ["tokenizer.mlmodel"]
        case .tflite: return ["labels.txt"]
        case .custom: return []
        }
    }
}

/// Format detection confidence levels
enum DetectionConfidence {
    case high      // Unique files found
    case medium    // Common files found
    case low       // Based on heuristics
    case none      // No indicators found
}

/// Format detection result with confidence
struct FormatDetectionResult {
    let format: TokenizerFormat?
    let confidence: DetectionConfidence
    let evidence: [String]
    let alternatives: [TokenizerFormat]
}
