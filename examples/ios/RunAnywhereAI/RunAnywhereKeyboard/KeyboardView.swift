//
//  KeyboardView.swift
//  RunAnywhereKeyboard
//
//  SwiftUI keyboard UI.
//  Shows a "Dictate" button that triggers the Flow Session in the main app,
//  plus standard utility keys (space, return, delete, globe/switch keyboard).
//

import SwiftUI
import Combine

struct KeyboardView: View {
    let onDictate: () -> Void
    let onNextKeyboard: () -> Void
    let onSpace: () -> Void
    let onReturn: () -> Void
    let onDelete: () -> Void

    @State private var sessionState: String = "idle"

    // Poll state whenever the view appears / becomes visible
    private let stateTimer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 6) {
            if sessionState != "idle" {
                statusBanner
            }
            buttonsRow
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
        .onAppear { refreshState() }
        .onReceive(stateTimer) { _ in refreshState() }
    }

    // MARK: - Status Banner

    @ViewBuilder
    private var statusBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.75)
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .transition(.opacity)
    }

    private var statusText: String {
        switch sessionState {
        case "recording":    return "Recording… speak now"
        case "transcribing": return "Transcribing…"
        case "done":         return "Done — text inserted"
        default:             return ""
        }
    }

    // MARK: - Buttons Row

    private var buttonsRow: some View {
        HStack(spacing: 6) {
            dictateButton
            Spacer()
            keyButton(label: "space", action: onSpace)
            iconButton(systemImage: "return", action: onReturn)
            iconButton(systemImage: "delete.left", action: onDelete)
            iconButton(systemImage: "globe", action: onNextKeyboard)
        }
    }

    private var dictateButton: some View {
        Button(action: {
            onDictate()
            refreshState()
        }) {
            HStack(spacing: 6) {
                Image(systemName: sessionState == "recording" ? "stop.circle.fill" : "mic.fill")
                Text(sessionState == "recording" ? "Recording…" : "Dictate")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(sessionState == "recording" ? Color.orange : Color.accentColor)
            .cornerRadius(8)
        }
    }

    private func keyButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14))
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color(.systemGray5))
                .cornerRadius(8)
        }
        .foregroundColor(.primary)
    }

    private func iconButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .padding(11)
                .background(Color(.systemGray5))
                .cornerRadius(8)
        }
        .foregroundColor(.primary)
    }

    // MARK: - State

    private func refreshState() {
        let newState = SharedDataBridge.shared.sessionState
        if newState != sessionState {
            withAnimation(.easeInOut(duration: 0.2)) {
                sessionState = newState
            }
        }
    }
}
