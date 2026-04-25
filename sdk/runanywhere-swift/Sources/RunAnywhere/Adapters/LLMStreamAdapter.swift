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
        private let handle: rac_handle_t
        private let key: UInt
        private let lock = NSLock()
        private var continuations: [UUID: AsyncStream<RALLMStreamEvent>.Continuation] = [:]
        private var userPtr: UnsafeMutableRawPointer?
        private var installed = false

        init(handle: rac_handle_t, key: UInt) {
            self.handle = handle
            self.key = key
        }

        func attach(_ continuation: AsyncStream<RALLMStreamEvent>.Continuation) -> UUID? {
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
                guard let event = try? RALLMStreamEvent(serializedBytes: data) else {
                    fanOut.finishAll()
                    return
                }
                fanOut.broadcast(event)
            }

            let result = rac_llm_set_stream_proto_callback(handle, trampoline, userPtr)
            if result != RAC_SUCCESS {
                Unmanaged<HandleFanOut>.fromOpaque(userPtr).release()
                return false
            }

            self.userPtr = userPtr
            installed = true
            return true
        }

        private func broadcast(_ event: RALLMStreamEvent) {
            lock.lock()
            let snapshot = Array(continuations.values)
            if event.isFinal {
                continuations.removeAll()
            }
            lock.unlock()

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
                _ = rac_llm_unset_stream_proto_callback(handle)
                installed = false
                ptrToRelease = userPtr
                userPtr = nil
            }
            lock.unlock()

            if let ptrToRelease = ptrToRelease {
                Unmanaged<HandleFanOut>.fromOpaque(ptrToRelease).release()
            }
            LLMStreamAdapter.removeFanOut(for: key)
        }
    }

    private let handle: rac_handle_t

    private static let fanOutLock = NSLock()
    private static var fanOuts: [UInt: HandleFanOut] = [:]

    private static func fanOut(for handle: rac_handle_t) -> HandleFanOut {
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
