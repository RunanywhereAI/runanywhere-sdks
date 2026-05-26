//
//  RunAnywhere+Solutions.swift
//  RunAnywhere SDK
//
//  Public API for L5 solutions runtime (T4.7 / T4.8). A "solution" is a
//  prepackaged pipeline config — either a typed `RASolutionConfig` proto
//  or YAML sugar — that the C++ core compiles into a GraphScheduler DAG
//  and executes through the `rac_solution_*` C ABI.
//
//  Surface mirrors the rest of the SDK's capability-shape: callers reach
//  the API through `RunAnywhere.solutions.run(config:)`. The proto-byte
//  variant is the canonical entry point; the typed-proto helper is a
//  thin convenience that serialises and forwards.
//

import CRACommons
import Foundation
import os
import SwiftProtobuf

// MARK: - SolutionHandle

/// Opaque, ARC-safe wrapper around a `rac_solution_handle_t`.
///
/// Owns the underlying C handle and guarantees `rac_solution_destroy`
/// runs exactly once (either explicitly via `destroy()` or on the final
/// release through `deinit`). All lifecycle verbs are forwarded one-to-one
/// to the C ABI.
public final class SolutionHandle: @unchecked Sendable {

    // Per AGENTS.md: NSLock is forbidden — use `OSAllocatedUnfairLock`.
    private let handle: OSAllocatedUnfairLock<rac_solution_handle_t?>

    // swiftlint:disable:next strict_fileprivate
    fileprivate init(handle: rac_solution_handle_t) {
        self.handle = OSAllocatedUnfairLock(initialState: handle)
    }

    deinit {
        if let handle = handle.withLock({ $0 }) {
            rac_solution_destroy(handle)
        }
    }

    /// Start the underlying scheduler. Non-blocking.
    public func start() throws {
        try withHandle { rac_solution_start($0) }
    }

    /// Request a graceful shutdown. Non-blocking.
    public func stop() throws {
        try withHandle { rac_solution_stop($0) }
    }

    /// Force-cancel the graph. Returns once worker threads observe cancellation.
    public func cancel() throws {
        try withHandle { rac_solution_cancel($0) }
    }

    /// Feed a single UTF-8 item into the root input edge.
    public func feed(_ item: String) throws {
        try withHandle { handle in
            item.withCString { rac_solution_feed(handle, $0) }
        }
    }

    /// Signal end-of-stream on the root input edge.
    public func closeInput() throws {
        try withHandle { rac_solution_close_input($0) }
    }

    /// Cancel, join, and destroy the solution. Idempotent.
    public func destroy() {
        handle.withLock { current in
            if let handle = current {
                rac_solution_destroy(handle)
                current = nil
            }
        }
    }

    /// Whether the underlying C handle is still live (CANONICAL_API §11).
    ///
    /// Returns `true` as long as `destroy()` has not been called (or `deinit`
    /// triggered). Once destroyed, further calls to the lifecycle verbs throw
    /// `SDKException(.invalidState)`.
    public var isAlive: Bool {
        handle.withLock { $0 != nil }
    }

    /// Run `body` against the native handle while holding the slot lock so
    /// that a concurrent `destroy()` (or `deinit`) cannot free the handle
    /// mid-call. `rac_solution_destroy` cancels and joins before deleting
    /// the runner, so serialising the lifecycle verbs is the simplest way
    /// to honour the Sendable contract without resurrecting a freed pointer
    /// (see swift-public-features-002).
    private func withHandle(_ body: (rac_solution_handle_t) -> rac_result_t) throws {
        let result: rac_result_t = try handle.withLock { current in
            guard let current else {
                throw SDKException(
                    code: .invalidState,
                    message: "Solution handle has already been destroyed",
                    category: .internal
                )
            }
            return body(current)
        }
        guard result == RAC_SUCCESS else {
            throw SDKException(
                code: .processingFailed,
                message: SolutionHandle.errorMessage(
                    op: "Solution lifecycle call",
                    rc: result
                ),
                category: .internal
            )
        }
    }

