//
//  HandleStreamAdapter.swift
//  RunAnywhere
//
//  Swift simplification Phase 1 — see
//  gaps/gaps/simplification/swift-bridge-duplication.md §1 Pattern C.
//
//  Generic AsyncStream-based wrapper over a proto-byte streaming C ABI.
//  Replaces the duplicated fan-out machinery in `LLMStreamAdapter` and
//  `VoiceAgentStreamAdapter`: each adapter is identical except for
//  (1) the native handle type, (2) the proto Event type, and (3) the
//  C register/unregister symbols. This generic absorbs (1) and (2) via
//  type parameters and (3) via injected closures.
//
//  Semantics (matched to LLMStreamAdapter exactly):
//    * The first subscriber installs one C callback registration.
//    * Subsequent subscribers fan out from the same registration — all
//      share the single registered trampoline.
//    * On the last subscriber unsubscribing the registration is torn
//      down and the per-handle fan-out is removed from the static map.
//    * If the caller supplies `isTerminalEvent`, an event satisfying
//      the predicate finishes every continuation and tears down the
//      registration immediately (the LLM `isFinal` semantics). When the
//      predicate is omitted (the VoiceAgent case) events fan out
//      forever until consumers detach.
//
//  Concurrency:
//    * State is guarded by `OSAllocatedUnfairLock` (per CLAUDE.md
//      `NSLock` is forbidden).
//    * The `@convention(c)` trampoline is a free closure with no
//      captures; context is plumbed through `Unmanaged.passRetained`
//      / `.fromOpaque` / `.takeUnretainedValue` / `.release`.
//    * The generic class is `@unchecked Sendable`; safety is rooted
//      entirely in the lock.
//
//  Public API:
//      let adapter = HandleStreamAdapter<rac_handle_t, RALLMStreamEvent>(
//          handle: handle,
//          streamKey: "llm",
//          register: { h, cb, ud in rac_llm_set_stream_proto_callback(h, cb, ud) },
//          unregister: { h in _ = rac_llm_unset_stream_proto_callback(h) },
//          isTerminalEvent: { $0.isFinal }
//      )
//      for await event in adapter.stream() { ... }
//
//  Cancellation: standard `for-await break` cancels the AsyncStream,
//  which deregisters via `onTermination`.

import CRACommons
import Foundation
import os
import SwiftProtobuf

/// Generic AsyncStream wrapper for proto-byte streaming C ABIs that
/// follow the `(handle, callback, userData) -> rac_result_t` shape.
///
/// `Handle` must be `Hashable` so per-handle fan-out instances can be
/// shared across multiple `HandleStreamAdapter` constructions for the
/// same native handle. `Event` must be a SwiftProtobuf `Message` so
/// the trampoline can decode raw bytes via `Event(serializedBytes:)`.
public final class HandleStreamAdapter<Handle: Hashable, Event: Message>: @unchecked Sendable {

    // MARK: - C callback bridge

    /// `void (*)(uint8_t*, size_t, void*)` matching every proto-byte
    /// streaming callback in the commons C ABI.
    public typealias CCallback = @convention(c) (
        UnsafePointer<UInt8>?, Int, UnsafeMutableRawPointer?
    ) -> Void

    /// Closure that installs the trampoline against the native handle.
    public typealias Register = @Sendable (Handle, CCallback?, UnsafeMutableRawPointer?) -> rac_result_t

    /// Closure that removes the trampoline from the native handle.
    public typealias Unregister = @Sendable (Handle) -> Void

    /// Predicate that classifies an event as terminal. When supplied
    /// and a yielded event satisfies it, every continuation is
    /// finished and the C registration is torn down immediately.
    public typealias IsTerminalEvent = @Sendable (Event) -> Bool

    // MARK: - Per-handle fan-out

    private final class HandleFanOut: HandleStreamFanOutEntry {
        // Per CLAUDE.md: NSLock is forbidden — use OSAllocatedUnfairLock.
        private let handle: Handle
        private let storeKey: HandleStreamStoreKey
        private let register: Register
        private let unregister: Unregister
        private let isTerminalEvent: IsTerminalEvent?
        private let state = OSAllocatedUnfairLock<HandleFanOutState<Event>>(
            initialState: HandleFanOutState<Event>()
        )

        init(
            handle: Handle,
            storeKey: HandleStreamStoreKey,
            register: @escaping Register,
            unregister: @escaping Unregister,
            isTerminalEvent: IsTerminalEvent?
        ) {
            self.handle = handle
            self.storeKey = storeKey
            self.register = register
            self.unregister = unregister
            self.isTerminalEvent = isTerminalEvent
        }

