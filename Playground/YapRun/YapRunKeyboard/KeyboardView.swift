//
//  KeyboardView.swift
//  YapRunKeyboard
//
//  SwiftUI keyboard UI — implements the 5-state WisprFlow-style UX.
//  Brand: black background, white as the voice.
//

import SwiftUI
import Combine

// MARK: - Brand Colors (keyboard extension can't import main target)
// All colors adapt to the system color scheme via the `scheme` environment value.

private enum Brand {
    static let green = Color(.sRGB, red: 0.063, green: 0.725, blue: 0.506) // #10B981

    // Adaptive helpers — call with the current colorScheme
    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : .black
    }
    static func accentDark(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.75) : Color(white: 0.35)
    }
    static func keySurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.13) : Color(white: 0.95)
    }
    static func keyCard(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.17) : Color(white: 0.88)
    }
    static func textPrimary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : .black
    }
    static func textSecondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5)
    }
    static func overlayColor(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : .black
    }
    static func dividerColor(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.1)
    }
    static func yapBtnBg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.22) : Color(white: 0.85)
    }
}

struct KeyboardView: View {
    let onRunTap: () -> Void
    let onMicTap: () -> Void
    let onStopTap: () -> Void
    let onCancelTap: () -> Void
    let onUndoTap: () -> Void
    let onNextKeyboard: () -> Void
    let onSpace: () -> Void
    let onReturn: () -> Void
    let onDelete: () -> Void
    let onInsertCharacter: (String) -> Void

    // MARK: - State

    @Environment(\.colorScheme) private var colorScheme
    @State private var sessionState: String = "idle"
    @State private var audioLevel: Float = 0
    @State private var barPhase: Double = 0
    @State private var showUndo = false
    @State private var showStats = false

