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
        private let handle: rac_voice_agent_handle_t
        private let key: UInt
        private let lock = NSLock()
        private var continuations: [UUID: AsyncStream<RAVoiceEvent>.Continuation] = [:]
        private var userPtr: UnsafeMutableRawPointer?
        private var installed = false

        init(handle: rac_voice_agent_handle_t, key: UInt) {
            self.handle = handle
            self.key = key
        }

        func attach(_ continuation: AsyncStream<RAVoiceEvent>.Continuation) -> UUID? {
            lock.lock()
            defer { lock.unlock() }

            if !installed && !installLocked() {
                return nil
            }

            let id = UUID()
            continuations[id] = continuation
            return id
        }

        func detach(_ id: UUID) {
            lock.lock()
            continuations.removeValue(forKey: id)
            let shouldTearDown = continuations.isEmpty
            lock.unlock()

            if shouldTearDown {
                tearDown()
            }
        }

        private func installLocked() -> Bool {
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

            let result = rac_voice_agent_set_proto_callback(handle, trampoline, userPtr)
            if result != RAC_SUCCESS {
                Unmanaged<HandleFanOut>.fromOpaque(userPtr).release()
                return false
            }

            self.userPtr = userPtr
            installed = true
            return true
        }

        private func broadcast(_ event: RAVoiceEvent) {
            lock.lock()
            let snapshot = Array(continuations.values)
            lock.unlock()

            for continuation in snapshot {
                continuation.yield(event)
            }
        }

        private func finishAll() {
            lock.lock()
            let snapshot = Array(continuations.values)
            continuations.removeAll()
            lock.unlock()

            for continuation in snapshot {
                continuation.finish()
            }
            tearDown()
        }

        private func tearDown() {
            var ptrToRelease: UnsafeMutableRawPointer?

            lock.lock()
            if installed {
                rac_voice_agent_set_proto_callback(handle, nil, nil)
                installed = false
                ptrToRelease = userPtr
                userPtr = nil
            }
            lock.unlock()

            if let ptrToRelease = ptrToRelease {
                Unmanaged<HandleFanOut>.fromOpaque(ptrToRelease).release()
            }
            VoiceAgentStreamAdapter.removeFanOut(for: key)
        }
    }

    private let handle: rac_voice_agent_handle_t

    private static let fanOutLock = NSLock()
    private static var fanOuts: [UInt: HandleFanOut] = [:]

    private static func fanOut(for handle: rac_voice_agent_handle_t) -> HandleFanOut {
        let key = UInt(bitPattern: handle)
        fanOutLock.lock()
        defer { fanOutLock.unlock() }
        if let existing = fanOuts[key] {
            return existing
        }
        let fanOut = HandleFanOut(handle: handle, key: key)
        fanOuts[key] = fanOut
        return fanOut
    }

    private static func removeFanOut(for key: UInt) {
        fanOutLock.lock()
        fanOuts.removeValue(forKey: key)
        fanOutLock.unlock()
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
