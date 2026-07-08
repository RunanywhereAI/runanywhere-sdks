//
//  ModelPresentation.swift
//  RunAnywhereAI
//
//  Consumer-facing labels for SDK model metadata.
//

import Foundation
import SwiftUI
import RunAnywhere

private let privateHfTags: Set<String> = ["private", "requires-hf-auth", "hf-auth", "gated"]

struct ModelCapabilityBadge: Identifiable {
    let id: String
    let label: String
    let systemImage: String
    let color: Color
}

/// Internal-only size class derived from a model's byte footprint. Used for
/// recommendation fit checks and variant ordering — never surfaced as a raw
/// "Tiny/Small/…" pill in the consumer UI.
enum ModelSizeClass: Int, Comparable {
    case tiny
    case small
    case medium
    case large

    /// Thresholds are on the best-available size signal (download or memory).
    init(bytes: Int64) {
        switch bytes {
        case ..<400_000_000: self = .tiny
        case ..<1_200_000_000: self = .small
        case ..<3_000_000_000: self = .medium
        default: self = .large
        }
    }

    static func < (lhs: ModelSizeClass, rhs: ModelSizeClass) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The single, friendly "feel" tag shown on a model — the only speed/intelligence
/// signal surfaced to the consumer. Derived purely from size class.
enum ModelFeel: Int {
    case fast
    case balanced
    case smart

    init(sizeClass: ModelSizeClass) {
        switch sizeClass {
        case .tiny: self = .fast
        case .small: self = .balanced
        case .medium, .large: self = .smart
        }
    }

    var label: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .smart: return "Smart"
        }
    }

    var systemImage: String {
        switch self {
        case .fast: return "bolt.fill"
        case .balanced: return "scalemass"
        case .smart: return "lightbulb"
        }
    }

    var color: Color {
        switch self {
        case .fast: return AppColors.statusGreen
        case .balanced: return AppColors.statusBlue
        case .smart: return AppColors.primaryPurple
        }
    }
}

enum ConsumerModelGroup: Int, CaseIterable, Identifiable {
    case chatModels
    case appleBuiltIn
    case voiceModels
    case visionModels
    case imageGenerationModels
    case documentModels
    case modelAdapters
    case other

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .appleBuiltIn:
            return "Apple Built-in"
        case .chatModels:
            return "Chat Models"
        case .voiceModels:
            return "Voice Models"
        case .visionModels:
            return "Vision Models"
        case .imageGenerationModels:
            return "Image Generation"
        case .documentModels:
            return "Document Models"
        case .modelAdapters:
            return "LoRA & Adapters"
        case .other:
            return "Other Models"
        }
    }

    var footer: String {
        switch self {
        case .appleBuiltIn:
            return "Apple Foundation Models are built into supported devices and need no download."
        case .chatModels:
            return "Primary assistants for private chat. Download one to use it offline."
        case .voiceModels:
            return "Speech, dictation, and read-aloud models."
        case .visionModels:
            return "Models for camera, photo, and multimodal understanding."
        case .imageGenerationModels:
            return "On-device image generation, powered by Apple CoreML."
        case .documentModels:
            return "Embedding and answer models used by document Q&A."
        case .modelAdapters:
            return "Adapters customize a loaded base chat model. Choose a primary assistant first."
        case .other:
            return "Additional SDK model entries available on this device."
        }
    }
}

extension InferenceFramework {
    var consumerBackendLabel: String {
        switch self {
        case .llamaCpp:
            return "Llama CPP"
        case .onnx:
            return "ONNX Voice"
        case .foundationModels:
            return "Apple Built-in"
        case .systemTts:
            return "System Voice"
        case .fluidAudio:
            return "Fluid Audio"
        case .coreml:
            return "Core ML"
        case .mlx:
            return "MLX"
        case .sherpa:
            return "Sherpa Voice"
        case .qhexrt:
            return "Hexagon NPU"
        case .piperTts:
            return "Piper Voice"
        case .swiftTransformers:
            return "Swift Transformers"
        case .builtIn:
            return "Built-in"
        case .none:
            return "No Backend"
        case .unknown:
            return "Unknown Backend"
        case .tflite:
            return "TensorFlow Lite"
        case .executorch:
            return "ExecuTorch"
        case .mediapipe:
            return "MediaPipe"
        case .mlc:
            return "MLC"
        case .picoLlm:
            return "Pico LLM"
        default:
            return displayName
        }
    }

