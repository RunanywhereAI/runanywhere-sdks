//
//  SharedDataBridge.swift
//  YapRun + YapRunKeyboard
//
//  Shared between the main app and keyboard extension targets.
//  Provides:
//  - App Group UserDefaults for state sharing
//  - Darwin CFNotificationCenter helpers for instant IPC signalling
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

    private init() {
        defaults = UserDefaults(suiteName: SharedConstants.appGroupID)
    }

    // MARK: - Session State

    var sessionState: String {
        get {
            defaults?.synchronize()
            return defaults?.string(forKey: SharedConstants.Keys.sessionState) ?? "idle"
        }
        set {
            defaults?.set(newValue, forKey: SharedConstants.Keys.sessionState)
            defaults?.synchronize()
        }
    }

    // MARK: - Transcription Result

    var transcribedText: String? {
        get {
            defaults?.synchronize()
            return defaults?.string(forKey: SharedConstants.Keys.transcribedText)
        }
        set {
            if let value = newValue {
                defaults?.set(value, forKey: SharedConstants.Keys.transcribedText)
            } else {
                defaults?.removeObject(forKey: SharedConstants.Keys.transcribedText)
            }
            defaults?.synchronize()
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
        get { defaults?.float(forKey: SharedConstants.Keys.audioLevel) ?? 0 }
        set { defaults?.set(newValue, forKey: SharedConstants.Keys.audioLevel) }
    }

    // MARK: - Heartbeat

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
        sessionState = "idle"
    }
}
