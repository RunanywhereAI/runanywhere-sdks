//
//  HandleStreamAdapterTests.swift
//  RunAnywhere SDK
//
//  Adapter coverage for the `HandleStreamAdapter` fan-out machine. The four
//  scenarios in this suite exercise the lifecycle invariants documented in
//  `Sources/RunAnywhere/Adapters/HandleStreamAdapter.swift`:
//
//   1. AsyncStream cancellation drains down to a single C-side teardown.
//   2. Concurrent first-subscribers serialize on the `.installing` state so
//      `register(...)` is invoked exactly once.
//   3. `install()` failure rolls every pending continuation back, leaves
//      `unregister` untouched, and resets the state machine to
//      `.notInstalled` so a retry re-enters `install()`.
//   4. Two distinct native handles whose `hashValue` collides remain on
//      independent fan-out entries (AnyHashable-based keying).
//
//  These tests inject synthetic `register` / `unregister` closures rather
//  than touching the real C ABI, which lets the suite assert lifecycle
//  invariants without dlsym-resolving any `rac_*_set_stream_proto_callback`
//  symbol. The hash-collision test additionally captures the installed
//  trampoline so it can drive proto-byte payloads through each fan-out and
//  observe per-handle subscriber isolation.
//

import Foundation
import os
import SwiftProtobuf
import XCTest

@testable import RunAnywhere

final class HandleStreamAdapterTests: XCTestCase {

    // MARK: - Helper types

    /// Test-only handle whose UUID payload guarantees disjoint static-
    /// registry buckets across tests — each test instantiates its own
    /// `HandleFanOut` by virtue of carrying a fresh handle and stream key.
    private struct UniqueHandle: Hashable, Sendable {
        let id: UUID
    }

    /// Handle whose `hash(into:)` collapses to a constant so two distinct
    /// instances necessarily share `hashValue`. Used by the hash-collision
    /// isolation test to force `AnyHashable`-based equality (not raw
    /// `hashValue` comparison) to be the disambiguator inside the static
    /// fan-out registry.
    private struct CollidingHandle: Hashable, Sendable {
        let id: Int
        func hash(into hasher: inout Hasher) {
            hasher.combine(0)
        }
    }

    /// Captured trampoline + user pointer for a single `register` call.
    /// `@unchecked Sendable` because `UnsafeMutableRawPointer` is not
    /// declared `Sendable` by the standard library; the lock around
    /// the capture provides the actual synchronization.
    private struct CapturedTrampoline: @unchecked Sendable {
        var callback: HandleStreamAdapter<CollidingHandle, RAChatMessage>.CCallback?
        var userPtr: UnsafeMutableRawPointer?
    }

    // MARK: - Shared helpers

    private func uniqueStreamKey(_ function: String = #function) -> String {
        "test-\(function)-\(UUID().uuidString)"
    }

    /// Poll `predicate` at 10ms intervals up to `timeout`, returning the
    /// final value. Used in lieu of fixed sleeps so tests pass quickly on
    /// fast machines and remain stable on slow CI.
    private func waitFor(
        timeout: TimeInterval = 2.0,
        _ predicate: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return predicate()
    }

    // MARK: - Test 1: AsyncStream cancellation triggers exactly one teardown

    func testAsyncStreamCancellationTerminatesNativeWork() async throws {
        let registerCount = OSAllocatedUnfairLock<Int>(initialState: 0)
        let unregisterCount = OSAllocatedUnfairLock<Int>(initialState: 0)
        let handle = UniqueHandle(id: UUID())
        let streamKey = uniqueStreamKey()

        let adapter = HandleStreamAdapter<UniqueHandle, RAChatMessage>(
            handle: handle,
            streamKey: streamKey,
            register: { _, _, _ in
                registerCount.withLock { $0 += 1 }
                return 0
            },
            unregister: { _ in
                unregisterCount.withLock { $0 += 1 }
            },
            quiesce: {}
        )

        let consumer = Task {
            for await _ in adapter.stream() {
                // No events are delivered; we drive teardown via cancel().
            }
        }

        let installed = await waitFor { registerCount.withLock { $0 } == 1 }
        XCTAssertTrue(installed, "register must run exactly once for the first subscriber")
        XCTAssertEqual(registerCount.withLock { $0 }, 1)

        consumer.cancel()

        // Cancellation propagates through onTermination → detach → tearDown.
        let torn = await waitFor { unregisterCount.withLock { $0 } == 1 }
        XCTAssertTrue(torn, "unregister must fire exactly once when the sole subscriber cancels")
        XCTAssertEqual(unregisterCount.withLock { $0 }, 1)
        XCTAssertEqual(registerCount.withLock { $0 }, 1, "teardown must not re-enter register()")
    }

