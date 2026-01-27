//
//  MLXVLMModels.swift
//  RunAnywhere SDK
//
//  Supported MLX VLM models and their configurations.
//  These models use safetensors format from HuggingFace and run natively on Apple Silicon.
//

import Foundation

// MARK: - MLX VLM Model Catalog

/// Supported MLX VLM model configurations
///
/// These are pre-quantized models from HuggingFace optimized for Apple Silicon.
/// Models are downloaded automatically when first used.
public enum MLXVLMModel: String, CaseIterable, Sendable {

    // MARK: - SmolVLM (Mobile-Optimized)

    /// SmolVLM 256M - Smallest model, fastest inference
    case smolVLM256M = "HuggingFaceTB/SmolVLM-256M-Instruct"

    /// SmolVLM 500M - Small model with better quality
    case smolVLM500M = "HuggingFaceTB/SmolVLM-500M-Instruct"

    // MARK: - Qwen2-VL (High Quality)

    /// Qwen2-VL 2B 4-bit - Good balance of quality and speed
    case qwen2VL2B4bit = "mlx-community/Qwen2-VL-2B-Instruct-4bit"

    /// Qwen2-VL 7B 4-bit - High quality, larger model
    case qwen2VL7B4bit = "mlx-community/Qwen2-VL-7B-Instruct-4bit"

    // MARK: - Qwen2.5-VL (Latest)

    /// Qwen2.5-VL 3B 4-bit - Latest Qwen VLM, recommended
    case qwen25VL3B4bit = "mlx-community/Qwen2.5-VL-3B-Instruct-4bit"

    /// Qwen2.5-VL 7B 4-bit - Latest Qwen VLM, high quality
    case qwen25VL7B4bit = "mlx-community/Qwen2.5-VL-7B-Instruct-4bit"

    // MARK: - LLaVA (Classic)

    /// LLaVA v1.6 Mistral 7B 4-bit - Classic VLM architecture
    case llavaV16Mistral7B4bit = "mlx-community/llava-v1.6-mistral-7b-hf-4bit"

    // MARK: - Properties

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .smolVLM256M: return "SmolVLM 256M"
        case .smolVLM500M: return "SmolVLM 500M"
        case .qwen2VL2B4bit: return "Qwen2-VL 2B (4-bit)"
        case .qwen2VL7B4bit: return "Qwen2-VL 7B (4-bit)"
        case .qwen25VL3B4bit: return "Qwen2.5-VL 3B (4-bit)"
        case .qwen25VL7B4bit: return "Qwen2.5-VL 7B (4-bit)"
        case .llavaV16Mistral7B4bit: return "LLaVA v1.6 Mistral 7B (4-bit)"
        }
    }

    /// Estimated memory usage in GB
    public var estimatedMemoryGB: Double {
        switch self {
        case .smolVLM256M: return 0.5
        case .smolVLM500M: return 0.8
        case .qwen2VL2B4bit: return 2.0
        case .qwen2VL7B4bit: return 5.0
        case .qwen25VL3B4bit: return 2.5
        case .qwen25VL7B4bit: return 5.0
        case .llavaV16Mistral7B4bit: return 5.0
        }
    }

    /// Whether this model is suitable for mobile (< 4GB memory)
    public var isMobileFriendly: Bool {
        estimatedMemoryGB < 4.0
    }

    /// HuggingFace model ID
    public var huggingFaceId: String { rawValue }

    /// Model family/architecture
    public var family: String {
        switch self {
        case .smolVLM256M, .smolVLM500M:
            return "SmolVLM"
        case .qwen2VL2B4bit, .qwen2VL7B4bit:
            return "Qwen2-VL"
        case .qwen25VL3B4bit, .qwen25VL7B4bit:
            return "Qwen2.5-VL"
        case .llavaV16Mistral7B4bit:
            return "LLaVA"
        }
    }

    /// Whether this model is quantized
    public var isQuantized: Bool {
        rawValue.contains("4bit") || rawValue.contains("8bit")
    }

    /// Get all mobile-friendly models
    public static var mobileFriendly: [MLXVLMModel] {
        allCases.filter { $0.isMobileFriendly }
    }

    /// Default recommended model for iOS
    public static var defaultForIOS: MLXVLMModel {
        .qwen25VL3B4bit
    }

    /// Default recommended model for macOS
    public static var defaultForMacOS: MLXVLMModel {
        .qwen25VL7B4bit
    }
}

// MARK: - ModelInfo Extension

public extension MLXVLMModel {

    /// Convert to ModelInfo for registration with the model registry
    func toModelInfo() -> ModelInfo {
        ModelInfo(
            id: "mlx-vlm-\(rawValue.replacingOccurrences(of: "/", with: "-"))",
            name: displayName,
            category: .vision,
            format: .unknown, // MLX uses safetensors, not a standard format
            framework: .mlx,
            downloadURL: URL(string: "https://huggingface.co/\(rawValue)"),
            localPath: nil,
            artifactType: .custom(strategyId: "mlx-huggingface"),
            downloadSize: Int64(estimatedMemoryGB * 1024 * 1024 * 1024),
            contextLength: 4096,
            supportsThinking: false,
            thinkingPattern: nil,
            description: "MLX VLM: \(displayName) - \(family) architecture, \(String(format: "%.1f", estimatedMemoryGB))GB",
            source: .local
        )
    }
}
