//
//  VoiceAssistantComponents.swift
//  RunAnywhereAI
//
//  Reusable UI components for VoiceAssistantView
//

import SwiftUI

// MARK: - ConversationBubble

struct ConversationBubble: View {
    let speaker: String
    let message: String
    let isUser: Bool

    private func fillColor(isUser: Bool) -> Color {
        if isUser {
            #if os(macOS)
            return Color(NSColor.controlBackgroundColor)
            #else
            return Color(.secondarySystemBackground)
            #endif
        } else {
            return AppColors.primaryAccent.opacity(0.08)
        }
    }

    var body: some View {
        Text(message)
            .font(.body)
            .foregroundColor(.primary)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(fillColor(isUser: isUser))
            )
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - ModelBadge

struct ModelBadge: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: AdaptiveSizing.badgeFontSize))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: AdaptiveSizing.badgeFontSize - 1))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: AdaptiveSizing.badgeFontSize))
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, AdaptiveSizing.badgePaddingH)
        .padding(.vertical, AdaptiveSizing.badgePaddingV)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
}
