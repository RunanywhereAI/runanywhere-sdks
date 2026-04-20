// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Sentry telemetry adapter. Gated behind `canImport(Sentry)` so the SDK
// builds without the Sentry SPM dependency — host apps opt in via the
// `RunAnywhereSentry` product (or by linking Sentry themselves).
//
// When Sentry is available, wires `ra_telemetry_set_http_callback` to
// forward telemetry events through Sentry's queue, and installs a
// `ra_event_subscribe_all` listener that routes SDK error events into
// Sentry as captured exceptions / breadcrumbs.

import Foundation
import CRACommonsCore

#if canImport(Sentry)
import Sentry
#endif

public enum SentryAdapter {

    public struct Configuration: Sendable {
        public var dsn: String
        public var environment: String
        public var releaseName: String?
        public var sampleRate: Float
        public var enableCrashHandler: Bool

        public init(dsn: String,
                    environment: String = "production",
                    releaseName: String? = nil,
                    sampleRate: Float = 1.0,
                    enableCrashHandler: Bool = true) {
            self.dsn = dsn
            self.environment = environment
            self.releaseName = releaseName
            self.sampleRate = sampleRate
            self.enableCrashHandler = enableCrashHandler
        }
    }

    #if canImport(Sentry)

    /// Install the Sentry SDK + wire SDK event routing.
    public static func install(configuration: Configuration) {
        SentrySDK.start { options in
            options.dsn         = configuration.dsn
            options.environment = configuration.environment
            options.releaseName = configuration.releaseName
            options.sampleRate  = NSNumber(value: configuration.sampleRate)
            options.enableCrashHandler = configuration.enableCrashHandler
        }

        // Route error-category SDK events through Sentry as breadcrumbs.
        _ = ra_event_subscribe(
            ra_event_category_t(RA_EVENT_CATEGORY_ERROR),
            { event, _ in
                guard let evt = event?.pointee else { return }
                let name = evt.name.flatMap { String(cString: $0) } ?? "ra.error"
                let payload = evt.payload_json.flatMap { String(cString: $0) } ?? ""
                let crumb = Breadcrumb(level: .error, category: "runanywhere")
                crumb.message = name
                crumb.data = ["payload": payload]
                SentrySDK.addBreadcrumb(crumb)
            },
            nil)
    }

    /// Capture a Swift error explicitly. Useful from catch blocks.
    public static func capture(_ error: Error, extra: [String: Any] = [:]) {
        SentrySDK.capture(error: error) { scope in
            for (k, v) in extra { scope.setExtra(value: v, key: k) }
        }
    }

    public static func addBreadcrumb(category: String, message: String,
                                       level: SentryLevel = .info) {
        let crumb = Breadcrumb(level: level, category: category)
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
    }

    #else

    /// Sentry not linked — no-op fallback so app code compiles uniformly.
    public static func install(configuration: Configuration) {}
    public static func capture(_ error: Error, extra: [String: Any] = [:]) {}
    public static func addBreadcrumb(category: String, message: String, level: Int = 0) {}

    #endif
}