    // MARK: - Test 2: N concurrent first-subscribers collapse to a single install

    func testFirstSubscriberRaceSerializesInstall() async throws {
        let registerCount = OSAllocatedUnfairLock<Int>(initialState: 0)
        let unregisterCount = OSAllocatedUnfairLock<Int>(initialState: 0)
        let handle = UniqueHandle(id: UUID())
        let streamKey = uniqueStreamKey()

        let adapter = HandleStreamAdapter<UniqueHandle, RAChatMessage>(
            handle: handle,
            streamKey: streamKey,
            register: { _, _, _ in
                registerCount.withLock { $0 += 1 }
                // Widen the install window so the remaining attach() calls
                // race through and observe `.installing`. Blocking the
                // current cooperative thread is acceptable here because
                // only the installer ever enters this branch.
                Thread.sleep(forTimeInterval: 0.05)
                return 0
            },
            unregister: { _ in
                unregisterCount.withLock { $0 += 1 }
            },
            quiesce: {}
        )

        let consumerCount = 10
        var consumers: [Task<Void, Never>] = []
        for _ in 0..<consumerCount {
            consumers.append(Task {
                for await _ in adapter.stream() {
                    // never delivered
                }
            })
        }

        // Wait for all 10 attaches to land and the installer's install()
        // to complete (Thread.sleep above is 50ms; 250ms is comfortable).
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(
            registerCount.withLock { $0 },
            1,
            "register must run exactly once even with \(consumerCount) concurrent attaches"
        )

        for task in consumers { task.cancel() }

        let torn = await waitFor { unregisterCount.withLock { $0 } == 1 }
        XCTAssertTrue(torn, "unregister must fire exactly once after the last subscriber detaches")
        XCTAssertEqual(unregisterCount.withLock { $0 }, 1)
    }

    // MARK: - Test 3: install() failure rolls back every pending continuation

    func testInstallFailureRollsBackAllPendingContinuations() async throws {
        let registerCount = OSAllocatedUnfairLock<Int>(initialState: 0)
        let unregisterCount = OSAllocatedUnfairLock<Int>(initialState: 0)
        let handle = UniqueHandle(id: UUID())
        let streamKey = uniqueStreamKey()

        // The first register() call fails; subsequent calls succeed. This
        // both verifies the rollback path AND proves the state machine
        // returned to `.notInstalled` (otherwise the retry would short-
        // circuit as `.installed` and never call register again).
        let failuresRemaining = OSAllocatedUnfairLock<Int>(initialState: 1)

        let adapter = HandleStreamAdapter<UniqueHandle, RAChatMessage>(
            handle: handle,
            streamKey: streamKey,
            register: { _, _, _ in
                registerCount.withLock { $0 += 1 }
                let shouldFail = failuresRemaining.withLock { (remaining: inout Int) -> Bool in
                    if remaining > 0 {
                        remaining -= 1
                        return true
                    }
                    return false
                }
                return shouldFail ? -1 : 0
            },
            unregister: { _ in
                unregisterCount.withLock { $0 += 1 }
            },
            quiesce: {}
        )

        // Drive the failing install. The for-await must drain to zero
        // iterations because the rollback finishes every pending
        // continuation (including this one) before stream() returns.
        var deliveredEventCount = 0
        for await _ in adapter.stream() {
            deliveredEventCount += 1
        }

        XCTAssertEqual(
            deliveredEventCount,
            0,
            "failed install must not deliver any events to pending continuations"
        )
        XCTAssertEqual(
            registerCount.withLock { $0 },
            1,
            "register must run exactly once on the first install attempt"
        )
        XCTAssertEqual(
            unregisterCount.withLock { $0 },
            0,
            "unregister must NOT fire when install never reached `.installed`"
        )

        // A second subscriber must reach register() — proving the state
        // machine rolled back to `.notInstalled`.
        let secondConsumer = Task {
            for await _ in adapter.stream() {
                // never delivered
            }
        }

        let retried = await waitFor { registerCount.withLock { $0 } == 2 }
        XCTAssertTrue(
            retried,
            "state machine must reset to `.notInstalled` so a retry re-enters register()"
        )
        XCTAssertEqual(registerCount.withLock { $0 }, 2)

        secondConsumer.cancel()

        let torn = await waitFor { unregisterCount.withLock { $0 } == 1 }
        XCTAssertTrue(torn, "successful install + cancel must fire unregister exactly once")
    }

