//
//  RunAnywhereLifetimeGateTests.swift
//  RunAnywhere SDK
//
//  Focused coverage for reset/initialize lifetime serialization.
//

import CRACommons
import Foundation
import os
import XCTest

@testable import RunAnywhere

final class RunAnywhereLifetimeGateTests: XCTestCase {

    func testResetRejectsInitializationUntilMatchingGenerationCompletes() throws {
        var gate = SDKLifetimeGate()
        XCTAssertNoThrow(try gate.requireInitializationAllowed())

        let generation = try XCTUnwrap(gate.beginReset())
        XCTAssertTrue(gate.isResetInProgress)
        XCTAssertThrowsError(try gate.requireInitializationAllowed()) { error in
            guard let sdkError = error as? SDKException else {
                return XCTFail("expected SDKException, got \(error)")
            }
            XCTAssertEqual(sdkError.code, .invalidState)
            XCTAssertEqual(sdkError.category, .internal)
        }

        XCTAssertFalse(gate.completeReset(generation: generation &+ 1))
        XCTAssertTrue(gate.isResetInProgress, "stale completion must not reopen the gate")
        XCTAssertTrue(gate.completeReset(generation: generation))
        XCTAssertFalse(gate.isResetInProgress)
        XCTAssertNoThrow(try gate.requireInitializationAllowed())
    }

    func testConcurrentResetSharesCurrentGeneration() throws {
        var gate = SDKLifetimeGate()
        let priorGeneration = gate.generation
        let firstGeneration = try XCTUnwrap(gate.beginReset())

        XCTAssertNil(gate.beginReset(), "a concurrent reset must not create a second lifetime")
        XCTAssertEqual(gate.generation, firstGeneration)
        XCTAssertFalse(gate.permitsCompletion(generation: priorGeneration))
        XCTAssertFalse(gate.permitsCompletion(generation: firstGeneration))

        XCTAssertTrue(gate.completeReset(generation: firstGeneration))
        XCTAssertFalse(gate.permitsCompletion(generation: priorGeneration))
        XCTAssertTrue(gate.permitsCompletion(generation: firstGeneration))
        let secondGeneration = try XCTUnwrap(gate.beginReset())
        XCTAssertEqual(secondGeneration, firstGeneration &+ 1)
    }
}

final class CppBridgeLifetimeGateTests: XCTestCase {

    func testShutdownWaitsForInitializationThenOwnsTeardown() throws {
        var gate = CppBridgeLifetimeGate()

        XCTAssertTrue(try gate.beginInitialization())
        XCTAssertEqual(gate.beginShutdown(), .waitForInitialization)
        XCTAssertThrowsError(try gate.beginInitialization())

        XCTAssertTrue(gate.completeInitialization())
        XCTAssertTrue(gate.isInitialized)
        XCTAssertEqual(gate.beginShutdown(), .start)
        XCTAssertFalse(gate.isInitialized)
        XCTAssertEqual(gate.beginShutdown(), .join)
        XCTAssertThrowsError(try gate.beginInitialization())

        XCTAssertTrue(gate.completeShutdown())
        XCTAssertTrue(try gate.beginInitialization())
    }

    func testRollbackBlocksReinitializationUntilCleanupCompletes() throws {
        var gate = CppBridgeLifetimeGate()

        XCTAssertTrue(try gate.beginInitialization())
        XCTAssertTrue(gate.beginRollback())
        XCTAssertThrowsError(try gate.beginInitialization())
        XCTAssertEqual(gate.beginShutdown(), .join)
        XCTAssertTrue(gate.completeShutdown())
        XCTAssertTrue(try gate.beginInitialization())
    }
}

final class ComponentActorLifetimeTests: XCTestCase {

    func testDestroyedActorCreatesFreshHandleOnlyForNewBridgeLifetime() async throws {
        let state = OSAllocatedUnfairLock(initialState: ComponentActorTestState())
        let vtable = CppBridge.ComponentVTable(
            component: .tts,
            create: { outHandle in
                let address = state.withLock { lockedState -> Int in
                    lockedState.createdHandleCount += 1
                    return lockedState.createdHandleCount
                }
                outHandle.pointee = UnsafeMutableRawPointer(bitPattern: address)
                return RAC_SUCCESS
            },
            isLoaded: { _ in RAC_FALSE },
            cleanup: { _ in },
            destroy: { _ in
                state.withLock { $0.destroyedHandleCount += 1 }
            },
            loadModel: nil
        )
        let actor = CppBridge.ComponentActor(
            vtable: vtable,
            bridgeIsInitialized: {
                state.withLock { $0.bridgeIsInitialized }
            }
        )

        _ = try await actor.getHandle()
        await actor.destroy()

        do {
            _ = try await actor.getHandle()
            XCTFail("a destroyed component must stay closed in the retiring bridge lifetime")
        } catch let error as SDKException {
            XCTAssertEqual(error.code, .notInitialized)
            XCTAssertEqual(error.category, .component)
        }

        state.withLock { $0.bridgeIsInitialized = true }
        _ = try await actor.getHandle()

        XCTAssertEqual(state.withLock { $0.createdHandleCount }, 2)
        XCTAssertEqual(state.withLock { $0.destroyedHandleCount }, 1)
        let isShutDown = await actor.isShutDown
        XCTAssertFalse(isShutDown)

        await actor.destroy()
    }
}

