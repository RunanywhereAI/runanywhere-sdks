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
        case .mediaPipe:
            return "brain.filled.head.profile"
        default:
            return "cpu"
        }
    }

    private var frameworkColor: Color {
        switch framework {
        case .foundationModels:
            return AppColors.textPrimary
        case .mediaPipe:
            return AppColors.statusBlue
        default:
            return AppColors.statusGray
        }
    }

    private var frameworkDescription: String {
        switch framework {
        case .foundationModels:
            return "Apple's pre-installed system models"
        case .mediaPipe:
            return "Google's cross-platform ML framework"
        default:
            return "Machine learning framework"
        }
    }
}