    // MARK: - Test 4: Distinct handles with colliding hashes stay independent

    func testHandleHashCollisionDoesNotAliasStreams() async throws {
        let streamKey = uniqueStreamKey()
        let handleA = CollidingHandle(id: 1)
        let handleB = CollidingHandle(id: 2)

        // Sanity-check the test prerequisite.
        XCTAssertEqual(
            handleA.hashValue,
            handleB.hashValue,
            "test prereq: handles must hash to the same value"
        )
        XCTAssertNotEqual(
            handleA,
            handleB,
            "test prereq: handles must compare distinct under =="
        )

        // Capture each handle's installed C trampoline so the test can
        // fire proto-byte payloads into each fan-out independently and
        // observe per-handle subscriber isolation.
        let captureA = OSAllocatedUnfairLock<CapturedTrampoline>(initialState: .init())
        let captureB = OSAllocatedUnfairLock<CapturedTrampoline>(initialState: .init())

        let adapterA = HandleStreamAdapter<CollidingHandle, RAChatMessage>(
            handle: handleA,
            streamKey: streamKey,
            register: { _, callback, userPtr in
                // Build the `@unchecked Sendable` snapshot before crossing
                // the inner @Sendable closure boundary so that
                // `UnsafeMutableRawPointer?` is never captured directly.
                let snapshot = CapturedTrampoline(callback: callback, userPtr: userPtr)
                captureA.withLock { $0 = snapshot }
                return 0
            },
            unregister: { _ in },
            quiesce: {}
        )
        let adapterB = HandleStreamAdapter<CollidingHandle, RAChatMessage>(
            handle: handleB,
            streamKey: streamKey,
            register: { _, callback, userPtr in
                let snapshot = CapturedTrampoline(callback: callback, userPtr: userPtr)
                captureB.withLock { $0 = snapshot }
                return 0
            },
            unregister: { _ in },
            quiesce: {}
        )

        let receivedA = OSAllocatedUnfairLock<[String]>(initialState: [])
        let receivedB = OSAllocatedUnfairLock<[String]>(initialState: [])

        let consumerA = Task {
            for await event in adapterA.stream() {
                receivedA.withLock { $0.append(event.id) }
            }
        }
        let consumerB = Task {
            for await event in adapterB.stream() {
                receivedB.withLock { $0.append(event.id) }
            }
        }

        let ready = await waitFor {
            captureA.withLock { $0.callback } != nil &&
                captureB.withLock { $0.callback } != nil
        }
        XCTAssertTrue(ready, "both fan-out registrations must capture their trampolines")

        // Deliver one event into handleA's fan-out. handleB's stream must
        // remain empty because the static registry routes by the
        // AnyHashable-wrapped handle, not the colliding raw hash.
        var eventA = RAChatMessage()
        eventA.id = "from-A"
        try Self.deliver(event: eventA, into: captureA)

        var eventB = RAChatMessage()
        eventB.id = "from-B"
        try Self.deliver(event: eventB, into: captureB)

        let settled = await waitFor {
            receivedA.withLock { $0.count } == 1 && receivedB.withLock { $0.count } == 1
        }
        XCTAssertTrue(settled, "each fan-out should deliver exactly its own event")
        XCTAssertEqual(
            receivedA.withLock { $0 },
            ["from-A"],
            "handleA's stream must receive only handleA's event"
        )
        XCTAssertEqual(
            receivedB.withLock { $0 },
            ["from-B"],
            "handleB's stream must receive only handleB's event"
        )

        consumerA.cancel()
        consumerB.cancel()
    }

