//
//  RunAnywhereActivityExtensionLiveActivity.swift
//  RunAnywhereActivityExtension
//
//  Live Activity widget — shows the dictation flow session status in
//  the Dynamic Island and on the Lock Screen / StandBy.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct DictationLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationActivityAttributes.self) { context in
            LockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    phaseIcon(phase: context.state.phase)
                        .font(.title2)
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
                phaseIcon(phase: context.state.phase)
            } compactTrailing: {
                if context.state.phase == "transcribing" {
                    ProgressView().scaleEffect(0.6)
                } else if context.state.phase == "ready" {
                    Image(systemName: "mic")
                        .font(.caption2)
                        .foregroundStyle(phaseColor(phase: context.state.phase))
                } else {
                    Text(formattedDuration(context.state.elapsedSeconds))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } minimal: {
                phaseIcon(phase: context.state.phase)
            }
            .keylineTint(phaseColor(phase: context.state.phase))
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func phaseIcon(phase: String) -> some View {
        switch phase {
        case "transcribing":
            ProgressView().scaleEffect(0.7).tint(.orange)
        case "done":
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case "ready":
            Image(systemName: "mic").foregroundStyle(.blue)
        default: // "listening"
            Image(systemName: "mic.fill").foregroundStyle(.red)
        }
    }

    private func phaseColor(phase: String) -> Color {
        switch phase {
        case "ready":        return .blue
        case "listening":    return .red
        case "transcribing": return .orange
        case "done":         return .green
        default:             return .secondary
        }
    }

    private func expandedTitle(for phase: String) -> String {
        switch phase {
        case "ready":        return "Ready"
        case "listening":    return "Listening…"
        case "transcribing": return "Transcribing…"
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
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(phaseColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Group {
                    if state.phase == "transcribing" {
                        ProgressView().tint(phaseColor)
                    } else {
                        Image(systemName: phaseSystemImage)
                            .font(.title3)
                            .foregroundStyle(phaseColor)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if !state.transcript.isEmpty {
                    Text(state.transcript)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if state.phase == "listening" {
                    Text(formattedDuration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if state.phase == "ready", state.wordCount > 0 {
                    Text("\(state.wordCount) words dictated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if state.wordCount > 0, state.phase != "listening" {
                Text("\(state.wordCount)w")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .activityBackgroundTint(Color.black.opacity(0.6))
        .activitySystemActionForegroundColor(.white)
    }

    private var title: String {
        switch state.phase {
        case "ready":        return "Mic Ready"
        case "listening":    return "Listening…"
        case "transcribing": return "Transcribing…"
        case "done":         return "Text inserted"
        default:             return "RunAnywhere"
        }
    }

    private var phaseSystemImage: String {
        switch state.phase {
        case "ready":  return "mic"
        case "done":   return "checkmark.circle.fill"
        default:       return "mic.fill"
        }
    }

    private var phaseColor: Color {
        switch state.phase {
        case "ready":        return .blue
        case "listening":    return .red
        case "transcribing": return .orange
        case "done":         return .green
        default:             return .accentColor
        }
    }

    private var formattedDuration: String {
        let m = state.elapsedSeconds / 60
        let s = state.elapsedSeconds % 60
        return m > 0 ? "\(m):\(String(format: "%02d", s))" : "\(s)s"
    }
}
