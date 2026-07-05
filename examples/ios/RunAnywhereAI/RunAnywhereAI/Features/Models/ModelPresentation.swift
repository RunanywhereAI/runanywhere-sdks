//
//  ModelPresentation.swift
//  RunAnywhereAI
//
//  Consumer-facing labels for SDK model metadata.
//

import SwiftUI
import RunAnywhere

struct ModelCapabilityBadge: Identifiable {
    let id: String
    let label: String
    let systemImage: String
    let color: Color
}

enum ConsumerModelGroup: Int, CaseIterable, Identifiable {
    case chatModels
    case appleBuiltIn
    case voiceModels
    case visionModels
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
            return "Local Llama"
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
        case .metalrt:
            return "Apple Metal"
        case .genie:
            return "Qualcomm Genie"
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
        case .metalrt:
            return "Metal"
        case .genie:
            return "Genie"
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
        case .metalrt:
            return "Apple GPU acceleration"
        case .genie:
            return "Qualcomm accelerated runtime"
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
        case .metalrt:
            return AppColors.primaryBlue
        case .genie:
            return AppColors.statusGreen
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
        case .metalrt:
            return "bolt.fill"
        case .genie:
            return "sparkles"
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
        let normalizedID = id.lowercased()
        if normalizedID.hasPrefix("lora-adapter:") {
            return true
        }
        if metadata.tags.contains(where: { $0.lowercased() == "lora-adapter" || $0.lowercased() == "lora" }) {
            return true
        }
        return name.localizedCaseInsensitiveContains("lora")
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
        case .multimodal, .vision, .imageGeneration:
            return .visionModels
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
}

struct ConsumerBadge: View {
    let badge: ModelCapabilityBadge

    var body: some View {
        HStack(spacing: AppSpacing.xxSmall) {
            Image(systemName: badge.systemImage)
            Text(badge.label)
        }
        .font(AppTypography.caption2)
        .padding(.horizontal, AppSpacing.small)
        .padding(.vertical, AppSpacing.xxSmall)
        .background(badge.color.opacity(0.12))
        .foregroundColor(badge.color)
        .cornerRadius(AppSpacing.cornerRadiusSmall)
    }
}
