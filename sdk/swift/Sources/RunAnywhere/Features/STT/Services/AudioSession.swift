// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation

#if canImport(AVFoundation)
import AVFoundation

/// Owns the shared AVAudioSession category for VoiceAgent, plus route-change
/// and interruption handling. Every VoiceSession shares a single instance.
@MainActor
public final class AudioSession {
    public static let shared = AudioSession()

    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver:  NSObjectProtocol?

    public private(set) var isActive: Bool = false

    public func activate() throws {
        #if os(iOS) || os(tvOS) || os(watchOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord,
                                mode: .voiceChat,
                                options: [.allowBluetooth,
                                          .allowBluetoothA2DP,
                                          .defaultToSpeaker])
        try session.setActive(true)
        installObservers()
        isActive = true
        #else
        isActive = true
        #endif
    }

    public func deactivate() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        try? AVAudioSession.sharedInstance().setActive(false,
            options: .notifyOthersOnDeactivation)
        #endif
        removeObservers()
        isActive = false
    }

    private func installObservers() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        let center = NotificationCenter.default
        interruptionObserver = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main, using: { _ in
                // TODO: notify the active VoiceSession to cancel playback.
            })
        routeChangeObserver = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main, using: { _ in
                // TODO: emit PipelineState change when headphones (un)plug.
            })
        #endif
    }

    private func removeObservers() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        if let io = interruptionObserver {
            NotificationCenter.default.removeObserver(io)
        }
        if let ro = routeChangeObserver {
            NotificationCenter.default.removeObserver(ro)
        }
        interruptionObserver = nil
        routeChangeObserver  = nil
        #endif
    }
}

#else  // !canImport(AVFoundation) — Linux test builds

@MainActor
public final class AudioSession {
    public static let shared = AudioSession()
    public private(set) var isActive: Bool = false
    public func activate()   throws { isActive = true }
    public func deactivate()        { isActive = false }
}

#endif
