//
//  VoiceAgentStreamAdapter.swift
//  RunAnywhere
//
//  GAP 09 Phase 16 — see v2_gap_specs/GAP_09_STREAMING_CONSISTENCY.md.
//
//  Wraps `rac_voice_agent_set_proto_callback` (declared in
//  `rac_voice_event_abi.h`, GAP 09 Phase 15) as an `AsyncStream<RAVoiceEvent>`.
//  RAVoiceEvent is the codegen'd type from `idl/voice_events.proto` via
//  swift-protobuf (GAP 01).
//
//  Public API:
//      try await RunAnywhere.initializeVoiceAgentWithLoadedModels()
//      let handle = try await CppBridge.VoiceAgent.shared.getHandle()
//      let adapter = VoiceAgentStreamAdapter(handle: handle)
//      for await event in adapter.stream() { handle(event) }
//
//  Cancellation: standard `for-await break` cancels the underlying
//  AsyncStream which deregisters the C callback via `onTermination`.

import CRACommons
import Foundation
import SwiftProtobuf
import os

/// AsyncStream-based wrapper over the GAP 09 proto-byte voice agent ABI.
///
/// Multiple concurrent `stream()` collectors for the same native handle
/// share one C callback registration and fan out decoded proto events.
public final class VoiceAgentStreamAdapter {

    // MARK: - C callback bridge

    /// `void (*)(uint8_t*, size_t, void*)` matching
    /// `rac_voice_agent_proto_event_callback_fn`.
    private typealias CCallback = @convention(c) (
        UnsafePointer<UInt8>?, Int, UnsafeMutableRawPointer?
    ) -> Void

    private final class HandleFanOut {
        // Per CLAUDE.md: NSLock is forbidden — use OSAllocatedUnfairLock.
        private struct FanOutState {
            var continuations: [UUID: AsyncStream<RAVoiceEvent>.Continuation] = [:]
            var userPtr: UnsafeMutableRawPointer?
            var installed: Bool = false
        }

        private let handle: rac_voice_agent_handle_t
        private let key: UInt
        private let state = OSAllocatedUnfairLock<FanOutState>(initialState: FanOutState())

        init(handle: rac_voice_agent_handle_t, key: UInt) {
            self.handle = handle
            self.key = key
        }

        func attach(_ continuation: AsyncStream<RAVoiceEvent>.Continuation) -> UUID? {
            let alreadyInstalled = state.withLock { $0.installed }
            if !alreadyInstalled {
                if !install() { return nil }
            }

            let id = UUID()
            state.withLock { $0.continuations[id] = continuation }
            return id
        }

        func detach(_ id: UUID) {
            let shouldTearDown = state.withLock { s -> Bool in
                s.continuations.removeValue(forKey: id)
                return s.continuations.isEmpty
            }

            if shouldTearDown {
                tearDown()
            }
        }

        private func install() -> Bool {
            let userPtr = Unmanaged.passRetained(self).toOpaque()
            let trampoline: CCallback = { bytesPtr, bytesLen, userData in
                guard let bytesPtr = bytesPtr,
                      let userData = userData else { return }

                let fanOut = Unmanaged<HandleFanOut>.fromOpaque(userData).takeUnretainedValue()
                let data = Data(bytes: bytesPtr, count: bytesLen)
                guard let event = try? RAVoiceEvent(serializedBytes: data) else {
                    fanOut.finishAll()
                    return
                }
                fanOut.broadcast(event)
            }

            state.withLock {
                $0.userPtr = userPtr
                $0.installed = true
            }

            let result = rac_voice_agent_set_proto_callback(handle, trampoline, userPtr)
            if result != RAC_SUCCESS {
                state.withLock {
                    $0.userPtr = nil
                    $0.installed = false
                }
                Unmanaged<HandleFanOut>.fromOpaque(userPtr).release()
                return false
            }
            return true
        }

        private func broadcast(_ event: RAVoiceEvent) {
            let snapshot: [AsyncStream<RAVoiceEvent>.Continuation] =
                state.withLock { Array($0.continuations.values) }

            for continuation in snapshot {
                continuation.yield(event)
            }
        }

        private func finishAll() {
            let snapshot: [AsyncStream<RAVoiceEvent>.Continuation] = state.withLock { s in
                let values = Array(s.continuations.values)
                s.continuations.removeAll()
                return values
            }

            for continuation in snapshot {
                continuation.finish()
            }
            tearDown()
        }

        private func tearDown() {
            let ptrToRelease: UnsafeMutableRawPointer? = state.withLock { s in
                guard s.installed else { return nil }
                rac_voice_agent_set_proto_callback(handle, nil, nil)
                s.installed = false
                let ptr = s.userPtr
                s.userPtr = nil
                return ptr
            }

            if let ptrToRelease {
                Unmanaged<HandleFanOut>.fromOpaque(ptrToRelease).release()
            }
            VoiceAgentStreamAdapter.removeFanOut(for: key)
        }
    }

    private let handle: rac_voice_agent_handle_t

    private static let fanOuts = OSAllocatedUnfairLock<[UInt: HandleFanOut]>(initialState: [:])

    private static func fanOut(for handle: rac_voice_agent_handle_t) -> HandleFanOut {
        let key = UInt(bitPattern: handle)
        return fanOuts.withLock { dict in
            if let existing = dict[key] {
                return existing
            }
            let fanOut = HandleFanOut(handle: handle, key: key)
            dict[key] = fanOut
            return fanOut
        }
    }

    private static func removeFanOut(for key: UInt) {
        fanOuts.withLock { _ = $0.removeValue(forKey: key) }
    }

    // MARK: - Init

    /// Wrap an existing voice agent handle as an event stream.
    public init(handle: rac_voice_agent_handle_t) {
        self.handle = handle
    }

    // MARK: - Public API

    /// Start a new subscription. The returned stream emits one
    /// `RAVoiceEvent` per agent event until cancelled or the agent ends.
    ///
    /// Calling `stream()` twice attaches two collectors to the same
    /// per-handle native callback registration.
    public func stream() -> AsyncStream<RAVoiceEvent> {
        AsyncStream { continuation in
            let fanOut = Self.fanOut(for: handle)
            guard let id = fanOut.attach(continuation) else {
                continuation.finish()
                return
            }

            continuation.onTermination = { @Sendable _ in
                fanOut.detach(id)
            }
        }
    }
}