        func attach(_ continuation: AsyncStream<Event>.Continuation) -> UUID? {
            // Install the trampoline outside the lock — the C
            // registration may invoke the callback synchronously on
            // some platforms, so we must not hold the lock across it.
            let alreadyInstalled = state.withLock { $0.installed }

            if !alreadyInstalled {
                if !install() { return nil }
            }

            let id = UUID()
            state.withLock { $0.continuations[id] = continuation }
            return id
        }

        func detach(_ id: UUID) {
            let shouldTearDown = state.withLock { lockedState -> Bool in
                lockedState.continuations.removeValue(forKey: id)
                return lockedState.continuations.isEmpty
            }

            if shouldTearDown {
                tearDown()
            }
        }

        private func install() -> Bool {
            let userPtr = Unmanaged.passRetained(self).toOpaque()

            // The trampoline must be a `@convention(c)` closure with no
            // generic-parameter captures (Swift compiler restriction).
            // We bridge to the protocol method `deliverBytes` on the
            // non-generic `HandleStreamFanOutEntry` protocol; dynamic
            // dispatch dispatches into the generic `HandleFanOut` body
            // where `Event(serializedBytes:)` is sound.
            let trampoline: CCallback = { bytesPtr, bytesLen, userData in
                guard let userData = userData else { return }
                let entry = Unmanaged<AnyObject>.fromOpaque(userData).takeUnretainedValue()
                guard let fanOut = entry as? HandleStreamFanOutEntry else { return }
                fanOut.deliverBytes(bytesPtr, bytesLen)
            }

            // Optimistic write — assume the registration will succeed.
            state.withLock {
                $0.userPtr = userPtr
                $0.installed = true
            }

            let result = register(handle, trampoline, userPtr)
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

        // MARK: HandleStreamFanOutEntry

        func deliverBytes(_ bytesPtr: UnsafePointer<UInt8>?, _ bytesLen: Int) {
            guard let bytesPtr = bytesPtr else { return }
            let data = Data(bytes: bytesPtr, count: bytesLen)
            guard let event = try? Event(serializedBytes: data) else {
                finishAll()
                return
            }
            broadcast(event)
        }

        private func broadcast(_ event: Event) {
            let isFinal = isTerminalEvent?(event) ?? false

            let snapshot: [AsyncStream<Event>.Continuation] = state.withLock { lockedState in
                let values = Array(lockedState.continuations.values)
                if isFinal {
                    lockedState.continuations.removeAll()
                }
                return values
            }

            for continuation in snapshot {
                continuation.yield(event)
                if isFinal {
                    continuation.finish()
                }
            }

            if isFinal {
                tearDown()
            }
        }

        private func finishAll() {
            let snapshot: [AsyncStream<Event>.Continuation] = state.withLock { lockedState in
                let values = Array(lockedState.continuations.values)
                lockedState.continuations.removeAll()
                return values
            }

            for continuation in snapshot {
                continuation.finish()
            }
            tearDown()
        }

        func tearDown() {
            let ptrToRelease: UnsafeMutableRawPointer? = state.withLock { lockedState in
                guard lockedState.installed else { return nil }
                unregister(handle)
                lockedState.installed = false
                let ptr = lockedState.userPtr
                lockedState.userPtr = nil
                return ptr
            }

            if let ptrToRelease {
                Unmanaged<HandleFanOut>.fromOpaque(ptrToRelease).release()
            }
            HandleStreamAdapter.removeFanOut(for: storeKey)
        }
    }

    // MARK: - Static fan-out registry

    // Global because Swift forbids generic stored statics. The single
    // swiftlint:disable:next avoid_any_object
    // `[StoreKey: AnyObject]` lock backs every instantiation of this
    // generic. `streamKey` partitions the dictionary so two
    // specialisations cannot collide even if their `Handle.hashValue`
    // happens to match.
    // swiftlint:disable:next avoid_any_object
    private static var fanOuts: OSAllocatedUnfairLock<[HandleStreamStoreKey: AnyObject]> {
        HandleStreamAdapterRegistry.shared.fanOuts
    }

    private static func fanOut(
        for handle: Handle,
        streamKey: String,
        register: @escaping Register,
        unregister: @escaping Unregister,
        isTerminalEvent: IsTerminalEvent?
    ) -> HandleFanOut {
        let key = HandleStreamStoreKey(streamKey: streamKey, handleHash: handle.hashValue)
        return fanOuts.withLock { dict in
            if let existing = dict[key] as? HandleFanOut {
                return existing
            }
            let fanOut = HandleFanOut(
                handle: handle,
                storeKey: key,
                register: register,
                unregister: unregister,
                isTerminalEvent: isTerminalEvent
            )
            dict[key] = fanOut
            return fanOut
        }
    }

    private static func removeFanOut(for key: HandleStreamStoreKey) {
        fanOuts.withLock { _ = $0.removeValue(forKey: key) }
    }

