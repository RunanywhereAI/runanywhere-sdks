//
//  RunAnywhere+BackgroundDownloads.swift
//  RunAnywhere SDK
//
//  Public controls for background model downloads. Both flags default to on for
//  parity with the Android foreground-service download experience.
//

import Foundation

public extension RunAnywhere {
    /// When enabled, eligible model downloads run on a background URLSession and
    /// continue while the app is suspended. Extraction/unknown-size models always
    /// use the foreground path regardless of this flag.
    static var backgroundDownloadsEnabled: Bool {
        get { BackgroundDownloadCoordinator.shared.isEnabled }
        set { BackgroundDownloadCoordinator.shared.isEnabled = newValue }
    }

    /// When enabled, downloads post a local progress notification that updates in
    /// place plus a terminal completion/failure notification.
    static var downloadNotificationsEnabled: Bool {
        get { BackgroundDownloadCoordinator.shared.notificationsEnabled }
        set { BackgroundDownloadCoordinator.shared.notificationsEnabled = newValue }
    }

    /// Forward `application(_:handleEventsForBackgroundURLSession:completionHandler:)`
    /// here so the SDK can finish restored background transfers and call the
    /// system completion handler once its session events drain.
    static func handleBackgroundURLSessionEvents(
        identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundDownloadCoordinator.sessionIdentifier else {
            completionHandler()
            return
        }
        BackgroundDownloadCoordinator.shared.registerBackgroundCompletionHandler(completionHandler)
    }
}