    /// Compose a human-readable failure message from a `rac_result_t`.
    ///
    /// Pairs `rac_error_message(rc)` (canonical static description per
    /// code) with `rac_error_get_details()` (thread-local detail set by
    /// the failing C call, if any) so callers see the underlying cause
    /// instead of just a numeric code.
    fileprivate static func errorMessage(op: String, rc: rac_result_t) -> String {
        var message = "\(op) failed"
        let description = String(cString: rac_error_message(rc))
        if !description.isEmpty {
            message += ": \(description)"
        }
        if let detailPtr = rac_error_get_details() {
            let detail = String(cString: detailPtr)
            if !detail.isEmpty {
                message += " (\(detail))"
            }
        }
        message += " [rc=\(rc)]"
        return message
    }
}

// MARK: - Solutions Capability

public extension RunAnywhere {

    /// Capability accessor for solution-runtime operations.
    ///
    /// Mirrors the Kotlin/Flutter/RN/Web shape — `RunAnywhere.solutions.run(config:)`.
    static var solutions: Solutions { Solutions() }

    /// Stateless namespace for solution-runtime APIs. Backed by the C ABI;
    /// keeps no mutable state of its own — every handle returned by `run`
    /// owns its own native solution.
    struct Solutions: Sendable {

        // swiftlint:disable:next strict_fileprivate
        fileprivate init() {}

        /// Construct and return a started solution from a serialised
        /// `runanywhere.v1.SolutionConfig` (or `PipelineSpec`) message.
        ///
        /// The handle is returned in the **created** state — call
        /// `start()` to launch worker threads. Callers that only want the
        /// "create + start" combo should chain `try handle.start()`.
        ///
        /// - Parameter configBytes: Serialized `SolutionConfig` proto.
        /// - Returns: Lifecycle handle owning the underlying solution.
        public func run(configBytes: Data) async throws -> SolutionHandle {
            try await ensureReady()

            var raw: rac_solution_handle_t?
            let result = configBytes.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> rac_result_t in
                rac_solution_create_from_proto(buffer.baseAddress, configBytes.count, &raw)
            }

            guard result == RAC_SUCCESS, let raw else {
                throw SDKException(
                    code: .invalidConfiguration,
                    message: SolutionHandle.errorMessage(
                        op: "rac_solution_create_from_proto",
                        rc: result
                    ),
                    category: .internal
                )
            }

            return SolutionHandle(handle: raw)
        }

        /// Convenience overload: serialise a typed `RASolutionConfig`
        /// proto and forward to `run(configBytes:)`. Frontends that
        /// already speak the generated proto types should prefer this
        /// surface; downstream the bytes path is identical.
        public func run(config: RASolutionConfig) async throws -> SolutionHandle {
            let bytes = try config.serializedData()
            return try await run(configBytes: bytes)
        }

        /// YAML sugar — construct a solution from a YAML document. The
        /// loader accepts both `SolutionConfig` shape (top-level oneof
        /// key) and `PipelineSpec` shape (`name`/`operators`/`edges`).
        public func run(yaml: String) async throws -> SolutionHandle {
            try await ensureReady()

            var raw: rac_solution_handle_t?
            let result = yaml.withCString { rac_solution_create_from_yaml($0, &raw) }

            guard result == RAC_SUCCESS, let raw else {
                throw SDKException(
                    code: .invalidConfiguration,
                    message: SolutionHandle.errorMessage(
                        op: "rac_solution_create_from_yaml",
                        rc: result
                    ),
                    category: .internal
                )
            }

            return SolutionHandle(handle: raw)
        }

        private func ensureReady() async throws {
            guard RunAnywhere.isInitialized else {
                throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
            }
            try await RunAnywhere.ensureServicesReady()
        }
    }
}
