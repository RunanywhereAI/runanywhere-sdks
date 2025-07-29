import SwiftUI
import Combine
import UniformTypeIdentifiers

enum ConversionFormat: String, CaseIterable {
    case gguf = "GGUF"
    case coreml = "CoreML"
    case onnx = "ONNX"
    case mlx = "MLX"
    case pytorch = "PyTorch"
    case tflite = "TFLite"

    var iconName: String {
        switch self {
        case .gguf: return "cube.fill"
        case .coreml: return "brain.head.profile"
        case .onnx: return "network"
        case .mlx: return "memorychip.fill"
        case .pytorch: return "flame.fill"
        case .tflite: return "cpu.fill"
        }
    }
}

enum QuantizationLevel: String, CaseIterable {
    case none = "None"
    case int8 = "INT8"
    case int4 = "INT4"
    case fp16 = "FP16"
}

enum ConversionOptimizationTarget: String, CaseIterable {
    case speed = "Speed"
    case memory = "Memory"
    case accuracy = "Accuracy"
    case balanced = "Balanced"
}

struct ConversionResult {
    let success: Bool
    let outputPath: String?
    let error: String?
}

@MainActor
class ModelConversionWizardViewModel: ObservableObject {
    @Published var selectedModelFile: URL?
    @Published var detectedFormat: ConversionFormat?
    @Published var targetFormat: ConversionFormat?
    @Published var quantizationLevel: QuantizationLevel = .none
    @Published var optimizationTarget: ConversionOptimizationTarget = .balanced
    @Published var preserveMetadata: Bool = true

    @Published var isConverting: Bool = false
    @Published var conversionProgress: Double = 0.0
    @Published var conversionStatus: String = ""
    @Published var conversionResult: ConversionResult?

    private let modelConverter = ModelConverter()
    private let formatDetector = ModelFormatDetector()
    private var cancellables = Set<AnyCancellable>()

    var formattedFileSize: String {
        guard let file = selectedModelFile else { return "Unknown" }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        } catch {
            return "Unknown"
        }
    }

    var canStartConversion: Bool {
        selectedModelFile != nil &&
            targetFormat != nil &&
            targetFormat != detectedFormat &&
            !isConverting
    }

    func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            selectedModelFile = url
            detectFormat(for: url)
        case .failure(let error):
            print("File selection failed: \(error)")
        }
    }

    func clearSelection() {
        selectedModelFile = nil
        detectedFormat = nil
        targetFormat = nil
        conversionResult = nil
    }

    func selectTargetFormat(_ format: ConversionFormat) {
        guard canConvertTo(format) else { return }
        targetFormat = format
    }

    func canConvertTo(_ format: ConversionFormat) -> Bool {
        guard let sourceFormat = detectedFormat else { return false }
        return sourceFormat != format
    }

    func startConversion() {
        guard let sourceFile = selectedModelFile,
              let sourceFormat = detectedFormat,
              let targetFormat = targetFormat else { return }

        isConverting = true
        conversionProgress = 0.0
        conversionStatus = "Initializing conversion..."
        conversionResult = nil

        let conversionOptions = ModelConversionOptions(
            sourceFormat: sourceFormat,
            targetFormat: targetFormat,
            quantizationLevel: quantizationLevel,
            optimizationTarget: optimizationTarget,
            preserveMetadata: preserveMetadata
        )

        Task {
            do {
                // Simulate conversion process
                let outputPath = try await performSimulatedConversion(
                    sourceFile: sourceFile,
                    options: conversionOptions
                )

                conversionResult = ConversionResult(
                    success: true,
                    outputPath: outputPath,
                    error: nil
                )
            } catch {
                conversionResult = ConversionResult(
                    success: false,
                    outputPath: nil,
                    error: error.localizedDescription
                )
            }

            isConverting = false
        }
    }

    private func detectFormat(for url: URL) {
        Task {
            do {
                let modelFormatInfo = try await formatDetector.detectFormat(at: url)
                await MainActor.run {
                    detectedFormat = ConversionFormat.from(modelFormat: modelFormatInfo.format)
                }
            } catch {
                print("Format detection failed: \(error)")
                await MainActor.run {
                    detectedFormat = nil
                }
            }
        }
    }

    private func performSimulatedConversion(
        sourceFile: URL,
        options: ModelConversionOptions
    ) async throws -> String {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConvertedModels")

        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let outputFileName = sourceFile.deletingPathExtension().lastPathComponent +
            "_converted." + options.targetFormat.fileExtension
        let outputPath = outputDirectory.appendingPathComponent(outputFileName)

        conversionProgress = 0.1
        conversionStatus = "Analyzing source model..."
        try await Task.sleep(nanoseconds: 500_000_000)

        conversionProgress = 0.3
        conversionStatus = "Setting up conversion pipeline..."
        try await Task.sleep(nanoseconds: 500_000_000)

        conversionProgress = 0.5
        conversionStatus = "Converting model format..."
        try await Task.sleep(nanoseconds: 1_000_000_000)

        if options.quantizationLevel != .none {
            conversionProgress = 0.7
            conversionStatus = "Applying quantization..."
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        conversionProgress = 0.9
        conversionStatus = "Optimizing for \(options.optimizationTarget.rawValue.lowercased())..."
        try await Task.sleep(nanoseconds: 500_000_000)

        conversionProgress = 1.0
        conversionStatus = "Conversion completed!"

        let conversionData = """
        Model Conversion Simulation
        Source: \(sourceFile.lastPathComponent)
        Target Format: \(options.targetFormat.rawValue)
        Quantization: \(options.quantizationLevel.rawValue)
        Optimization: \(options.optimizationTarget.rawValue)
        """.data(using: .utf8) ?? Data()

        try conversionData.write(to: outputPath)

        return outputPath.path
    }
}

struct ModelConversionOptions {
    let sourceFormat: ConversionFormat
    let targetFormat: ConversionFormat
    let quantizationLevel: QuantizationLevel
    let optimizationTarget: ConversionOptimizationTarget
    let preserveMetadata: Bool
}


extension ConversionFormat {
    var fileExtension: String {
        switch self {
        case .gguf: return "gguf"
        case .coreml: return "mlmodel"
        case .onnx: return "onnx"
        case .mlx: return "npz"
        case .pytorch: return "pth"
        case .tflite: return "tflite"
        }
    }

    static func from(modelFormat: ModelFormat) -> ConversionFormat? {
        switch modelFormat {
        case .gguf: return .gguf
        case .coreML: return .coreml
        case .onnx: return .onnx
        case .mlx: return .mlx
        case .pytorch: return .pytorch
        case .tflite: return .tflite
        default: return nil
        }
    }
}