    // MARK: - Test 5: Synchronous unregister callback must not deadlock tearDown

    /// Regression guard for `pass3-syn-057`: `tearDown` must release the
    /// per-handle lock BEFORE calling the C `unregister(...)` closure.
    /// If a future commons unset path synchronously delivers a final
    /// event (the contract the install() comment was added to defend
    /// against), the trampoline re-enters `broadcast` →
    /// `state.withLock`. `OSAllocatedUnfairLock` is non-recursive, so
    /// the old code (which held the lock across `unregister(handle)`)
    /// would deadlock. With the fixed ordering this test completes
    /// inside the 1-second timeout and `unregister` fires exactly once.
    func testSynchronousUnregisterCallbackDoesNotDeadlockTearDown() async throws {
        let registerCount = OSAllocatedUnfairLock<Int>(initialState: 0)
        let unregisterCount = OSAllocatedUnfairLock<Int>(initialState: 0)
        let capture = OSAllocatedUnfairLock<CapturedTrampoline>(initialState: .init())
        let handle = CollidingHandle(id: 42)
        let streamKey = uniqueStreamKey()

        let adapter = HandleStreamAdapter<CollidingHandle, RAChatMessage>(
            handle: handle,
            streamKey: streamKey,
            register: { _, callback, userPtr in
                registerCount.withLock { $0 += 1 }
                let snapshot = CapturedTrampoline(callback: callback, userPtr: userPtr)
                capture.withLock { $0 = snapshot }
                return 0
            },
            unregister: { _ in
                // Simulate a commons unset path that synchronously
                // delivers a final byte during deregistration. The
                // trampoline re-enters `deliverBytes` → `broadcast` →
                // `state.withLock`. If `tearDown` holds the lock across
                // this call, `OSAllocatedUnfairLock` (non-recursive)
                // deadlocks. With the fix, the lock is released before
                // this closure runs and re-entry is safe.
                let snapshot = capture.withLock { $0 }
                if let callback = snapshot.callback {
                    var finalEvent = RAChatMessage()
                    finalEvent.id = "final-from-unregister"
                    if let bytes = try? finalEvent.serializedData() {
                        bytes.withUnsafeBytes { raw in
                            let base = raw.bindMemory(to: UInt8.self).baseAddress
                            callback(base, bytes.count, snapshot.userPtr)
                        }
                    }
                }
                unregisterCount.withLock { $0 += 1 }
            },
            quiesce: {}
        )

        let consumer = Task {
            for await _ in adapter.stream() {
                // Drain. The synchronous final byte will fan out here
                // before the consumer is torn down.
            }
        }

        let installed = await waitFor { registerCount.withLock { $0 } == 1 }
        XCTAssertTrue(installed, "register must fire exactly once for the sole subscriber")

        // Drive tearDown via cancellation. With the fix this completes
        // well inside the 1-second budget; pre-fix this hangs forever
        // because tearDown's lock contends with the re-entered
        // broadcast's lock acquisition.
        let teardownStart = Date()
        consumer.cancel()
        let torn = await waitFor(timeout: 1.0) { unregisterCount.withLock { $0 } == 1 }
        let elapsed = Date().timeIntervalSince(teardownStart)

        XCTAssertTrue(
            torn,
            "tearDown must complete within 1 second; synchronous unregister callback must not deadlock"
        )
        XCTAssertLessThan(elapsed, 1.0, "tearDown elapsed = \(elapsed)s")
        XCTAssertEqual(
            unregisterCount.withLock { $0 },
            1,
            "unregister must fire exactly once even when it synchronously re-enters broadcast"
        )
        XCTAssertEqual(
            registerCount.withLock { $0 },
            1,
            "tearDown must not re-enter register()"
        )
    }

