//
//  ModelComponents.swift
//  RunAnywhereAI
//
//  Shared components for model selection
//

import SwiftUI
import RunAnywhereSDK

struct FrameworkRow: View {
    let framework: LLMFramework
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: frameworkIcon)
                    .foregroundColor(frameworkColor)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(framework.displayName)
                        .font(.headline)
                    Text(frameworkDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
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
            return .black
        case .mediaPipe:
            return .blue
        default:
            return .gray
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
