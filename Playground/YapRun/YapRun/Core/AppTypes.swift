//
//  AppTypes.swift
//  YapRun
//
//  Shared types used across iOS and macOS.
//

import SwiftUI

// MARK: - Dictation Phase

enum DictationPhase: Equatable {
    case idle
    case recording
    case transcribing
    case inserting
    case done(String)
    case error(String)
}

// MARK: - Dictation Entry

struct DictationEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let date: Date

    init(id: UUID = UUID(), text: String, date: Date = Date()) {
        self.id = id
        self.text = text
        self.date = date
    }
}

// MARK: - Mic Permission State

enum MicPermissionState: String {
    case unknown, granted, denied

    var icon: String {
        switch self {
        case .unknown: "mic.fill"
        case .granted: "checkmark.circle.fill"
        case .denied:  "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .unknown: .orange
        case .granted: AppColors.primaryGreen
        case .denied:  AppColors.primaryRed
        }
    }

    var label: String {
        switch self {
        case .unknown: "Not determined"
        case .granted: "Granted"
        case .denied:  "Denied — open Settings to allow"
        }
    }
}

// MARK: - Hub Section (macOS sidebar)

enum HubSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case playground = "Playground"
    case notepad = "Notepad"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home:       "house"
        case .playground: "waveform"
        case .notepad:    "note.text"
        case .settings:   "gear"
        }
    }
}
