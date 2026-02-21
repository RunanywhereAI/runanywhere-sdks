//
//  YapRunActivityLiveActivity.swift
//  YapRunActivity
//
//  Live Activity widget — shows the dictation flow session status in
//  the Dynamic Island and on the Lock Screen / StandBy.
//  Brand: black background, white as the voice.
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Brand Colors (widget extension can't import main target)

private enum Brand {
    static let accent      = Color.white
    static let accentDark  = Color(white: 0.75)
    static let green       = Color(.sRGB, red: 0.063, green: 0.725, blue: 0.506) // #10B981
    static let darkBg      = Color(.sRGB, red: 0.0,  green: 0.0,   blue: 0.0)   // #000000
    static let darkSurface = Color(.sRGB, red: 0.08, green: 0.08,  blue: 0.08)  // #141414
}

struct DictationLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DictationActivityAttributes.self) { context in
            LockScreenView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("yaprun_icon")
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
                Image("yaprun_icon")
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
                Image("yaprun_icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .keylineTint(Brand.accent)
        }
    }

    // MARK: - Helpers

    private func expandedTitle(for phase: String) -> String {
        switch phase {
        case "ready":        return "YapRun"
        case "listening":    return "Listening..."
        case "transcribing": return "Transcribing..."
        case "done":         return "Done"
        default:             return "YapRun"
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
            Image("yaprun_icon")
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
                } else if state.wordCount > 0 {
                    Text("\(state.wordCount) words")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Link(destination: URL(string: "yaprun://kill")!) {
                    Image(systemName: "power")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.12), in: Circle())
                }

                Link(destination: URL(string: "yaprun://playground")!) {
                    Image(systemName: "note.text")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
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
        case "ready":        return "YapRun"
        case "listening":    return "Listening..."
        case "transcribing": return "Transcribing..."
        case "done":         return "Text inserted"
        default:             return "YapRun"
        }
    }

    private var formattedDuration: String {
        let m = state.elapsedSeconds / 60
        let s = state.elapsedSeconds % 60
        return m > 0 ? "\(m):\(String(format: "%02d", s))" : "\(s)s"
    }
}