private struct ComponentActorTestState: Sendable {
    var bridgeIsInitialized = false
    var createdHandleCount = 0
    var destroyedHandleCount = 0
}

final class SDKEventSubscriptionLifetimeTests: XCTestCase {

    func testUnsubscribeQuiescesBeforeReleasingCallbackContext() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let sourceFile = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+SDKEvents.swift"
            )
        let source = try String(contentsOf: sourceFile, encoding: .utf8)

        XCTAssertTrue(source.contains("rac_sdk_event_quiesce"))
        let unsubscribe = try XCTUnwrap(source.range(of: "unsubscribe(subscriptionId)"))
        let quiesce = try XCTUnwrap(source.range(of: "quiesce()", range: unsubscribe.upperBound..<source.endIndex))
        let remove = try XCTUnwrap(
            source.range(of: "pointers.removeValue", range: quiesce.upperBound..<source.endIndex)
        )
        let release = try XCTUnwrap(
            source.range(of: ".release()", range: remove.upperBound..<source.endIndex)
        )

        XCTAssertLessThan(unsubscribe.lowerBound, quiesce.lowerBound)
        XCTAssertLessThan(quiesce.lowerBound, remove.lowerBound)
        XCTAssertLessThan(remove.lowerBound, release.lowerBound)
    }
}

final class HTTPClientAdapterLifetimeTests: XCTestCase {

    func testCredentialBoundaryDoesNotFollowRedirects() {
        XCTAssertFalse(HTTPClientAdapter.RequestTrustBoundary.controlPlane.followsRedirects)
        XCTAssertTrue(HTTPClientAdapter.RequestTrustBoundary.externalAsset.followsRedirects)
    }

    func testShutdownRequiresNewLifetimeConfiguration() async throws {
        let adapter = HTTPClientAdapter.shared
        await adapter.shutdown()

        let firstURL = try XCTUnwrap(URL(string: "https://first.example.com"))
        await adapter.configure(baseURL: firstURL, apiKey: "first-api-key")
        let firstConfigured = await adapter.isConfigured
        let firstGenerationValue = await adapter.activeConfigurationGeneration
        let firstGeneration = try XCTUnwrap(firstGenerationValue)
        XCTAssertTrue(firstConfigured)

        await adapter.shutdown()
        let configuredAfterShutdown = await adapter.isConfigured
        XCTAssertFalse(configuredAfterShutdown, "reset must remove the prior lifetime's credentials")

        let secondURL = try XCTUnwrap(URL(string: "https://second.example.com"))
        await adapter.configure(baseURL: secondURL, apiKey: "second-api-key")
        let secondConfigured = await adapter.isConfigured
        let secondGenerationValue = await adapter.activeConfigurationGeneration
        let secondGeneration = try XCTUnwrap(secondGenerationValue)
        XCTAssertTrue(secondConfigured, "a later lifetime must accept its own configuration")
        XCTAssertNotEqual(firstGeneration, secondGeneration)
        let staleGenerationIsCurrent = await adapter.configurationIsCurrent(generation: firstGeneration)
        XCTAssertFalse(staleGenerationIsCurrent, "a request snapshot must not adopt later credentials")

        await adapter.shutdown()
    }
}

final class TelemetryHTTPTaskRegistryTests: XCTestCase {

    func testDrainWaitsForAcceptedTasksAndClosesAdmission() async {
        let registry = TelemetryHTTPTaskRegistry()
        let gate = TelemetryTaskTestGate()
        registry.beginLifetime()

        XCTAssertTrue(
            registry.submit {
                await gate.markStartedAndWait()
            }
        )

        let releaseTask = Task {
            await gate.waitUntilStarted()
            await gate.release()
        }
        await registry.drain()
        await releaseTask.value

        XCTAssertEqual(registry.pendingTaskCount, 0)
        XCTAssertFalse(registry.submit {})
    }

    func testNewLifetimeCancelsAndFinishesPriorTasksBeforeAdmission() async {
        let registry = TelemetryHTTPTaskRegistry()
        let cancellation = TelemetryCancellationProbe()
        let firstGeneration = registry.beginLifetime()

        XCTAssertTrue(
            registry.submit {
                await cancellation.waitForCancellation()
            }
        )
        await cancellation.waitUntilStarted()

        let secondGeneration = registry.beginLifetime()
        XCTAssertNotEqual(firstGeneration, secondGeneration)
        let wasCancelled = await cancellation.wasCancelled
        XCTAssertTrue(wasCancelled)
        XCTAssertEqual(registry.pendingTaskCount, 0)

        await registry.drain()
    }
}

private actor TelemetryTaskTestGate {
    private var started = false
    private var released = false

    func markStartedAndWait() async {
        started = true
        while !released {
            await Task.yield()
        }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func release() {
        released = true
    }
}

private actor TelemetryCancellationProbe {
    private var started = false
    private(set) var wasCancelled = false

    func waitForCancellation() async {
        started = true
        while !Task.isCancelled {
            await Task.yield()
        }
        wasCancelled = true
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }
}