    private let stateTimer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()
    private let waveformTimer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if showStats {
                statsView
            } else {
                switch sessionState {
                case "listening", "transcribing", "done":
                    waveformView
                default:
                    fullKeyboardView
                }
            }
        }
        .background(
            RadialGradient(
                colors: [Brand.accent(colorScheme).opacity(0.025), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: 160
            )
            .allowsHitTesting(false)
        )
        .onAppear { refreshState() }
        .onReceive(stateTimer) { _ in refreshState() }
        .onReceive(waveformTimer) { _ in
            guard sessionState == "listening" else { return }
            audioLevel = SharedDataBridge.shared.audioLevel
            barPhase += 0.15
        }
        .onChange(of: sessionState) { _, newState in
            if newState == "done" {
                showUndo = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation { showUndo = false }
                }
            }
        }
    }

    // MARK: - Full Keyboard

    private var fullKeyboardView: some View {
        VStack(spacing: 0) {
            toolbarRow
            Divider().overlay(Brand.dividerColor(colorScheme))
            numberRow
            specialCharsRow1
            specialCharsRow2
            bottomRow
        }
    }

    // MARK: Toolbar

    private var toolbarRow: some View {
        HStack(spacing: 0) {
            iconButton(systemImage: "slider.horizontal.3") {
                withAnimation(.easeInOut(duration: 0.2)) { showStats = true }
            }
            .padding(.leading, 4)

            Spacer()

            switch sessionState {
            case "idle":
                Button(action: onRunTap) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Yap")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(Brand.textPrimary(colorScheme))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Brand.yapBtnBg(colorScheme))
                    .cornerRadius(8)
                }
                .padding(.trailing, 8)

            case "activating":
                ProgressView()
                    .tint(Brand.accent(colorScheme))
                    .scaleEffect(0.85)
                    .padding(.trailing, 12)

            case "ready":
                HStack(spacing: 6) {
                    Text("Using iPhone Microphone")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Brand.textSecondary(colorScheme))
                    Button(action: onMicTap) {
                        Image(systemName: "waveform")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(Brand.accent(colorScheme))
                            .padding(8)
                            .background(Brand.accent(colorScheme).opacity(0.15), in: Circle())
                    }
                }
                .padding(.trailing, 8)

            default:
                EmptyView()
            }
        }
        .frame(height: 44)
    }

    // MARK: Number Row

    private var numberRow: some View {
        HStack(spacing: 0) {
            ForEach(["1","2","3","4","5","6","7","8","9","0"], id: \.self) { char in
                characterKey(char)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    // MARK: Special Characters Row 1

    private var specialCharsRow1: some View {
        HStack(spacing: 0) {
            ForEach(["-","/",":",";"," ( "," ) ","$","&","@","\""], id: \.self) { char in
                characterKey(char)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    // MARK: Special Characters Row 2

    private var specialCharsRow2: some View {
        HStack(spacing: 0) {
            characterKey("#+=")
                .frame(maxWidth: .infinity)
            ForEach([".","," ,"?","!","'"], id: \.self) { char in
                characterKey(char)
            }
            Button(action: onDelete) {
                Image(systemName: "delete.left")
                    .font(.system(size: 14))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Brand.keyCard(colorScheme))
                    .cornerRadius(6)
            }
            .foregroundColor(Brand.textPrimary(colorScheme).opacity(0.8))
            .padding(3)
            .frame(maxWidth: .infinity, minHeight: 42)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    // MARK: Bottom Row

    private var bottomRow: some View {
        HStack(spacing: 0) {
            Button(action: onNextKeyboard) {
                Image(systemName: "globe")
                    .font(.system(size: 18))
                    .frame(width: 46, height: 42)
                    .background(Brand.keyCard(colorScheme))
                    .cornerRadius(6)
            }
            .foregroundColor(Brand.textPrimary(colorScheme).opacity(0.8))
            .padding(3)

            Button(action: onNextKeyboard) {
                Text("ABC")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 52, height: 42)
                    .background(Brand.keyCard(colorScheme))
                    .cornerRadius(6)
            }
            .foregroundColor(Brand.textPrimary(colorScheme).opacity(0.8))
            .padding(3)

            Button(action: onSpace) {
                HStack(spacing: 6) {
                    Image("yaprun_icon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Text("YapRun")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Brand.textPrimary(colorScheme).opacity(0.9))
                }
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(Brand.keySurface(colorScheme))
                .cornerRadius(6)
            }
            .padding(3)

            Button(action: onReturn) {
                Image(systemName: "return")
                    .font(.system(size: 16))
                    .frame(width: 52, height: 42)
                    .background(Brand.keyCard(colorScheme))
                    .cornerRadius(6)
            }
            .foregroundColor(Brand.textPrimary(colorScheme).opacity(0.8))
            .padding(3)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    // MARK: - Stats View

    private var statsView: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showStats = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Brand.textPrimary(colorScheme).opacity(0.7))
                        .frame(width: 36, height: 36)
                        .background(Brand.overlayColor(colorScheme).opacity(0.12), in: Circle())
                }
                .padding(.leading, 12)

                Spacer()
            }
            .padding(.top, 10)

            Spacer()

            let stats = loadDictationStats()
            Text(formattedWordCount(stats.totalWords))
                .font(.system(size: 56, weight: .bold, design: .serif))
                .foregroundStyle(Brand.accent(colorScheme))

            Text("words")
                .font(.system(size: 56, weight: .bold, design: .serif))
                .foregroundStyle(Brand.accent(colorScheme))

            Text("you've dictated so far.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Brand.textSecondary(colorScheme))
                .padding(.top, 4)

            if stats.sessionCount > 0 {
                Text("You've had \(stats.sessionCount) dictation session\(stats.sessionCount == 1 ? "" : "s")")
                    .font(.system(size: 14))
                    .foregroundStyle(Brand.textPrimary(colorScheme).opacity(0.4))
                    .padding(.top, 2)
            }

            Spacer()
        }
        .frame(minHeight: 260)
    }

    // MARK: - Waveform View

    private var waveformView: some View {
        VStack(spacing: 0) {
            Spacer()

            if sessionState != "transcribing" {
                HStack {
                    Button(action: sessionState == "done" ? {} : onCancelTap) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(sessionState == "done" ? Color.clear : Brand.textPrimary(colorScheme).opacity(0.8))
                            .frame(width: 44, height: 44)
                    }
                    .padding(.leading, 20)

                    Spacer()

                    VStack(spacing: 2) {
                        if sessionState == "done" {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Brand.green)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Brand.accent(colorScheme))
                                Text("Listening")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Brand.textPrimary(colorScheme))
                            }
                            Text("iPhone Microphone")
                                .font(.caption)
                                .foregroundStyle(Brand.textSecondary(colorScheme))
                        }
                    }

                    Spacer()

                    if sessionState == "done" && showUndo {
                        Button(action: onUndoTap) {
                            Image(systemName: "arrow.uturn.backward.circle")
                                .font(.system(size: 22))
                                .foregroundStyle(Brand.textSecondary(colorScheme))
                        }
                        .padding(.trailing, 20)
                    } else {
                        Button(action: onStopTap) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Brand.accent(colorScheme))
                                .frame(width: 44, height: 44)
                        }
                        .padding(.trailing, 20)
                        .opacity(sessionState == "done" ? 0 : 1)
                    }
                }
            }

            waveformBars
                .frame(height: 56)
                .padding(.horizontal, 20)

            if sessionState == "transcribing" {
                VStack(spacing: 4) {
                    ProgressView()
                        .tint(Brand.accent(colorScheme))
                        .scaleEffect(0.9)
                    Text("Transcribing...")
                        .font(.caption)
                        .foregroundStyle(Brand.textSecondary(colorScheme))
                }
                .padding(.vertical, 8)
            }

            Spacer()

            HStack {
                Button(action: onNextKeyboard) {
                    Image(systemName: "globe")
                        .font(.system(size: 18))
                        .frame(width: 46, height: 40)
                        .background(Brand.keyCard(colorScheme))
                        .cornerRadius(6)
                }
                .foregroundColor(Brand.textPrimary(colorScheme).opacity(0.8))
                .padding(.leading, 7)
                .padding(.bottom, 6)
                Spacer()
            }
        }
        .frame(minHeight: 180)
    }

    // MARK: Waveform Bars

    private var waveformBars: some View {
        HStack(spacing: 3) {
            ForEach(0..<30, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barGradient)
                    .frame(width: 3, height: barHeight(for: index))
                    .animation(.easeOut(duration: 0.08), value: audioLevel)
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 4
        let maxH: CGFloat = 50
        if sessionState == "transcribing" {
            let wave = CGFloat(sin(Double(index) * 0.5 + barPhase))
            return base + (maxH * 0.25) * (0.5 + 0.5 * wave)
        }
        if sessionState == "done" {
            return base + 8
        }
        let wave = CGFloat(sin(Double(index) * 0.45 + barPhase))
        let level = CGFloat(min(max(audioLevel, 0), 1))
        let dynamic = (maxH - base) * level * (0.6 + 0.4 * ((wave + 1) / 2))
        return base + dynamic
    }

    private var barGradient: LinearGradient {
        switch sessionState {
        case "done":
            return LinearGradient(
                colors: [Brand.green.opacity(0.9), Brand.green.opacity(0.5)],
                startPoint: .top, endPoint: .bottom
            )
        default:
            return LinearGradient(
                colors: [Brand.accent(colorScheme).opacity(0.95), Brand.accentDark(colorScheme).opacity(0.5)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // MARK: - Helpers

    private func characterKey(_ char: String) -> some View {
        Button(action: { onInsertCharacter(char.trimmingCharacters(in: .whitespaces)) }) {
            Text(char)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(Brand.keySurface(colorScheme))
                .cornerRadius(6)
        }
        .foregroundColor(Brand.textPrimary(colorScheme).opacity(0.9))
        .padding(3)
    }

    private func iconButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .padding(10)
        }
        .foregroundColor(Brand.textSecondary(colorScheme))
    }

    // MARK: - Stats Loading

    private struct DictationStats {
        let totalWords: Int
        let sessionCount: Int
    }

    private struct DictationEntry: Codable {
        let id: UUID
        let text: String
        let date: Date
    }

    private func loadDictationStats() -> DictationStats {
        guard let data = SharedDataBridge.shared.defaults?.data(forKey: SharedConstants.Keys.dictationHistory),
              let entries = try? JSONDecoder().decode([DictationEntry].self, from: data) else {
            return DictationStats(totalWords: 0, sessionCount: 0)
        }
        let totalWords = entries.reduce(0) { $0 + $1.text.split(separator: " ").count }
        return DictationStats(totalWords: totalWords, sessionCount: entries.count)
    }

    private func formattedWordCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    // MARK: - State Refresh

    private func refreshState() {
        var newState = SharedDataBridge.shared.sessionState

        if newState != "idle" {
            let heartbeat = SharedDataBridge.shared.lastHeartbeatTimestamp
            if heartbeat > 0 && (Date().timeIntervalSince1970 - heartbeat) > 3.0 {
                newState = "idle"
            }
        }

        if newState != sessionState {
            withAnimation(.easeInOut(duration: 0.2)) {
                sessionState = newState
            }
        }
    }
}
