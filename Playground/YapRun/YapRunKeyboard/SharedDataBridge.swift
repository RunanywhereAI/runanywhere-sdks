//
//  SharedDataBridge.swift
//  YapRun + YapRunKeyboard
//
//  Shared between the main app and keyboard extension targets.
//  Provides:
//  - App Group UserDefaults for state sharing
//  - Darwin CFNotificationCenter helpers for instant IPC signalling
//  - In-memory caching to eliminate redundant UserDefaults IPC reads
//

import Foundation

// MARK: - Darwin Notification Center

private let _darwinCallback: CFNotificationCallback = { _, _, name, _, _ in
    guard let rawName = name?.rawValue as? String else { return }
    DarwinNotificationCenter.shared.fire(name: rawName)
}

final class DarwinNotificationCenter: @unchecked Sendable {
    static let shared = DarwinNotificationCenter()

    private var handlers: [String: [() -> Void]] = [:]
    private let queue = DispatchQueue(label: "com.runanywhere.yaprun.darwin.notifications")

    private init() {}

    func addObserver(name: String, callback: @escaping () -> Void) {
        queue.sync {
            let isFirstObserver = handlers[name] == nil
            handlers[name, default: []].append(callback)

            if isFirstObserver {
                CFNotificationCenterAddObserver(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    Unmanaged.passUnretained(self).toOpaque(),
                    _darwinCallback,
                    name as CFString,
                    nil,
                    .deliverImmediately
                )
            }
        }
    }

    func post(name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }

    func fire(name: String) {
        let cbs: [() -> Void] = queue.sync { handlers[name] ?? [] }
        DispatchQueue.main.async {
            cbs.forEach { $0() }
        }
    }
}

// MARK: - Shared Data Bridge

final class SharedDataBridge {
    static let shared = SharedDataBridge()

    let defaults: UserDefaults?

    // MARK: - Cached Values
    // These eliminate redundant UserDefaults IPC reads. The keyboard extension
    // reads these values frequently (audioLevel every 150ms, sessionState every 5s).
    // Caches are invalidated via Darwin notifications from the main app.
    private var _cachedSessionState: String
    private var _cachedAudioLevel: Float

    private init() {
        defaults = UserDefaults(suiteName: SharedConstants.appGroupID)
        _cachedSessionState = defaults?.string(forKey: SharedConstants.Keys.sessionState) ?? "idle"
        _cachedAudioLevel = defaults?.float(forKey: SharedConstants.Keys.audioLevel) ?? 0
        registerCacheObservers()
    }

    /// Register Darwin notification observers to invalidate caches when the main app writes.
    private func registerCacheObservers() {
        DarwinNotificationCenter.shared.addObserver(
            name: SharedConstants.DarwinNotifications.stateChanged
        ) { [weak self] in
            self?.refreshStateFromDefaults()
        }

        DarwinNotificationCenter.shared.addObserver(
            name: SharedConstants.DarwinNotifications.audioLevelChanged
        ) { [weak self] in
            self?.refreshAudioLevelFromDefaults()
        }
    }

    /// Refresh all cached values from UserDefaults.
    func refreshAllFromDefaults() {
        _cachedSessionState = defaults?.string(forKey: SharedConstants.Keys.sessionState) ?? "idle"
        _cachedAudioLevel = defaults?.float(forKey: SharedConstants.Keys.audioLevel) ?? 0
    }

    /// Refresh only session state from UserDefaults.
    private func refreshStateFromDefaults() {
        _cachedSessionState = defaults?.string(forKey: SharedConstants.Keys.sessionState) ?? "idle"
    }

    /// Refresh only audio level from UserDefaults.
    private func refreshAudioLevelFromDefaults() {
        _cachedAudioLevel = defaults?.float(forKey: SharedConstants.Keys.audioLevel) ?? 0
    }

    // MARK: - Session State

