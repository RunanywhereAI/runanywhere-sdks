//
//  CppBridge+SDKEvents.swift
//  RunAnywhere SDK
//
//  Canonical SDKEvent proto-byte stream bridge.
//

import CRACommons
import Foundation
import os

private enum SDKEventProtoABI {
    typealias EventCallback = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias Subscribe = @convention(c) (EventCallback?, UnsafeMutableRawPointer?) -> UInt64
    typealias Unsubscribe = @convention(c) (UInt64) -> Void
    typealias Publish = @convention(c) (UnsafePointer<UInt8>?, Int) -> rac_result_t
    typealias Poll = @convention(c) (UnsafeMutablePointer<rac_proto_buffer_t>?) -> rac_result_t
    typealias PublishFailure = @convention(c) (
        rac_result_t,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?,
        rac_bool_t
    ) -> rac_result_t
    typealias ClearQueue = @convention(c) () -> Void

    static let subscribe = NativeProtoABI.load("rac_sdk_event_subscribe", as: Subscribe.self)
    static let unsubscribe = NativeProtoABI.load("rac_sdk_event_unsubscribe", as: Unsubscribe.self)
    static let publish = NativeProtoABI.load("rac_sdk_event_publish_proto", as: Publish.self)
    static let poll = NativeProtoABI.load("rac_sdk_event_poll", as: Poll.self)
    static let publishFailure = NativeProtoABI.load(
        "rac_sdk_event_publish_failure",
        as: PublishFailure.self
    )
    static let clearQueue = NativeProtoABI.load("rac_sdk_event_clear_queue", as: ClearQueue.self)
}

private final class SDKEventSubscriptionBox {
    let handler: (RASDKEvent) -> Void

    init(handler: @escaping (RASDKEvent) -> Void) {
        self.handler = handler
    }
}

private let sdkEventSubscriptionPointers = OSAllocatedUnfairLock<[UInt64: UInt]>(initialState: [:])

private func sdkEventProtoCallback(
    protoBytes: UnsafePointer<UInt8>?,
    protoSize: Int,
    userData: UnsafeMutableRawPointer?
) {
    guard let protoBytes, protoSize > 0, let userData else { return }
    let box = Unmanaged<SDKEventSubscriptionBox>.fromOpaque(userData).takeUnretainedValue()
    if let event = try? RASDKEvent(serializedBytes: Data(bytes: protoBytes, count: protoSize)) {
        box.handler(event)
    }
}

extension CppBridge.Events {
    @discardableResult
    public static func subscribeSDKEvents(_ handler: @escaping (RASDKEvent) -> Void) -> UInt64 {
        guard let subscribe = SDKEventProtoABI.subscribe else { return 0 }

        let retained = Unmanaged.passRetained(SDKEventSubscriptionBox(handler: handler))
        let opaque = retained.toOpaque()
        let subscriptionId = subscribe(sdkEventProtoCallback, opaque)
        guard subscriptionId != 0 else {
            retained.release()
            return 0
        }
        sdkEventSubscriptionPointers.withLock {
            $0[subscriptionId] = UInt(bitPattern: opaque)
        }
        return subscriptionId
    }

    public static func unsubscribeSDKEvents(_ subscriptionId: UInt64) {
        SDKEventProtoABI.unsubscribe?(subscriptionId)

        let opaqueValue = sdkEventSubscriptionPointers.withLock { pointers in
            pointers.removeValue(forKey: subscriptionId)
        }
        if let opaqueValue {
            let opaque = UnsafeMutableRawPointer(bitPattern: opaqueValue)!
            Unmanaged<SDKEventSubscriptionBox>.fromOpaque(opaque).release()
        }
    }

    @discardableResult
    public static func publishSDKEvent(_ event: RASDKEvent) -> Bool {
        guard let publish = SDKEventProtoABI.publish,
              let data = try? event.serializedData() else {
            return false
        }
        let status = data.withUnsafeBytes { rawBuffer -> rac_result_t in
            publish(rawBuffer.bindMemory(to: UInt8.self).baseAddress, rawBuffer.count)
        }
        return status == RAC_SUCCESS
    }

    public static func pollSDKEvent() -> RASDKEvent? {
        guard let poll = SDKEventProtoABI.poll, NativeProtoABI.canReceiveProtoBuffer else {
            return nil
        }

        var outBuffer = rac_proto_buffer_t()
        defer { NativeProtoABI.free(&outBuffer) }
        guard poll(&outBuffer) == RAC_SUCCESS else {
            return nil
        }
        return try? NativeProtoABI.decode(RASDKEvent.self, from: outBuffer)
    }

    @discardableResult
    public static func publishSDKFailure(
        errorCode: rac_result_t,
        message: String,
        component: String,
        operation: String,
        recoverable: Bool
    ) -> Bool {
        guard let publishFailure = SDKEventProtoABI.publishFailure else {
            return false
        }

        let status = message.withCString { messagePtr in
            component.withCString { componentPtr in
                operation.withCString { operationPtr in
                    publishFailure(
                        errorCode,
                        messagePtr,
                        componentPtr,
                        operationPtr,
                        recoverable ? RAC_TRUE : RAC_FALSE
                    )
                }
            }
        }
        return status == RAC_SUCCESS
    }

    public static func clearSDKEventQueue() {
        SDKEventProtoABI.clearQueue?()
    }
}