    var consumerBackendShortLabel: String {
        switch self {
        case .llamaCpp:
            return "Local"
        case .onnx:
            return "ONNX"
        case .foundationModels:
            return "Apple"
        case .systemTts:
            return "System"
        case .fluidAudio:
            return "Fluid"
        case .coreml:
            return "Core ML"
        case .mlx:
            return "MLX"
        case .sherpa:
            return "Sherpa"
        case .qhexrt:
            return "NPU"
        case .piperTts:
            return "Piper"
        case .swiftTransformers:
            return "Swift"
        case .builtIn:
            return "Built-in"
        case .none:
            return "None"
        case .unknown:
            return "Unknown"
        case .tflite:
            return "TFLite"
        case .executorch:
            return "ExecuTorch"
        case .mediapipe:
            return "MediaPipe"
        case .mlc:
            return "MLC"
        case .picoLlm:
            return "Pico"
        default:
            return displayName
        }
    }

    var consumerBackendDescription: String {
        switch self {
        case .llamaCpp:
            return "Private local language models"
        case .onnx:
            return "Speech, voice, and embedding models"
        case .foundationModels:
            return "Apple on-device intelligence"
        case .systemTts:
            return "Built into this device"
        case .fluidAudio:
            return "On-device audio models"
        case .coreml:
            return "Apple-optimized model runtime"
        case .mlx:
            return "Apple Silicon local models"
        case .sherpa:
            return "Private speech models"
        case .qhexrt:
            return "Qualcomm NPU acceleration"
        case .piperTts:
            return "Private text-to-speech voices"
        case .swiftTransformers:
            return "Native Swift transformer runtime"
        case .builtIn:
            return "Ships with this device or app"
        case .none:
            return "No model runtime required"
        case .unknown:
            return "Backend reported by the SDK"
        case .tflite:
            return "Mobile-optimized model runtime"
        case .executorch:
            return "Edge PyTorch runtime"
        case .mediapipe:
            return "Media pipeline runtime"
        case .mlc:
            return "Machine learning compiler runtime"
        case .picoLlm:
            return "Small local language models"
        default:
            return "RunAnywhere backend"
        }
    }

    var consumerBackendColor: Color {
        switch self {
        case .llamaCpp:
            return AppColors.primaryAccent
        case .onnx:
            return AppColors.primaryPurple
        case .foundationModels:
            return AppColors.textPrimary
        case .systemTts:
            return AppColors.statusBlue
        case .fluidAudio:
            return AppColors.primaryBlue
        case .coreml:
            return AppColors.primaryOrange
        case .mlx:
            return AppColors.primaryPurple
        case .sherpa:
            return AppColors.primaryPurple
        case .qhexrt:
            return AppColors.statusGreen
        case .piperTts:
            return AppColors.primaryBlue
        case .swiftTransformers:
            return AppColors.primaryAccent
        case .builtIn:
            return AppColors.statusGreen
        case .none:
            return AppColors.textSecondary
        case .unknown:
            return AppColors.statusGray
        case .tflite, .executorch, .mediapipe, .mlc, .picoLlm:
            return AppColors.statusBlue
        default:
            return AppColors.statusGray
        }
    }

    var consumerBackendIcon: String {
        switch self {
        case .llamaCpp:
            return "cube.transparent"
        case .onnx:
            return "waveform"
        case .foundationModels:
            return "apple.logo"
        case .systemTts:
            return "speaker.wave.2"
        case .fluidAudio:
            return "waveform.circle"
        case .coreml:
            return "cpu"
        case .mlx:
            return "memorychip"
        case .sherpa:
            return "waveform.badge.mic"
        case .qhexrt:
            return "cpu.fill"
        case .piperTts:
            return "speaker.wave.3"
        case .swiftTransformers:
            return "curlybraces"
        case .builtIn:
            return "checkmark.seal"
        case .none:
            return "circle.slash"
        case .unknown:
            return "questionmark.app"
        case .tflite, .executorch, .mediapipe, .mlc, .picoLlm:
            return "square.stack.3d.up"
        default:
            return "square.stack.3d.up"
        }
    }
}

extension RAModelCategory {
    var consumerCapabilityLabel: String {
        switch self {
        case .language:
            return "Chat"
        case .multimodal, .vision:
            return "Vision"
        case .imageGeneration:
            return "Images"
        case .audio:
            return "Audio"
        case .speechRecognition:
            return "Dictation"
        case .speechSynthesis:
            return "Voice"
        case .voiceActivityDetection:
            return "Speech Detect"
        case .embedding:
            return "Documents"
        default:
            return "Model"
        }
    }

    var consumerCapabilityIcon: String {
        switch self {
        case .language:
            return "message"
        case .multimodal, .vision:
            return "eye"
        case .imageGeneration:
            return "photo"
        case .audio:
            return "waveform.circle"
        case .speechRecognition:
            return "waveform"
        case .speechSynthesis:
            return "speaker.wave.2"
        case .voiceActivityDetection:
            return "waveform.badge.mic"
        case .embedding:
            return "doc.text.magnifyingglass"
        default:
            return "cube"
        }
    }
}

