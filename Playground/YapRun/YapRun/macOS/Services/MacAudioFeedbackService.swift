#if os(macOS)
//
//  MacAudioFeedbackService.swift
//  YapRun
//
//  Plays audio feedback sounds on dictation start/stop.
//

import AppKit
import SwiftUI

@MainActor
final class MacAudioFeedbackService {
    static let shared = MacAudioFeedbackService()

    @AppStorage("soundEffects") private var soundEffectsEnabled = true

    private init() {}

    func playStartSound() {
        guard soundEffectsEnabled else { return }
        NSSound.beep()
    }

    func playStopSound() {
        guard soundEffectsEnabled else { return }
        // Placeholder — replace with custom sound file
    }
}

#endif
