//
//  RunAnywhere+SDKEvents.swift
//  RunAnywhere SDK
//
//  Deprecated imperative SDK-event plumbing. The v3 surface is
//  `RunAnywhere.events` (folded `SdkEvent` stream) with `RunAnywhere.eventBus`
//  as the raw-proto escape hatch.
//

import CRACommons

public extension RunAnywhere {

    @discardableResult
    @available(*, deprecated, renamed: "events")
    static func subscribeSDKEvents(
        _ handler: @escaping @Sendable (RASDKEvent) -> Void
    ) -> UInt64 {
        CppBridge.Events.subscribeSDKEvents(handler)
    }

    @available(*, deprecated, renamed: "events")
    static func unsubscribeSDKEvents(_ subscriptionId: UInt64) {
        CppBridge.Events.unsubscribeSDKEvents(subscriptionId)
    }

    @discardableResult
    @available(*, deprecated, renamed: "eventBus")
    static func publishSDKEvent(_ event: RASDKEvent) -> Bool {
        CppBridge.Events.publishSDKEvent(event)
    }

    @available(*, deprecated, renamed: "events")
    static func pollSDKEvent() -> RASDKEvent? {
        CppBridge.Events.pollSDKEvent()
    }

    @discardableResult
    @available(*, deprecated, renamed: "eventBus")
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
