//
//  DownloadNotifier.swift
//  RunAnywhere SDK
//
//  Local notifications for background model downloads, matching the Android
//  ongoing progress notification. One notification per model, updated in place.
//

import Foundation
import UserNotifications
import CRACommons

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
        let percent = Int(rac_download_progress_percent(Float(fraction), 0, 0))
        // Throttle to whole 5% steps so the delegate's per-chunk callbacks don't
        // flood the notification center.
        if let previous = lastPercent[modelID], abs(percent - previous) < 5, percent < 100 { return }
        lastPercent[modelID] = percent

        let content = UNMutableNotificationContent()
        content.title = "Downloading model"
        content.body = "\(percent)% complete"
        await post(identifier: identifier(modelID), content: content)
    }

    /// The bytes have all arrived and are being checksummed.
    ///
    /// A separate notification rather than leaving the progress one at 100%,
    /// because on a multi-gigabyte model the hash runs for long enough that
    /// "100% complete" sitting on the lock screen while nothing finishes reads
    /// as a stuck download. Clearing `lastPercent` also means the next real
    /// progress update — from a retry, say — is not throttled away as a
    /// near-duplicate of the last percentage seen.
    func notifyVerifying(modelID: String) async {
        lastPercent[modelID] = nil
        let content = UNMutableNotificationContent()
        content.title = "Downloading model"
        content.body = "Checking the downloaded files…"
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