extension RAModelInfo {
    var isAppleFoundationModel: Bool {
        framework == .foundationModels
    }

    var isLoraAdapterModel: Bool {
        isLoRAAdapterArtifact
    }

    var requiresHfAuth: Bool {
        metadata.tags.contains { privateHfTags.contains($0.lowercased()) } ||
            framework == .qhexrt && downloadURL.localizedCaseInsensitiveContains("_HNPU")
    }

    var consumerSizeLabel: String {
        if isBuiltIn {
            return "No download"
        }
        let bytes = downloadSizeBytes > 0 ? downloadSizeBytes : memoryRequiredBytes
        if bytes > 0 {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
        }
        return requiresHfAuth ? "Size varies" : "Size unknown"
    }

    var consumerModelGroup: ConsumerModelGroup {
        if isAppleFoundationModel {
            return .appleBuiltIn
        }
        if isLoraAdapterModel {
            return .modelAdapters
        }

        switch category {
        case .language:
            return .chatModels
        case .speechRecognition, .speechSynthesis, .voiceActivityDetection, .audio:
            return .voiceModels
        case .multimodal, .vision:
            return .visionModels
        case .imageGeneration:
            return .imageGenerationModels
        case .embedding:
            return .documentModels
        default:
            return .other
        }
    }

    var consumerStatusLabel: String {
        if isBuiltIn {
            return "Built-in"
        }
        if localPathURL != nil {
            return "Ready"
        }
        return "Download"
    }

    var consumerStatusIcon: String {
        if isBuiltIn || localPathURL != nil {
            return "checkmark.circle.fill"
        }
        return "arrow.down.circle"
    }

    var consumerStatusColor: Color {
        if isBuiltIn || localPathURL != nil {
            return AppColors.statusGreen
        }
        return AppColors.primaryAccent
    }

    var consumerCapabilityBadges: [ModelCapabilityBadge] {
        var badges: [ModelCapabilityBadge] = [
            ModelCapabilityBadge(
                id: "capability-\(category.rawValue)",
                label: category.consumerCapabilityLabel,
                systemImage: category.consumerCapabilityIcon,
                color: framework.consumerBackendColor
            )
        ]

        if supportsThinking {
            badges.append(ModelCapabilityBadge(
                id: "thinking",
                label: "Thinking",
                systemImage: "brain",
                color: AppColors.primaryPurple
            ))
        }

        if supportsLora {
            badges.append(ModelCapabilityBadge(
                id: "lora",
                label: "LoRA",
                systemImage: "sparkles",
                color: AppColors.primaryBlue
            ))
        }

        if requiresHfAuth {
            badges.append(ModelCapabilityBadge(
                id: "hf-auth",
                label: "Private HF",
                systemImage: "lock.fill",
                color: AppColors.statusOrange
            ))
        }

        if isBuiltIn {
            badges.append(ModelCapabilityBadge(
                id: "builtin",
                label: "No download",
                systemImage: "checkmark.seal",
                color: AppColors.statusGreen
            ))
        }

        return badges
    }

    /// Best available size signal in bytes (download size preferred, else the
    /// runtime memory requirement). Zero when unknown.
    var consumerSizeBytes: Int64 {
        downloadSizeBytes > 0 ? downloadSizeBytes : memoryRequiredBytes
    }

    /// Coarse size class used internally for recommendation fit checks and
    /// variant ordering. Not surfaced as a raw pill.
    var consumerSizeClass: ModelSizeClass {
        ModelSizeClass(bytes: consumerSizeBytes)
    }

    /// The single friendly feel tag (Fast / Balanced / Smart) surfaced to users.
    var consumerFeel: ModelFeel {
        ModelFeel(sizeClass: consumerSizeClass)
    }

    /// True when the model advertises tool / function-calling ability via its
    /// id or name (e.g. LFM2 *-tool, Llama-3.2-3B tool-calling build).
    var supportsToolCalling: Bool {
        let haystack = "\(id) \(name)".lowercased()
        return haystack.contains("tool") || haystack.contains("function")
    }