    // MARK: - Stored properties

    private let handle: Handle
    private let streamKey: String
    private let register: Register
    private let unregister: Unregister
    private let isTerminalEvent: IsTerminalEvent?

    // MARK: - Init

    /// Wrap an existing native handle as a fan-out event stream.
    ///
    /// - Parameters:
    ///   - handle:   The native handle the C registration targets.
    ///   - streamKey: Identifier that partitions the global fan-out
    ///     store by adapter kind. Two adapter instances that share the
    ///     same `Handle` type but call different `register` symbols
    ///     must use distinct `streamKey` values; otherwise their
    ///     fan-outs collide. Pass a stable string such as `"llm"` or
    ///     `"voice-agent"`.
    ///   - register: Closure that installs the trampoline; e.g.
    ///     `{ h, cb, ud in rac_llm_set_stream_proto_callback(h, cb, ud) }`.
    ///   - unregister: Closure that removes the trampoline; e.g.
    ///     `{ h in _ = rac_llm_unset_stream_proto_callback(h) }`.
    ///   - isTerminalEvent: Optional predicate that classifies an
    ///     event as terminal. When non-nil and an event satisfies it,
    ///     every continuation is finished and the C registration is
    ///     torn down. Omit to get pure fan-out semantics (events flow
    ///     until subscribers detach).
    public init(
        handle: Handle,
        streamKey: String,
        register: @escaping Register,
        unregister: @escaping Unregister,
        isTerminalEvent: IsTerminalEvent? = nil
    ) {
        self.handle = handle
        self.streamKey = streamKey
        self.register = register
        self.unregister = unregister
        self.isTerminalEvent = isTerminalEvent
    }

    // MARK: - Public API

    /// Start a new subscription. The returned stream emits one
    /// decoded `Event` per byte payload delivered by the C callback.
    ///
    /// Calling `stream()` twice attaches two collectors to the same
    /// per-handle native callback registration.
    public func stream() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let fanOut = Self.fanOut(
                for: handle,
                streamKey: streamKey,
                register: register,
                unregister: unregister,
                isTerminalEvent: isTerminalEvent
            )
            guard let id = fanOut.attach(continuation) else {
                continuation.finish()
                return
            }

            continuation.onTermination = { @Sendable _ in
                fanOut.detach(id)
            }
        }
    }

    /// Force-tear down the per-handle registration regardless of
    /// outstanding subscribers. Subscribers' streams will finish.
    /// Intended for use during component destruction; ordinary
    /// cancellation should rely on `for-await break`.
    public func tearDown() {
        let key = HandleStreamStoreKey(streamKey: streamKey, handleHash: handle.hashValue)
        let fanOut = Self.fanOuts.withLock { $0[key] as? HandleFanOut }
        fanOut?.tearDown()
    }
}

// MARK: - Non-generic supporting types

// swiftlint:disable avoid_any_object
/// Type-erased entry point invoked from the `@convention(c)`
/// trampoline. Concrete `HandleFanOut` instances conform; dispatching
/// through this protocol breaks the generic-parameter capture that
/// would otherwise prevent the trampoline from being expressible as a
/// C function pointer.
private protocol HandleStreamFanOutEntry: AnyObject {
    func deliverBytes(_ bytesPtr: UnsafePointer<UInt8>?, _ bytesLen: Int)
}
// swiftlint:enable avoid_any_object

/// Composite key partitioning the global fan-out store. The
/// `streamKey` distinguishes adapters that share the same `Handle`
/// type but address different C registration ABIs (e.g. a future
/// per-handle adapter that registers two unrelated streams against
/// the same `rac_handle_t`).
private struct HandleStreamStoreKey: Hashable, Sendable {
    // periphery:ignore
    let streamKey: String
    // periphery:ignore
    let handleHash: Int
}

/// Mutable state guarded by `HandleFanOut`'s `OSAllocatedUnfairLock`.
/// Lifted to file scope so the nested-type depth limit imposed by
/// SwiftLint's `nesting` rule is respected.
private struct HandleFanOutState<Event: Message> {
    var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]
    var userPtr: UnsafeMutableRawPointer?
    var installed: Bool = false
}

/// Holds the lock that backs every `HandleStreamAdapter` instantiation.
/// A single global is required because Swift forbids generic stored
/// statics. The `(streamKey, handleHash)` composite key keeps each
/// specialisation's entries disjoint inside the shared dictionary.
private final class HandleStreamAdapterRegistry: @unchecked Sendable {
    static let shared = HandleStreamAdapterRegistry()
    // swiftlint:disable:next avoid_any_object
    let fanOuts = OSAllocatedUnfairLock<[HandleStreamStoreKey: AnyObject]>(initialState: [:])

    private init() {}
}
