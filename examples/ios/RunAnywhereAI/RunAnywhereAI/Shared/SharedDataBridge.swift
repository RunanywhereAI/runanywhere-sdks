//
//  SharedDataBridge.swift
//  RunAnywhereAI + RunAnywhereKeyboard
//
//  Shared between the main app and keyboard extension targets.
//  Provides:
//  - App Group UserDefaults for state sharing
//  - Darwin CFNotificationCenter helpers for instant IPC signalling
//

import Foundation

// MARK: - Darwin Notification Center
// Uses a module-level non-capturing C callback and a singleton store
// to work around the restriction that Swift closures cannot be C function pointers.

private let _darwinCallback: CFNotificationCallback = { _, _, name, _, _ in
    guard let rawName = name?.rawValue as? String else { return }
    DarwinNotificationCenter.shared.fire(name: rawName)
}

final class DarwinNotificationCenter: @unchecked Sendable {
    static let shared = DarwinNotificationCenter()

    private var handlers: [String: [() -> Void]] = [:]
    // Serial queue replaces NSLock — Swift 6 compatible, avoids priority inversion
    private let queue = DispatchQueue(label: "com.runanywhere.darwin.notifications")

    private init() {}

    /// Register a callback for a Darwin notification name.
    /// Safe to call multiple times for the same name.
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

    /// Post a Darwin notification to all processes observing this name.
    func post(name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }

    /// Called by the C callback — dispatches registered handlers on main queue.
    func fire(name: String) {
        let cbs: [() -> Void] = queue.sync { handlers[name] ?? [] }
        DispatchQueue.main.async {
            cbs.forEach { $0() }
        }
    }
}

// MARK: - Shared Data Bridge

/// Facade over App Group UserDefaults for all cross-process state.
/// Used identically in both the main app and keyboard extension.
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

    // MARK: - Cleanup

    /// Clear all transient session data. Called after text is inserted.
    func clearSession() {
        defaults?.removeObject(forKey: SharedConstants.Keys.transcribedText)
        sessionState = "idle"
    }
}
