//
//  NotificationTool.swift
//  RunAnywhereAI
//
//  send_notification — posts a local user notification. The manager is
//  also the UNUserNotificationCenter delegate: without a delegate that
//  returns presentation options, notifications posted while the app is
//  frontmost (the common case during a chat) are silently swallowed.
//

import Foundation
import RunAnywhere
import UserNotifications

@MainActor
final class NotificationToolManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationToolManager()

    func requestAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        guard granted else {
            throw ToolPermissionError(
                "Notification permission was denied. Enable it in System Settings > Notifications."
            )
        }
        center.delegate = self
    }

    static func send(title: String, body: String, delaySeconds: Double) async -> [String: RAToolValue] {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return [
                "error": RAToolValue(
                    "Notifications are not authorized for this app — the user must enable them in System Settings"
                )
            ]
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Delay is clamped to 24h; a "notification" further out belongs in
        // Reminders or Calendar, which survive app termination.
        let clampedDelay = min(max(delaySeconds, 0), 86_400)
        let trigger: UNNotificationTrigger? = clampedDelay >= 1
            ? UNTimeIntervalNotificationTrigger(timeInterval: clampedDelay, repeats: false)
            : nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
        } catch {
            return ["error": RAToolValue(error.localizedDescription)]
        }

        return [
            "delivered": RAToolValue(true),
            "title": RAToolValue(title),
            "delay_seconds": RAToolValue(clampedDelay)
        ]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

enum NotificationTool {
    static var definition: RAToolDefinition {
        RAToolDefinition(
            name: "send_notification",
            description: """
                Shows a system notification banner on this device, immediately or after a \
                delay of up to 24 hours. Use when the user asks to be notified, pinged, or \
                alerted ("notify me in 20 minutes", "send me a notification when done"). \
                The notification only fires while this app is running — for anything \
                further out or that must survive quitting the app, use create_reminder \
                instead. Keep the title short and put detail in the body. Only say the \
                notification was sent or scheduled if the result has delivered = true; if \
                the result has "error", it was not delivered.
                """,
            parameters: [
                ToolParameter(
                    name: "title",
                    type: .string,
                    description: "Short headline shown in the notification banner."
                ),
                ToolParameter(
                    name: "body",
                    type: .string,
                    description: "Message text shown under the title."
                ),
                ToolParameter(
                    name: "delay_seconds",
                    type: .number,
                    description: """
                        Seconds to wait before showing the notification (e.g. 1200 for "in \
                        20 minutes"). Omit or pass 0 to show it immediately. Maximum 86400 \
                        (24 hours).
                        """,
                    required: false
                )
            ],
            category: "Notifications"
        )
    }

    static var executor: ToolExecutor {
        { args in
            guard let title = args["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                return ["error": RAToolValue("Missing required \"title\" argument")]
            }
            let body = args["body"]?.string ?? ""
            let delay = args["delay_seconds"]?.number ?? 0
            return await NotificationToolManager.send(title: title, body: body, delaySeconds: delay)
        }
    }
}
