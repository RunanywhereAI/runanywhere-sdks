#if os(macOS)
//
//  FlowBarView.swift
//  YapRun
//
//  SwiftUI content for the floating Flow Bar pill.
//  Shows idle state, waveform during recording, spinner during transcription.
//

import Combine
import SwiftUI

struct FlowBarView: View {
    private let dictation = MacDictationService.shared

    @State private var barPhase: Double = 0
    private let waveformTimer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            switch dictation.phase {
            case .idle:
                idleContent
            case .recording:
                recordingContent
            case .transcribing:
                transcribingContent
            case .inserting:
                transcribingContent
            case .done(let text):
                doneContent(text)
            case .error(let message):
                errorContent(message)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(pillBackground)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .frame(width: 220, height: 48)
        .onReceive(waveformTimer) { _ in
            if dictation.phase == .recording {
                barPhase += 0.15
            }
        }
        .onTapGesture {
            Task { await dictation.toggleFromFlowBar() }
        }
    }

    // MARK: - States

    private var idleContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text("YapRun")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var recordingContent: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)

            HStack(spacing: 2) {
                ForEach(0..<12, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white.opacity(0.9))
                        .frame(width: 2, height: miniBarHeight(for: index))
                }
            }
            .frame(height: 20)

            Text(formatTime(dictation.elapsedSeconds))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var transcribingContent: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.6)
            Text("Processing...")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func doneContent(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.primaryGreen)
            Text(text.prefix(30) + (text.count > 30 ? "..." : ""))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
        }
    }

    private func errorContent(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.primaryRed)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
    }

    // MARK: - Background

    private var pillBackground: some View {
        Group {
            switch dictation.phase {
            case .recording:
                Color(white: 0.12).opacity(0.95)
            case .done:
                AppColors.primaryGreen.opacity(0.15)
                    .background(Color(white: 0.12).opacity(0.95))
            default:
                Color(white: 0.12).opacity(0.9)
            }
        }
    }

    // MARK: - Helpers

    private func miniBarHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 3
        let maxH: CGFloat = 18
        let level = CGFloat(min(max(dictation.audioLevel, 0), 1))
        let wave = CGFloat(sin(Double(index) * 0.5 + barPhase))
        let dynamic = (maxH - base) * level * (0.5 + 0.5 * ((wave + 1) / 2))
        return base + dynamic
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

#endif
