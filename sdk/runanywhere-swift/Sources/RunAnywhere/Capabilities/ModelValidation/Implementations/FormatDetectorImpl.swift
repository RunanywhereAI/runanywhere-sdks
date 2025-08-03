import Foundation

/// Implementation of format detection for model files
public class FormatDetectorImpl: FormatDetector {

    // MARK: - Properties

    private let logger = SDKLogger(category: "FormatDetector")

    // Known file extensions mapped to formats
    private let extensionMap: [String: ModelFormat] = [
        "mlmodel": .mlmodel,
        "mlmodelc": .mlmodel,
        "mlpackage": .mlpackage,
        "tflite": .tflite,
        "onnx": .onnx,
        "ort": .ort,
        "safetensors": .safetensors,
        "gguf": .gguf,
        "ggml": .ggml,
        "pte": .pte
    ]

    // MARK: - Initialization

    public init() {}

    // MARK: - FormatDetector Protocol

    public func detectFormat(at url: URL) -> ModelFormat? {
        let ext = url.pathExtension.lowercased()

        logger.debug("Detecting format for file: \(url.lastPathComponent)")

        // First try by extension
        if let format = extensionMap[ext] {
            logger.debug("Format detected by extension: \(format.rawValue)")
            return format
        }

        // Special handling for generic extensions
        switch ext {
        case "bin":
            return detectBinaryFormat(at: url)
        case "pt", "pth":
            return .bin // PyTorch models are typically binary
        case "h5", "hdf5":
            return .bin // Keras/TensorFlow models are binary
        default:
            // Try to detect by reading file header
            return detectByContent(at: url)
        }
    }

    // MARK: - Private Methods

    private func detectBinaryFormat(at url: URL) -> ModelFormat? {
        // Check if it's part of a larger model structure
        let parentDir = url.deletingLastPathComponent()

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: parentDir,
                includingPropertiesForKeys: nil
            )

            // Check for accompanying files that indicate format
            for file in files {
                let filename = file.lastPathComponent.lowercased()

                if filename == "config.json" {
                    // Likely HuggingFace format
                    logger.debug("Detected HuggingFace format by config.json")
                    return .safetensors
                } else if filename.contains("ggml") {
                    logger.debug("Detected GGML format by filename pattern")
                    return .ggml
                }
            }
        } catch {
            logger.error("Failed to scan directory: \(error)")
        }

        return .bin
    }

    private func detectByContent(at url: URL) -> ModelFormat? {
        guard let file = try? FileHandle(forReadingFrom: url) else {
            logger.error("Cannot open file for format detection")
            return nil
        }
        defer { try? file.close() }

        let headerData = file.readData(ofLength: 16)
        guard headerData.count >= 4 else {
            logger.error("File too small for format detection")
            return nil
        }

        // Check for known magic bytes
        if let magic = String(data: headerData.prefix(4), encoding: .utf8) {
            switch magic {
            case "GGUF":
                logger.debug("Detected GGUF format by magic bytes")
                return .gguf
            case "GGML":
                logger.debug("Detected GGML format by magic bytes")
                return .ggml
            default:
                break
            }
        }

        // Check for other binary patterns
        if headerData.starts(with: [0x08, 0x00, 0x00, 0x00]) {
            // Possible protobuf (ONNX)
            logger.debug("Possible ONNX format detected")
            return .onnx
        }

        // Check for TensorFlow Lite pattern
        if headerData.count >= 8 {
            let tfliteMagic = headerData.subdata(in: 4..<8)
            if tfliteMagic == Data([0x54, 0x46, 0x4C, 0x33]) { // "TFL3"
                logger.debug("Detected TFLite format by magic bytes")
                return .tflite
            }
        }

        logger.debug("Unable to detect format from content")
        return nil
    }
}
