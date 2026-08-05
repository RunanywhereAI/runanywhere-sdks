//
//  DownloadNotifier.swift
//  RunAnywhere SDK
//
//  Local notifications for background model downloads, matching the Android
//  ongoing progress notification. One notification per model, updated in place.
//

import Foundation
import UserNotifications

actor DownloadNotifier {
    static let shared = DownloadNotifier()

    private var authorizationRequested = false
    private var lastPercent: [String: Int] = [:]

    private init() {}

    private func identifier(_ modelID: String) -> String { "com.runanywhere.download.\(modelID)" }

    func requestAuthorizationIfNeeded() async {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    func notifyProgress(modelID: String, fraction: Double) async {
        let percent = max(0, min(100, Int(fraction * 100)))
        // Throttle to whole 5% steps so the delegate's per-chunk callbacks don't
        // flood the notification center.
        if let previous = lastPercent[modelID], abs(percent - previous) < 5, percent < 100 { return }
        lastPercent[modelID] = percent

        let content = UNMutableNotificationContent()
        content.title = "Downloading model"
        content.body = "\(percent)% complete"
        await post(identifier: identifier(modelID), content: content)
    }

    func notifyCompleted(modelID: String) async {
        lastPercent[modelID] = nil
        let content = UNMutableNotificationContent()
        content.title = "Model ready"
        content.body = "Download complete."
        content.sound = .default
        await post(identifier: identifier(modelID), content: content)
    }

    func notifyFailed(modelID: String, message: String) async {
        lastPercent[modelID] = nil
        let content = UNMutableNotificationContent()
        content.title = "Download failed"
        content.body = message
        content.sound = .default
        await post(identifier: identifier(modelID), content: content)
    }

    private func post(identifier: String, content: UNNotificationContent) async {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