    var sessionState: String {
        get { _cachedSessionState }
        set {
            _cachedSessionState = newValue
            defaults?.set(newValue, forKey: SharedConstants.Keys.sessionState)
            DarwinNotificationCenter.shared.post(
                name: SharedConstants.DarwinNotifications.stateChanged
            )
        }
    }

    // MARK: - Transcription Result

    var transcribedText: String? {
        get {
            return defaults?.string(forKey: SharedConstants.Keys.transcribedText)
        }
        set {
            if let value = newValue {
                defaults?.set(value, forKey: SharedConstants.Keys.transcribedText)
            } else {
                defaults?.removeObject(forKey: SharedConstants.Keys.transcribedText)
            }
        }
    }

    // MARK: - Host App Bounce-Back

    var returnToAppScheme: String? {
        get { defaults?.string(forKey: SharedConstants.Keys.returnToAppScheme) }
        set { defaults?.set(newValue, forKey: SharedConstants.Keys.returnToAppScheme) }
    }

    // MARK: - Model Preference

    var preferredSTTModelId: String? {
        get { defaults?.string(forKey: SharedConstants.Keys.preferredSTTModelId) }
        set { defaults?.set(newValue, forKey: SharedConstants.Keys.preferredSTTModelId) }
    }

    // MARK: - Audio Level

    var audioLevel: Float {
        get { _cachedAudioLevel }
        set {
            _cachedAudioLevel = newValue
            defaults?.set(newValue, forKey: SharedConstants.Keys.audioLevel)
            // Post so the peer process (keyboard extension ↔ main app) refreshes
            // its own _cachedAudioLevel — otherwise readers see stale values.
            DarwinNotificationCenter.shared.post(
                name: SharedConstants.DarwinNotifications.audioLevelChanged
            )
        }
    }

    // MARK: - Heartbeat

    /// Heartbeat is written ~every second by FlowSessionManager without a state
    /// transition, so caching + Darwin-notification invalidation would require
    /// a notification per second. Instead, read through to UserDefaults every
    /// time so remote readers always see a fresh value.
    var lastHeartbeatTimestamp: Double {
        get { defaults?.double(forKey: SharedConstants.Keys.lastHeartbeat) ?? 0 }
        set { defaults?.set(newValue, forKey: SharedConstants.Keys.lastHeartbeat) }
    }

    // MARK: - Last Inserted Text

    var lastInsertedText: String? {
        get { defaults?.string(forKey: SharedConstants.Keys.lastInsertedText) }
        set {
            if let value = newValue {
                defaults?.set(value, forKey: SharedConstants.Keys.lastInsertedText)
            } else {
                defaults?.removeObject(forKey: SharedConstants.Keys.lastInsertedText)
            }
        }
    }

    // MARK: - Undo Text (saved for redo after undo)

    var undoText: String? {
        get { defaults?.string(forKey: SharedConstants.Keys.undoText) }
        set {
            if let value = newValue {
                defaults?.set(value, forKey: SharedConstants.Keys.undoText)
            } else {
                defaults?.removeObject(forKey: SharedConstants.Keys.undoText)
            }
        }
    }

    // MARK: - Cleanup

    func clearAfterInsertion() {
        defaults?.removeObject(forKey: SharedConstants.Keys.transcribedText)
        defaults?.removeObject(forKey: SharedConstants.Keys.lastInsertedText)
        defaults?.removeObject(forKey: SharedConstants.Keys.undoText)
        sessionState = "ready"
    }

    func clearSession() {
        defaults?.removeObject(forKey: SharedConstants.Keys.transcribedText)
        defaults?.removeObject(forKey: SharedConstants.Keys.lastInsertedText)
        defaults?.removeObject(forKey: SharedConstants.Keys.undoText)
        defaults?.set(Float(0), forKey: SharedConstants.Keys.audioLevel)
        defaults?.set(Double(0), forKey: SharedConstants.Keys.lastHeartbeat)
        _cachedAudioLevel = 0
        sessionState = "idle"
    }
}
