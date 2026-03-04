//
//  RunAnywhereActivityExtensionLiveActivity.swift
//  RunAnywhereActivityExtension
//
//  Live Activity widget — shows the dictation flow session status in
//  the Dynamic Island and on the Lock Screen / StandBy.
//  Branded with RunAnywhere color palette (#FF5500 primary accent).
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Brand Colors (widget extension can't import main target)

private enum Brand {
    static let accent      = Color(.sRGB, red: 1.0, green: 0.333, blue: 0.0)    // #FF5500
    static let accentDark  = Color(.sRGB, red: 0.902, green: 0.271, blue: 0.0)  // #E64500
    static let green       = Color(.sRGB, red: 0.063, green: 0.725, blue: 0.506) // #10B981
    static let darkBg      = Color(.sRGB, red: 0.059, green: 0.090, blue: 0.165) // #0F172A
    static let darkSurface = Color(.sRGB, red: 0.102, green: 0.122, blue: 0.180) // #1A1F2E
}

struct DictationLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationActivityAttributes.self) { context in
            LockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("runanywhere_icon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(expandedTitle(for: context.state.phase))
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formattedDuration(context.state.elapsedSeconds))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if context.state.wordCount > 0 {
                            Text("\(context.state.wordCount)w")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.transcript.isEmpty {
                        Text(context.state.transcript)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(.horizontal, 8)
                    }
                }
            } compactLeading: {
                Image("runanywhere_icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } compactTrailing: {
                if context.state.phase == "transcribing" {
                    ProgressView().scaleEffect(0.6).tint(Brand.accent)
                } else if context.state.phase == "ready" {
                    Image(systemName: "waveform")
                        .font(.caption2)
                        .foregroundStyle(Brand.accent)
                } else {
                    Text(formattedDuration(context.state.elapsedSeconds))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } minimal: {
                Image("runanywhere_icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .keylineTint(Brand.accent)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func phaseIcon(phase: String) -> some View {
        switch phase {
        case "transcribing":
            ProgressView().scaleEffect(0.7).tint(Brand.accent)
        case "done":
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.green)
        case "listening":
            Image(systemName: "waveform")
                .foregroundStyle(Brand.accent)
                .symbolEffect(.variableColor.iterative, isActive: true)
        default: // "ready"
            Image(systemName: "waveform").foregroundStyle(Brand.accent)
        }
    }

    private func expandedTitle(for phase: String) -> String {
        switch phase {
        case "ready":        return "Ready"
        case "listening":    return "Listening..."
        case "transcribing": return "Transcribing..."
        case "done":         return "Done"
        default:             return "RunAnywhere"
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return m > 0 ? "\(m):\(String(format: "%02d", s))" : "\(s)s"
    }
}

// MARK: - Lock Screen / StandBy View

private struct LockScreenView: View {
    let state: DictationActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            // RunAnywhere app icon
            Image("runanywhere_icon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                if !state.transcript.isEmpty {
                    Text(state.transcript)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                } else if state.phase == "listening" {
                    Text(formattedDuration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                } else if state.phase == "ready", state.wordCount > 0 {
                    Text("\(state.wordCount) words dictated")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer()

            if state.wordCount > 0, state.phase != "listening" {
                Text("\(state.wordCount)w")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.trailing, 4)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Brand.darkBg, Brand.darkSurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .activityBackgroundTint(Brand.darkBg)
        .activitySystemActionForegroundColor(.white)
    }

    private var title: String {
        switch state.phase {
        case "ready":        return "RunAnywhere Ready"
        case "listening":    return "Listening..."
        case "transcribing": return "Transcribing..."
        case "done":         return "Text inserted"
        default:             return "RunAnywhere"
        }
    }

    private var formattedDuration: String {
        let m = state.elapsedSeconds / 60
        let s = state.elapsedSeconds % 60
        return m > 0 ? "\(m):\(String(format: "%02d", s))" : "\(s)s"
    }
}
