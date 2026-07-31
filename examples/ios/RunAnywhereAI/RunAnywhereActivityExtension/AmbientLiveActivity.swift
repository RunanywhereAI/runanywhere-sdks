//
//  AmbientLiveActivity.swift
//  RunAnywhereActivityExtension
//
//  Live Activity for the Ambient Memory Lab.
//
//  The Lock Screen is visible to anyone holding the phone, so this surface
//  never renders transcript, summary, speaker, or memory text — only that a
//  session is recording, for how long, and how much it has captured.
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private enum AmbientBrand {
    static let accent      = Color(.sRGB, red: 1.0, green: 0.412, blue: 0.0)     // #FF6900
    static let red         = Color(.sRGB, red: 0.937, green: 0.267, blue: 0.267) // #EF4444
    static let darkBg      = Color(.sRGB, red: 0.059, green: 0.090, blue: 0.165) // #0F172A
    static let darkSurface = Color(.sRGB, red: 0.102, green: 0.122, blue: 0.180) // #1A1F2E
}

struct AmbientLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AmbientActivityAttributes.self) { context in
            AmbientLockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "brain.head.profile")
                        .font(.title3)
                        .foregroundStyle(AmbientBrand.accent)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(AmbientPhase.title(context.state.phase, isStopped: context.state.isStopped))
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(AmbientPhase.duration(context.state.elapsedSeconds))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("\(context.state.segmentCount) captured")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.isStopped {
                        Button(intent: StopAmbientMemoryIntent()) {
                            Label("Stop", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .tint(AmbientBrand.red)
                        .padding(.horizontal, 8)
                    }
                }
            } compactLeading: {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundStyle(AmbientBrand.accent)
            } compactTrailing: {
                Text(AmbientPhase.duration(context.state.elapsedSeconds))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            } minimal: {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundStyle(AmbientBrand.accent)
            }
            .keylineTint(AmbientBrand.accent)
        }
    }
}

// MARK: - Lock Screen

private struct AmbientLockScreenView: View {
    let state: AmbientActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "brain.head.profile")
                .font(.title)
                .foregroundStyle(AmbientBrand.accent)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(AmbientPhase.title(state.phase, isStopped: state.isStopped))
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            if !state.isStopped {
                Button(intent: StopAmbientMemoryIntent()) {
                    Image(systemName: "stop.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(AmbientBrand.red)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [AmbientBrand.darkBg, AmbientBrand.darkSurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .activityBackgroundTint(AmbientBrand.darkBg)
        .activitySystemActionForegroundColor(.white)
    }

    private var subtitle: String {
        var parts = [AmbientPhase.duration(state.elapsedSeconds)]
        parts.append("\(state.segmentCount) captured")
        if state.actionItemCount > 0 { parts.append("\(state.actionItemCount) to do") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Presentation Helpers

private enum AmbientPhase {
    static func title(_ phase: String, isStopped: Bool) -> String {
        if isStopped { return "Note stopped" }
        switch phase {
        case "preparing":  return "Preparing note"
        case "speech":     return "Note hearing speech"
        case "processing": return "Note transcribing"
        case "paused":     return "Note paused"
        default:           return "Note recording"
        }
    }

    static func duration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
