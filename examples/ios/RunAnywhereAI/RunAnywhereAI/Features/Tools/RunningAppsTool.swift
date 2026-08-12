//
//  RunningAppsTool.swift
//  RunAnywhereAI
//
//  list_running_apps — the user-visible applications currently running on
//  this Mac. macOS only: iOS does not expose other processes to apps.
//

#if os(macOS)
import AppKit
import Foundation
import RunAnywhere

enum RunningAppsTool {
    static var definition: RAToolDefinition {
        RAToolDefinition(
            name: "list_running_apps",
            description: """
                Lists the applications currently running on this Mac (the ones that appear \
                in the Dock/app switcher — not background daemons or helper processes). \
                Use when the user asks what apps are open or whether a specific app is \
                running. Mention only apps that literally appear in this tool's result; \
                an app missing from the list is not running as a regular application. This \
                tool cannot launch, quit, or interact with apps — it only reports names.
                """,
            parameters: [],
            category: "System"
        )
    }

    static var executor: ToolExecutor {
        { _ in
            let names = await MainActor.run {
                NSWorkspace.shared.runningApplications
                    .filter { $0.activationPolicy == .regular }
                    .compactMap(\.localizedName)
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            }
            return [
                "app_count": RAToolValue(names.count),
                "apps": RAToolValue(names.joined(separator: "; "))
            ]
        }
    }
}
#endif
