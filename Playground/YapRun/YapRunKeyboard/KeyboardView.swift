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
}

struct KeyboardView: View {
    let onRunTap: () -> Void
    let onMicTap: () -> Void
    let onStopTap: () -> Void
    let onCancelTap: () -> Void
    let onUndoTap: () -> Void
    let onRedoTap: () -> Void
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
    @State private var checkmarkTapped = false
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var showStats = false
    @State private var isDeleting = false
    @State private var deleteStartTime: Date?

    private let stateTimer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()
    private let waveformTimer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()
    private let deleteRepeatTimer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

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
        .onAppear {
            refreshState()
            canUndo = SharedDataBridge.shared.lastInsertedText != nil
            canRedo = SharedDataBridge.shared.undoText != nil
        }
        .onReceive(stateTimer) { _ in refreshState() }
        .onReceive(waveformTimer) { _ in
            guard sessionState == "listening" || (checkmarkTapped && sessionState != "done") else { return }
            audioLevel = SharedDataBridge.shared.audioLevel
            barPhase += 0.15
        }
        .onChange(of: sessionState) { _, newState in
            switch newState {
            case "done":
                checkmarkTapped = false
                canUndo = true
                canRedo = false
            case "listening":
                checkmarkTapped = false
                canUndo = false
                canRedo = false
            case "idle", "ready":
                checkmarkTapped = false
            default:
                break
            }
        }
        .onReceive(deleteRepeatTimer) { _ in
            guard isDeleting, let start = deleteStartTime,
                  Date().timeIntervalSince(start) > 0.35 else { return }
            onDelete()
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
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showStats = true }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 48, height: 48)
            }
            .foregroundColor(Brand.textSecondary(colorScheme))
            .padding(.leading, 4)

            Spacer()

            switch sessionState {
            case "idle":
                Button(action: onRunTap) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .bold))
                        Text("Yap")
                            .font(.system(size: 20, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        colorScheme == .dark
                            ? Color(white: 0.28)
                            : Color(white: 0.18)
                    )
                    .cornerRadius(14)
                }
                .padding(.trailing, 8)

            case "activating":
                ProgressView()
                    .tint(Brand.accent(colorScheme))
                    .scaleEffect(0.85)
                    .padding(.trailing, 12)

            case "ready":
                Button(action: onMicTap) {
                    Image(systemName: "waveform")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Brand.green, in: Circle())
                }
                .padding(.trailing, 8)

            default:
                EmptyView()
            }
        }
        .frame(height: 58)
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
            Image(systemName: "delete.left")
                .font(.system(size: 16))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Brand.keyCard(colorScheme))
                .cornerRadius(6)
                .foregroundColor(Brand.textPrimary(colorScheme).opacity(0.8))
                .padding(3)
                .frame(maxWidth: .infinity, minHeight: 50)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isDeleting {
                                isDeleting = true
                                deleteStartTime = Date()
                                onDelete()
                            }
                        }
                        .onEnded { _ in
                            isDeleting = false
                            deleteStartTime = nil
                        }
                )
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    // MARK: Bottom Row

    private var bottomRow: some View {
        HStack(spacing: 0) {
            Button(action: onNextKeyboard) {
                Text("ABC")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 56, height: 50)
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
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Text("YapRun")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Brand.textPrimary(colorScheme).opacity(0.9))
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Brand.keySurface(colorScheme))
                .cornerRadius(6)
            }
            .padding(3)

            if canUndo {
                Button {
                    onUndoTap()
                    canUndo = false
                    canRedo = true
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 20))
                        .frame(width: 44, height: 50)
                        .background(Brand.keyCard(colorScheme))
                        .cornerRadius(6)
                }
                .foregroundColor(Brand.textPrimary(colorScheme).opacity(0.8))
                .padding(3)
            }

            if canRedo {
                Button {
                    onRedoTap()
                    canRedo = false
                    canUndo = true
                } label: {
                    Image(systemName: "arrow.uturn.forward.circle")
                        .font(.system(size: 20))
                        .frame(width: 44, height: 50)
                        .background(Brand.keyCard(colorScheme))
                        .cornerRadius(6)
                }
                .foregroundColor(Brand.textPrimary(colorScheme).opacity(0.8))
                .padding(3)
            }

            Button(action: onReturn) {
                Image(systemName: "return")
                    .font(.system(size: 18))
                    .frame(width: 56, height: 50)
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

    private var isTranscribing: Bool {
        checkmarkTapped || sessionState == "transcribing"
    }

    private var waveformView: some View {
        VStack(spacing: 0) {
            Spacer()

            // Top bar — always visible across listening/transcribing/done
            HStack {
                // Left: Cancel (hidden during transcribing/done)
                Button(action: onCancelTap) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Brand.textPrimary(colorScheme).opacity(0.8))
                        .frame(width: 44, height: 44)
                }
                .padding(.leading, 20)
                .opacity(sessionState == "done" || isTranscribing ? 0 : 1)
                .disabled(sessionState == "done" || isTranscribing)

                Spacer()

                // Center: Status indicator
                VStack(spacing: 2) {
                    if sessionState == "done" {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Brand.green)
                    } else if isTranscribing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .tint(Brand.accent(colorScheme))
                                .scaleEffect(0.75)
                            Text("Transcribing")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Brand.textPrimary(colorScheme))
                        }
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

                // Right: Checkmark / Spinner / Undo+Redo
                if sessionState == "done" {
                    HStack(spacing: 12) {
                        if canUndo {
                            Button {
                                onUndoTap()
                                canUndo = false
                                canRedo = true
                            } label: {
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Brand.textPrimary(colorScheme).opacity(0.8))
                            }
                        }
                        if canRedo {
                            Button {
                                onRedoTap()
                                canRedo = false
                                canUndo = true
                            } label: {
                                Image(systemName: "arrow.uturn.forward.circle")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Brand.textPrimary(colorScheme).opacity(0.8))
                            }
                        }
                    }
                    .padding(.trailing, 20)
                    .frame(width: 84, alignment: .trailing)
                } else if isTranscribing {
                    ProgressView()
                        .tint(Brand.accent(colorScheme))
                        .scaleEffect(0.85)
                        .frame(width: 44, height: 44)
                        .padding(.trailing, 20)
                } else {
                    Button {
                        checkmarkTapped = true
                        onStopTap()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Brand.accent(colorScheme))
                            .frame(width: 44, height: 44)
                    }
                    .padding(.trailing, 20)
                }
            }

            waveformBars
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 20)

            Spacer()
        }
        .frame(minHeight: 300)
    }

    // MARK: Waveform Bars

    private var waveformBars: some View {
        HStack(spacing: 3) {
            ForEach(0..<40, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(barGradient)
                    .frame(width: 4, height: barHeight(for: index))
                    .animation(.easeOut(duration: 0.08), value: audioLevel)
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 12
        let maxH: CGFloat = 200
        if sessionState == "transcribing" {
            let wave = CGFloat(sin(Double(index) * 0.5 + barPhase))
            return base + (maxH * 0.3) * (0.5 + 0.5 * wave)
        }
        if sessionState == "done" {
            return base + 30
        }
        let wave = CGFloat(sin(Double(index) * 0.45 + barPhase))
        let raw = CGFloat(min(max(audioLevel, 0), 1))
        // Boost low audio levels so bars are visually prominent
        let level = min(raw * 3.0 + 0.15, 1.0)
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
                .font(.system(size: 17))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Brand.keySurface(colorScheme))
                .cornerRadius(6)
        }
        .foregroundColor(Brand.textPrimary(colorScheme).opacity(0.9))
        .padding(3)
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
