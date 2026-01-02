//
//  ModelComponents.swift
//  RunAnywhereAI
//
//  Shared components for model selection
//

import SwiftUI
import RunAnywhere

struct FrameworkRow: View {
    let framework: InferenceFramework
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: frameworkIcon)
                    .foregroundColor(frameworkColor)
                    .frame(width: AppSpacing.xxLarge)

                VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
                    Text(framework.displayName)
                        .font(AppTypography.headline)
                    Text(frameworkDescription)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundColor(AppColors.textSecondary)
                    .font(AppTypography.caption)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var frameworkIcon: String {
        switch framework {
        case .foundationModels:
            return "apple.logo"
        case .llamaCpp:
            return "cpu"
        case .onnx:
            return "brain"
        case .fluidAudio:
            return "waveform"
        default:
            return "cpu"
        }
    }

    private var frameworkColor: Color {
        switch framework {
        case .foundationModels:
            return AppColors.textPrimary
        case .llamaCpp:
            return AppColors.primaryAccent
        case .onnx:
            return AppColors.statusGray
        default:
            return AppColors.statusGray
        }
    }

    private var frameworkDescription: String {
        switch framework {
        case .foundationModels:
            return "Apple's pre-installed system models"
        case .llamaCpp:
            return "Efficient LLM inference with GGUF models"
        case .onnx:
            return "ONNX Runtime for STT/TTS models"
        case .fluidAudio:
            return "Speaker diarization"
        default:
            return "Machine learning framework"
        }
    }
}