    // MARK: - Test 6: Cancel-to-native latency parity contract (pass3-syn-032)

    /// Cross-SDK cancellation contract regression test.
    ///
    /// `pass3-syn-032`: Swift is the reference SDK for the streaming
    /// fan-out adapters; Kotlin/Flutter/RN/Web mirror this shape. The
    /// cross-SDK contract is: when the LAST consumer of a fan-out cancels
    /// (or, equivalently, when a terminal event arrives), the C-side
    /// `unregister(handle)` MUST fire exactly once and the latency from
    /// `cancel()` to the unregister callback firing must be bounded
    /// (here: <250ms on a CI runner — generously slack to absorb
    /// scheduler jitter).
    ///
    /// The test installs a fresh trampoline, attaches N consumers,
    /// cancels them all at once, and asserts:
    ///   1. `unregister` fires exactly once,
    ///   2. the elapsed wall-clock from the cancel() call to the
    ///      observed unregister is < 250ms,
    ///   3. `register` is not re-entered as a side-effect of teardown.
    func testCancelToNativeLatencyContract() async throws {
        let registerCount = OSAllocatedUnfairLock<Int>(initialState: 0)
        let unregisterCount = OSAllocatedUnfairLock<Int>(initialState: 0)
        let handle = UniqueHandle(id: UUID())
        let streamKey = uniqueStreamKey()

        let adapter = HandleStreamAdapter<UniqueHandle, RAChatMessage>(
            handle: handle,
            streamKey: streamKey,
            register: { _, _, _ in
                registerCount.withLock { $0 += 1 }
                return 0
            },
            unregister: { _ in
                unregisterCount.withLock { $0 += 1 }
            },
            quiesce: {}
        )

        let consumerCount = 5
        var consumers: [Task<Void, Never>] = []
        for _ in 0..<consumerCount {
            consumers.append(Task {
                for await _ in adapter.stream() {
                    // No events; we cancel below.
                }
            })
        }

        let installed = await waitFor { registerCount.withLock { $0 } == 1 }
        XCTAssertTrue(installed, "register must run exactly once for the consumer cohort")

        // Cross-SDK cancellation latency budget. Each SDK adapter has an
        // analogous test (Kotlin `LLMStreamAdapter`, Flutter
        // `dart_bridge_*` proto callbacks, RN HybridLLM, Web StreamWorker)
        // that fans cancel from a structured-concurrency primitive into
        // commons. The 250 ms budget is the parity contract.
        let cancelStart = Date()
        for task in consumers { task.cancel() }

        let torn = await waitFor(timeout: 0.25) { unregisterCount.withLock { $0 } == 1 }
        let elapsed = Date().timeIntervalSince(cancelStart)

        XCTAssertTrue(
            torn,
            "cross-SDK cancel-to-native latency contract violated: \(elapsed)s > 250ms"
        )
        XCTAssertLessThan(
            elapsed,
            0.25,
            "cancel-to-native unregister fired in \(elapsed * 1000) ms (budget: 250 ms)"
        )
        XCTAssertEqual(
            unregisterCount.withLock { $0 },
            1,
            "unregister must fire exactly once regardless of how many consumers cancel"
        )
        XCTAssertEqual(
            registerCount.withLock { $0 },
            1,
            "teardown must not re-enter register()"
        )
    }

    // MARK: - Private helpers

    /// Invoke a captured `@convention(c)` trampoline with the proto-byte
    /// payload of `event`, simulating the C-side delivering one event to
    /// a specific fan-out registration.
    private static func deliver(
        event: RAChatMessage,
        into capture: OSAllocatedUnfairLock<CapturedTrampoline>
    ) throws {
        let snapshot = capture.withLock { $0 }
        let callback = try XCTUnwrap(snapshot.callback)
        let bytes = try event.serializedData()
        bytes.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: UInt8.self).baseAddress
            callback(base, bytes.count, snapshot.userPtr)
        }
    }
}
