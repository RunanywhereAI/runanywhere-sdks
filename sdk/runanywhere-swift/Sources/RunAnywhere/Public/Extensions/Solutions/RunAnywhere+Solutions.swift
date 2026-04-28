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
import SwiftProtobuf

// MARK: - SolutionHandle

/// Opaque, ARC-safe wrapper around a `rac_solution_handle_t`.
///
/// Owns the underlying C handle and guarantees `rac_solution_destroy`
/// runs exactly once (either explicitly via `destroy()` or on the final
/// release through `deinit`). All lifecycle verbs are forwarded one-to-one
/// to the C ABI.
public final class SolutionHandle: @unchecked Sendable {

    private let lock = NSLock()
    private var handle: rac_solution_handle_t?

    fileprivate init(handle: rac_solution_handle_t) {
        self.handle = handle
    }

    deinit {
        if let h = handle {
            rac_solution_destroy(h)
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
        lock.lock()
        defer { lock.unlock() }
        if let h = handle {
            rac_solution_destroy(h)
            handle = nil
        }
    }

    private func withHandle(_ body: (rac_solution_handle_t) -> rac_result_t) throws {
        lock.lock()
        let h = handle
        lock.unlock()

        guard let h else {
            throw SDKException.runtime(.invalidState, "Solution handle has already been destroyed")
        }

        let result = body(h)
        guard result == RAC_SUCCESS else {
            throw SDKException.runtime(
                .processingFailed,
                "Solution call failed with rac_result_t \(result)"
            )
        }
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
                throw SDKException.runtime(
                    .invalidConfiguration,
                    "rac_solution_create_from_proto failed with \(result)"
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
                throw SDKException.runtime(
                    .invalidConfiguration,
                    "rac_solution_create_from_yaml failed with \(result)"
                )
            }

            return SolutionHandle(handle: raw)
        }

        private func ensureReady() async throws {
            guard RunAnywhere.isSDKInitialized else {
                throw SDKException.general(.notInitialized, "SDK not initialized")
            }
            try await RunAnywhere.ensureServicesReady()
        }
    }
}
