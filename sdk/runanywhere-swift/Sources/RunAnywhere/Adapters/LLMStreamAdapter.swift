//
//  LLMStreamAdapter.swift
//  RunAnywhere
//
//  v2 close-out Phase G-2 — see docs/v2_closeout_phase_g2_report.md.
//
//  Wraps `rac_llm_set_stream_proto_callback` (declared in
//  `rac_llm_stream.h`) as an `AsyncStream<RALLMStreamEvent>`.
//  RALLMStreamEvent is the codegen'd type from `idl/llm_service.proto`
//  via swift-protobuf (GAP 01).
//
//  This is the unified LLM streaming path — the per-SDK hand-rolled
//  AsyncThrowingStream<String, Error> shim in RunAnywhere+TextGeneration.swift
//  was DELETED in the same change; the public `generateStream` on
//  `RunAnywhere` now pulls from this adapter.
//
//  Public API:
//      let handle = try await CppBridge.LLM.shared.getHandle()
//      let adapter = LLMStreamAdapter(handle: handle)
//      for await event in adapter.stream() {
//          if event.isFinal { break }
//          print(event.token, terminator: "")
//      }
//
//  Cancellation: `break` out of the `for-await` loop deregisters the C
//  callback via `onTermination`.

import CRACommons
import Foundation
import SwiftProtobuf
import os

/// AsyncStream-based wrapper over the Phase G-2 proto-byte LLM stream ABI.
///
/// Multiple concurrent `stream()` collectors for the same native handle
/// share one C callback registration and fan out decoded proto events.
public final class LLMStreamAdapter {

    // MARK: - C callback bridge

    /// `void (*)(uint8_t*, size_t, void*)` matching
    /// `rac_llm_stream_proto_callback_fn`.
    private typealias CCallback = @convention(c) (
        UnsafePointer<UInt8>?, Int, UnsafeMutableRawPointer?
    ) -> Void

    private final class HandleFanOut {
        // Per CLAUDE.md: NSLock is forbidden — use OSAllocatedUnfairLock.
        private struct FanOutState {
            var continuations: [UUID: AsyncStream<RALLMStreamEvent>.Continuation] = [:]
            var userPtr: UnsafeMutableRawPointer?
            var installed: Bool = false
        }

        private let handle: rac_handle_t
        private let key: UInt
        private let state = OSAllocatedUnfairLock<FanOutState>(initialState: FanOutState())

        init(handle: rac_handle_t, key: UInt) {
            self.handle = handle
            self.key = key
        }

        func attach(_ continuation: AsyncStream<RALLMStreamEvent>.Continuation) -> UUID? {
            // We must install the trampoline outside the lock because
            // installLocked invokes a C registration that might call back
            // synchronously on some platforms.
            var didInstall = true
            state.withLock { s in
                if !s.installed { didInstall = false }
            }

            if !didInstall {
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
            // Reserve the userPtr/installed flag under lock first, then call
            // the C ABI. If install fails we have to revert.
            let userPtr = Unmanaged.passRetained(self).toOpaque()
            let trampoline: CCallback = { bytesPtr, bytesLen, userData in
                guard let bytesPtr = bytesPtr,
                      let userData = userData else { return }

                let fanOut = Unmanaged<HandleFanOut>.fromOpaque(userData).takeUnretainedValue()
                let data = Data(bytes: bytesPtr, count: bytesLen)
                guard let event = try? RALLMStreamEvent(serializedBytes: data) else {
                    fanOut.finishAll()
                    return
                }
                fanOut.broadcast(event)
            }

            // Optimistic write — assume the registration will succeed.
            state.withLock {
                $0.userPtr = userPtr
                $0.installed = true
            }

            let result = rac_llm_set_stream_proto_callback(handle, trampoline, userPtr)
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

        private func broadcast(_ event: RALLMStreamEvent) {
            let snapshot: [AsyncStream<RALLMStreamEvent>.Continuation] = state.withLock { s in
                let values = Array(s.continuations.values)
                if event.isFinal {
                    s.continuations.removeAll()
                }
                return values
            }

            for continuation in snapshot {
                continuation.yield(event)
                if event.isFinal {
                    continuation.finish()
                }
            }

            if event.isFinal {
                tearDown()
            }
        }

        private func finishAll() {
            let snapshot: [AsyncStream<RALLMStreamEvent>.Continuation] = state.withLock { s in
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
                _ = rac_llm_unset_stream_proto_callback(handle)
                s.installed = false
                let ptr = s.userPtr
                s.userPtr = nil
                return ptr
            }

            if let ptrToRelease {
                Unmanaged<HandleFanOut>.fromOpaque(ptrToRelease).release()
            }
            LLMStreamAdapter.removeFanOut(for: key)
        }
    }

    private let handle: rac_handle_t

    private static let fanOuts = OSAllocatedUnfairLock<[UInt: HandleFanOut]>(initialState: [:])

    private static func fanOut(for handle: rac_handle_t) -> HandleFanOut {
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

    /// Wrap an existing LLM component handle as an event stream.
    public init(handle: rac_handle_t) {
        self.handle = handle
    }

    // MARK: - Public API

    /// Start a new subscription. The returned stream emits one
    /// `RALLMStreamEvent` per generated token plus a terminal event
    /// (`isFinal == true`).
    public func stream() -> AsyncStream<RALLMStreamEvent> {
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
