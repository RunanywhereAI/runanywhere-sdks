//
//  RunAnywhere+SDKEvents.swift
//  RunAnywhere SDK
//
//  Public proto-backed SDK event stream API.
//

import CRACommons

/// Imperative SDK-event surface kept for cross-SDK parity (this is Kotlin's
/// primary event API and the documented React Native surface). Swift consumers
/// should prefer the Combine publisher `RunAnywhere.events.events`, which wraps
/// this same native bridge; these top-level entry points are intentionally
/// retained rather than removed as dead code.
public extension RunAnywhere {
    @discardableResult
    static func subscribeSDKEvents(
        _ handler: @escaping @Sendable (RASDKEvent) -> Void
    ) -> UInt64 {
        CppBridge.Events.subscribeSDKEvents(handler)
    }

    static func unsubscribeSDKEvents(_ subscriptionId: UInt64) {
        CppBridge.Events.unsubscribeSDKEvents(subscriptionId)
    }

    @discardableResult
    static func publishSDKEvent(_ event: RASDKEvent) -> Bool {
        CppBridge.Events.publishSDKEvent(event)
    }

    static func pollSDKEvent() -> RASDKEvent? {
        CppBridge.Events.pollSDKEvent()
    }

    @discardableResult
    static func publishSDKFailure(
        errorCode: rac_result_t,
        message: String,
        component: String,
        operation: String,
        recoverable: Bool = false
    ) -> Bool {
        CppBridge.Events.publishSDKFailure(
            errorCode: errorCode,
            message: message,
            component: component,
            operation: operation,
            recoverable: recoverable
        )
    }
}