    /// The single most notable capability tag, or nil when nothing stands out.
    /// Ordering reflects consumer relevance: tools → thinking → modality.
    var notableCapabilityBadge: ModelCapabilityBadge? {
        if category == .language {
            if supportsToolCalling {
                return ModelCapabilityBadge(
                    id: "cap-tools",
                    label: "Great for tools",
                    systemImage: "wrench.and.screwdriver",
                    color: AppColors.primaryOrange
                )
            }
            if supportsThinking {
                return ModelCapabilityBadge(
                    id: "cap-thinks",
                    label: "Thinks",
                    systemImage: "brain",
                    color: AppColors.primaryPurple
                )
            }
            return nil
        }

        switch category {
        case .multimodal, .vision, .imageGeneration:
            return ModelCapabilityBadge(
                id: "cap-vision", label: "Vision",
                systemImage: "eye", color: AppColors.primaryBlue
            )
        case .speechRecognition, .voiceActivityDetection:
            return ModelCapabilityBadge(
                id: "cap-dictation", label: "Voice",
                systemImage: "waveform", color: AppColors.primaryBlue
            )
        case .speechSynthesis, .audio:
            return ModelCapabilityBadge(
                id: "cap-voice", label: "Voice",
                systemImage: "speaker.wave.2", color: AppColors.primaryBlue
            )
        case .embedding:
            return ModelCapabilityBadge(
                id: "cap-documents", label: "Documents",
                systemImage: "doc.text.magnifyingglass", color: AppColors.primaryBlue
            )
        default:
            return nil
        }
    }

    /// AT MOST TWO clean consumer tags: a feel tag (Fast/Balanced/Smart) plus
    /// one notable capability tag. No quant strings, no backend names, no size
    /// pills. Built-in models show only their capability.
    var consumerTags: [ModelCapabilityBadge] {
        var tags: [ModelCapabilityBadge] = []

        if !isBuiltIn, consumerSizeBytes > 0, category == .language {
            let feel = consumerFeel
            tags.append(ModelCapabilityBadge(
                id: "feel-\(feel.rawValue)",
                label: feel.label,
                systemImage: feel.systemImage,
                color: feel.color
            ))
        }

        if let capability = notableCapabilityBadge {
            tags.append(capability)
        }

        return tags
    }

    /// Clean, human display name: family + parameter size, with quantization
    /// suffixes (Q4_K_M, Q8_0, 4bit, DWQ, …) and backend/vendor prefixes
    /// stripped. "MLX Qwen3 0.6B 4bit" → "Qwen3 0.6B",
    /// "LiquidAI LFM2 1.2B Tool Q4_K_M" → "LFM2 1.2B Tool".
    var consumerDisplayName: String {
        Self.cleanDisplayName(from: name)
    }

    /// Tokens never shown in a consumer display name (lowercased).
    private static let strippedNameTokens: Set<String> = [
        "mlx", "liquidai", "sherpa", "gguf",
        "q4_k_m", "q4_k_s", "q5_k_m", "q6_k", "q8_0",
        "4bit", "5bit", "6bit", "8bit", "f16", "fp16", "dwq"
    ]

    /// Parenthetical segments removed when their content is technical.
    private static let strippedParentheticals: Set<String> = [
        "onnx", "tool calling", "embedding"
    ]

    private static func cleanDisplayName(from rawName: String) -> String {
        var text = rawName

        // Drop technical parentheticals like "(ONNX)" / "(Tool Calling)".
        for phrase in strippedParentheticals {
            let pattern = "(?i)\\([^)]*\(phrase)[^)]*\\)"
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }

        let cleaned = text
            .split(separator: " ")
            .filter { !strippedNameTokens.contains($0.lowercased()) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        return cleaned.isEmpty ? rawName : cleaned
    }
}

extension InferenceFramework {
    /// Short, neutral backend label for the subtle backend pill
    /// (MLX / Llama CPP / ONNX / Sherpa / Apple).
    var consumerBackendBadgeLabel: String {
        switch self {
        case .llamaCpp: return "Llama CPP"
        case .mlx: return "MLX"
        case .onnx: return "ONNX"
        case .sherpa: return "Sherpa"
        case .foundationModels, .systemTts, .builtIn: return "Apple"
        case .piperTts: return "Piper"
        case .coreml: return "Core ML"
        default: return consumerBackendShortLabel
        }
    }
}

/// Small, neutral backend pill (never the dominant element of a row).
struct BackendPill: View {
    let framework: InferenceFramework

    var body: some View {
        Text(framework.consumerBackendBadgeLabel)
            .font(AppTypography.caption2)
            .fontWeight(.medium)
            .foregroundColor(AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.small)
            .padding(.vertical, AppSpacing.xxSmall)
            .background(AppColors.backgroundSecondary)
            .cornerRadius(AppSpacing.cornerRadiusSmall)
    }
}

struct ConsumerBadge: View {
    let badge: ModelCapabilityBadge

    var body: some View {
        HStack(spacing: AppSpacing.xxSmall) {
            Image(systemName: badge.systemImage)
            Text(badge.label)
                .lineLimit(1)
        }
        .font(AppTypography.caption2)
        .padding(.horizontal, AppSpacing.small)
        .padding(.vertical, AppSpacing.xxSmall)
        .background(badge.color.opacity(0.12))
        .foregroundColor(badge.color)
        .cornerRadius(AppSpacing.cornerRadiusSmall)
    }
}
