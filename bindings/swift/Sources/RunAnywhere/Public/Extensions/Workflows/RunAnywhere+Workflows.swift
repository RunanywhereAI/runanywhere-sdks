//
//  RunAnywhere+Workflows.swift
//  RunAnywhere SDK
//
//  Public API for the agent workflow runner. A workflow is a user-drawn DAG
//  that C++ commons validates, orders, and executes, reached here through the
//  `rac_agent_*` C ABI.
//
//  Two node types cannot run inside commons. Tool Call needs the Swift tool
//  registry and Code needs a JavaScript engine, so this file installs a host
//  callback table that supplies both. Registration is idempotent and happens
//  the first time anything touches `RunAnywhere.workflows`.
//

import CRACommons
import Foundation
import JavaScriptCore
import os
import SwiftProtobuf

// MARK: - WorkflowRun

/// A single execution of a workflow. Owns the native run handle and guarantees
/// `rac_agent_run_destroy` runs exactly once.
public final class WorkflowRun: @unchecked Sendable {

    private let handle: OSAllocatedUnfairLock<WorkflowRunState>

    // swiftlint:disable:next strict_fileprivate
    fileprivate init(handle: rac_handle_t, events: AsyncStream<RAWorkflowRunEvent>) {
        self.handle = OSAllocatedUnfairLock(initialState: WorkflowRunState(handle: handle))
        self.events = events
    }

    deinit {
        handle.withLock { state in
            if let current = state.handle {
                rac_agent_run_destroy(current)
                state.handle = nil
            }
        }
    }

    /// Node state changes and run start/finish, in the order commons emitted
    /// them. Subscribing does not start the run.
    public let events: AsyncStream<RAWorkflowRunEvent>

    /// Begin executing. Non-blocking; progress arrives on `events`.
    public func start() throws {
        try withHandle { rac_agent_run_start($0) }
    }

    /// Request cancellation. The running node finishes, nothing further is
    /// scheduled, and the record closes as cancelled.
    public func cancel() throws {
        try withHandle { rac_agent_run_cancel($0) }
    }

    /// The record as it stands, valid mid-run as well as after it finishes.
    public func record() throws -> RAWorkflowRunRecord {
        // The buffer is filled and drained inside the lock rather than captured
        // by the closure: rac_proto_buffer_t is not Sendable, so it cannot
        // cross into a @Sendable body.
        let encoded: Data = try handle.withLock { state in
            guard let current = state.handle else {
                throw SDKException(
                    code: .invalidState,
                    message: "Workflow run has already been destroyed",
                    category: .internal
                )
            }

            var buffer = rac_proto_buffer_t()
            rac_proto_buffer_init(&buffer)
            defer { rac_proto_buffer_free(&buffer) }

            let result = rac_agent_run_record_proto(current, &buffer)
            guard result == RAC_SUCCESS, let data = buffer.data else {
                throw WorkflowErrors.failure(op: "rac_agent_run_record_proto", rc: result)
            }
            return Data(bytes: data, count: buffer.size)
        }
        return try RAWorkflowRunRecord(serializedBytes: encoded)
    }

    /// Cancel, join, and release the native run. Idempotent.
    public func destroy() {
        handle.withLock { state in
            if let current = state.handle {
                rac_agent_run_destroy(current)
                state.handle = nil
            }
        }
    }

    public var isAlive: Bool {
        handle.withLock { $0.handle != nil }
    }

    private func withHandle(
        _ body: @Sendable (rac_handle_t) -> rac_result_t
    ) throws {
        let result: rac_result_t = try handle.withLock { state in
            guard let current = state.handle else {
                throw SDKException(
                    code: .invalidState,
                    message: "Workflow run has already been destroyed",
                    category: .internal
                )
            }
            return body(current)
        }
        guard result == RAC_SUCCESS else {
            throw WorkflowErrors.failure(op: "Workflow run call", rc: result)
        }
    }
}

/// The native handle is only read or cleared while the enclosing lock is held.
private struct WorkflowRunState: @unchecked Sendable {
    var handle: rac_handle_t?
}

// MARK: - Errors

private enum WorkflowErrors {
    static func failure(op: String, rc: rac_result_t) -> SDKException {
        var message = "\(op) failed"
        let description = String(cString: rac_error_message(rc))
        if !description.isEmpty {
            message += ": \(description)"
        }
        if let detail = rac_error_get_details() {
            let text = String(cString: detail)
            if !text.isEmpty {
                message += " (\(text))"
            }
        }
        return SDKException(code: .processingFailed, message: message, category: .internal)
    }
}

// MARK: - Host callbacks

/// Bridges the two node types commons delegates back to the host.
///
/// Both callbacks are invoked synchronously on a commons worker thread, so the
/// async Swift work below is bridged with a semaphore. That is the same
/// async-to-sync pattern the rest of the SDK uses against this C ABI.
private enum WorkflowHostBridge {

    private static let installed = OSAllocatedUnfairLock(initialState: false)

    static func installIfNeeded() {
        let shouldInstall = installed.withLock { flag -> Bool in
            if flag { return false }
            flag = true
            return true
        }
        guard shouldInstall else { return }

        var callbacks = rac_agent_host_callbacks_t()
        callbacks.abi_version = UInt32(RAC_AGENT_HOST_CALLBACKS_ABI_VERSION)
        callbacks.struct_size = MemoryLayout<rac_agent_host_callbacks_t>.size
        callbacks.invoke_tool = invokeToolTrampoline
        callbacks.evaluate_code = evaluateCodeTrampoline
        callbacks.user_data = nil

        let result = rac_agent_set_host_callbacks(&callbacks)
        if result != RAC_SUCCESS {
            SDKLogger(category: "Workflows").error(
                "Could not install workflow host callbacks: \(String(cString: rac_error_message(result)))"
            )
        }
    }

    private static let invokeToolTrampoline: @convention(c) (
        UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<rac_proto_buffer_t>?,
        UnsafeMutableRawPointer?
    ) -> rac_result_t = { bytes, size, outBuffer, _ in
        guard let bytes, let outBuffer else { return RAC_ERROR_INVALID_ARGUMENT }

        let payload = Data(bytes: bytes, count: size)
        guard let invocation = try? RAToolInvocation(serializedBytes: payload) else {
            return RAC_ERROR_DECODING_ERROR
        }

        // The C ABI is synchronous but the tool registry is an actor, so the
        // result travels back through a box rather than a captured var: an
        // inout capture across a Task is not Sendable.
        let outcome = ToolOutcomeBox()
        let semaphore = DispatchSemaphore(value: 0)
        let toolName = invocation.toolName
        let argumentsJson = invocation.argumentsJson

        Task {
            defer { semaphore.signal() }
            var call = RAToolCall()
            call.name = toolName
            call.argumentsJson = argumentsJson
            outcome.store(await RunAnywhere.executeTool(call))
        }
        semaphore.wait()

        var response = RAToolInvocationResult()
        if let result = outcome.value {
            if result.hasError {
                var error = RASDKError()
                error.message = result.error
                response.error = error
            } else {
                response.resultJson = result.resultJson
            }
        } else {
            var error = RASDKError()
            error.message = "Tool '\(toolName)' produced no result"
            response.error = error
        }

        return emit(response, into: outBuffer)
    }

    private static let evaluateCodeTrampoline: @convention(c) (
        UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<rac_proto_buffer_t>?,
        UnsafeMutableRawPointer?
    ) -> rac_result_t = { bytes, size, outBuffer, _ in
        guard let bytes, let outBuffer else { return RAC_ERROR_INVALID_ARGUMENT }

        let payload = Data(bytes: bytes, count: size)
        guard let invocation = try? RACodeInvocation(serializedBytes: payload) else {
            return RAC_ERROR_DECODING_ERROR
        }

        var response = RACodeInvocationResult()

        // A fresh context per node keeps one node's globals from leaking into
        // the next, and drops whatever the script allocated when it returns.
        guard let context = JSContext() else {
            var error = RASDKError()
            error.message = "Could not create a JavaScript context"
            response.error = error
            return emit(response, into: outBuffer)
        }

        var thrown: String?
        context.exceptionHandler = { _, exception in
            thrown = exception?.toString() ?? "unknown JavaScript error"
        }

        // The script sees the input items as `items` and returns a value; the
        // wrapper keeps user code from needing a specific function signature.
        let source = """
        (function() {
            var items = \(invocation.inputItemsJson);
            \(invocation.source)
        })()
        """

        let value = context.evaluateScript(source)

        if let thrown {
            var error = RASDKError()
            error.message = thrown
            response.error = error
            return emit(response, into: outBuffer)
        }

        guard let value, !value.isUndefined, !value.isNull else {
            response.outputItemsJson = "[]"
            return emit(response, into: outBuffer)
        }

        if let serialized = serializeJSValue(value, in: context) {
            response.outputItemsJson = serialized
        } else {
            var error = RASDKError()
            error.message = "Code node returned a value that is not JSON-serializable"
            response.error = error
        }
        return emit(response, into: outBuffer)
    }

    private static func serializeJSValue(_ value: JSValue, in context: JSContext) -> String? {
        guard let json = context.objectForKeyedSubscript("JSON"),
              let stringify = json.objectForKeyedSubscript("stringify"),
              let result = stringify.call(withArguments: [value]),
              !result.isUndefined else {
            return nil
        }
        return result.toString()
    }

    private static func emit<Message: SwiftProtobuf.Message>(
        _ message: Message,
        into buffer: UnsafeMutablePointer<rac_proto_buffer_t>
    ) -> rac_result_t {
        guard let encoded = try? message.serializedData() else {
            return RAC_ERROR_ENCODING_ERROR
        }
        return encoded.withUnsafeBytes { raw -> rac_result_t in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                return RAC_ERROR_ENCODING_ERROR
            }
            return rac_proto_buffer_copy(base, encoded.count, buffer)
        }
    }
}

// MARK: - Workflows capability

public extension RunAnywhere {

    /// Capability accessor for the workflow runner.
    static var workflows: Workflows { Workflows() }

    /// Stateless namespace. Every run returned by `run` owns its own native
    /// handle; this type keeps no mutable state.
    struct Workflows: Sendable {

        // swiftlint:disable:next strict_fileprivate
        fileprivate init() {}

        private func ensureReady() async throws {
            guard RunAnywhere.isReady else {
                throw SDKException(
                    code: .notInitialized,
                    message: "SDK not initialized",
                    category: .internal
                )
            }
            try await RunAnywhere.ensureServicesReady()
        }

        /// Store a workflow. Validated first, so an invalid document is
        /// rejected rather than written.
        public func save(_ document: RAWorkflowDocument) async throws {
            try await ensureReady()
            let encoded = try document.serializedData()
            let result = encoded.withUnsafeBytes { raw -> rac_result_t in
                rac_agent_workflow_save_proto(
                    raw.bindMemory(to: UInt8.self).baseAddress, encoded.count
                )
            }
            guard result == RAC_SUCCESS else {
                throw WorkflowErrors.failure(op: "rac_agent_workflow_save_proto", rc: result)
            }
        }

        public func load(id: String) async throws -> RAWorkflowDocument {
            try await ensureReady()
            var buffer = rac_proto_buffer_t()
            rac_proto_buffer_init(&buffer)
            defer { rac_proto_buffer_free(&buffer) }

            let result = id.withCString { rac_agent_workflow_load_proto($0, &buffer) }
            guard result == RAC_SUCCESS, let data = buffer.data else {
                throw WorkflowErrors.failure(op: "rac_agent_workflow_load_proto", rc: result)
            }
            return try RAWorkflowDocument(serializedBytes: Data(bytes: data, count: buffer.size))
        }

        /// Summaries of every stored workflow. An unreadable document is
        /// skipped rather than failing the listing.
        public func list() async throws -> [RAWorkflowSummary] {
            try await ensureReady()
            var buffer = rac_proto_buffer_t()
            rac_proto_buffer_init(&buffer)
            defer { rac_proto_buffer_free(&buffer) }

            let result = rac_agent_workflow_list_proto(&buffer)
            guard result == RAC_SUCCESS, let data = buffer.data else {
                throw WorkflowErrors.failure(op: "rac_agent_workflow_list_proto", rc: result)
            }
            let list = try RAWorkflowList(serializedBytes: Data(bytes: data, count: buffer.size))
            return list.workflows
        }

        /// Delete a workflow and its run records. Deleting an id that is not
        /// stored succeeds.
        public func delete(id: String) async throws {
            try await ensureReady()
            let result = id.withCString { rac_agent_workflow_delete($0) }
            guard result == RAC_SUCCESS else {
                throw WorkflowErrors.failure(op: "rac_agent_workflow_delete", rc: result)
            }
        }

        /// Check a document without storing it. An invalid document is a normal
        /// answer, returned in the result rather than thrown.
        public func validate(_ document: RAWorkflowDocument) async throws
            -> RAWorkflowValidationResult {
            try await ensureReady()
            let encoded = try document.serializedData()

            var buffer = rac_proto_buffer_t()
            rac_proto_buffer_init(&buffer)
            defer { rac_proto_buffer_free(&buffer) }

            let result = encoded.withUnsafeBytes { raw -> rac_result_t in
                rac_agent_workflow_validate_proto(
                    raw.bindMemory(to: UInt8.self).baseAddress, encoded.count, &buffer
                )
            }
            guard result == RAC_SUCCESS, let data = buffer.data else {
                throw WorkflowErrors.failure(op: "rac_agent_workflow_validate_proto", rc: result)
            }
            return try RAWorkflowValidationResult(
                serializedBytes: Data(bytes: data, count: buffer.size)
            )
        }

        /// Create a run for a stored workflow.
        ///
        /// The run comes back in the created state; call `start()` to execute
        /// it. Subscribe to `events` first if you want to see every transition.
        public func run(
            workflowID: String,
            initialItems: [RAWorkflowItem] = []
        ) async throws -> WorkflowRun {
            try await ensureReady()
            WorkflowHostBridge.installIfNeeded()

            var request = RAWorkflowRunRequest()
            request.workflowID = workflowID
            request.initialItems = initialItems
            let encoded = try request.serializedData()

            let box = WorkflowEventBox()
            let stream = AsyncStream<RAWorkflowRunEvent> { continuation in
                box.continuation = continuation
            }

            let context = Unmanaged.passRetained(box).toOpaque()
            var handle: rac_handle_t?
            let result = encoded.withUnsafeBytes { raw -> rac_result_t in
                rac_agent_run_create_proto(
                    raw.bindMemory(to: UInt8.self).baseAddress,
                    encoded.count,
                    { bytes, size, userData in
                        guard let bytes, let userData else { return }
                        let box = Unmanaged<WorkflowEventBox>.fromOpaque(userData)
                            .takeUnretainedValue()
                        if let event = try? RAWorkflowRunEvent(
                            serializedBytes: Data(bytes: bytes, count: size)
                        ) {
                            box.yield(event)
                        }
                    },
                    context,
                    &handle
                )
            }

            guard result == RAC_SUCCESS, let handle else {
                Unmanaged<WorkflowEventBox>.fromOpaque(context).release()
                throw WorkflowErrors.failure(op: "rac_agent_run_create_proto", rc: result)
            }

            box.onFinish = { Unmanaged<WorkflowEventBox>.fromOpaque(context).release() }
            return WorkflowRun(handle: handle, events: stream)
        }

        /// Load a persisted record for a run that has already finished.
        public func record(workflowID: String, runID: String) async throws -> RAWorkflowRunRecord {
            try await ensureReady()
            var buffer = rac_proto_buffer_t()
            rac_proto_buffer_init(&buffer)
            defer { rac_proto_buffer_free(&buffer) }

            let result = workflowID.withCString { workflow in
                runID.withCString { run in
                    rac_agent_run_record_load_proto(workflow, run, &buffer)
                }
            }
            guard result == RAC_SUCCESS, let data = buffer.data else {
                throw WorkflowErrors.failure(op: "rac_agent_run_record_load_proto", rc: result)
            }
            return try RAWorkflowRunRecord(serializedBytes: Data(bytes: data, count: buffer.size))
        }

        /// Every installed node pack. An unreadable pack is skipped rather than
        /// failing the listing.
        public func packs() async throws -> [RANodePack] {
            try await ensureReady()
            var buffer = rac_proto_buffer_t()
            rac_proto_buffer_init(&buffer)
            defer { rac_proto_buffer_free(&buffer) }

            let result = rac_agent_pack_list_proto(&buffer)
            guard result == RAC_SUCCESS, let data = buffer.data else {
                throw WorkflowErrors.failure(op: "rac_agent_pack_list_proto", rc: result)
            }
            let list = try RANodePackList(serializedBytes: Data(bytes: data, count: buffer.size))
            return list.packs
        }

        /// Install a node pack, replacing any pack already stored under its id.
        public func savePack(_ pack: RANodePack) async throws {
            try await ensureReady()
            let encoded = try pack.serializedData()
            let result = encoded.withUnsafeBytes { raw -> rac_result_t in
                rac_agent_pack_save_proto(
                    raw.bindMemory(to: UInt8.self).baseAddress, encoded.count
                )
            }
            guard result == RAC_SUCCESS else {
                throw WorkflowErrors.failure(op: "rac_agent_pack_save_proto", rc: result)
            }
        }

        public func loadPack(id: String) async throws -> RANodePack {
            try await ensureReady()
            var buffer = rac_proto_buffer_t()
            rac_proto_buffer_init(&buffer)
            defer { rac_proto_buffer_free(&buffer) }

            let result = id.withCString { rac_agent_pack_load_proto($0, &buffer) }
            guard result == RAC_SUCCESS, let data = buffer.data else {
                throw WorkflowErrors.failure(op: "rac_agent_pack_load_proto", rc: result)
            }
            return try RANodePack(serializedBytes: Data(bytes: data, count: buffer.size))
        }

        /// Uninstall a node pack. Deleting an id that is not installed succeeds.
        public func deletePack(id: String) async throws {
            try await ensureReady()
            let result = id.withCString { rac_agent_pack_delete($0) }
            guard result == RAC_SUCCESS else {
                throw WorkflowErrors.failure(op: "rac_agent_pack_delete", rc: result)
            }
        }

        /// Bundle the named workflows for sharing. Every pack they reference,
        /// transitively, is resolved and included by commons.
        public func exportBundle(workflowIDs: [String]) async throws -> RAWorkflowBundle {
            try await ensureReady()
            var request = RAWorkflowBundleExportRequest()
            request.workflowIds = workflowIDs
            let encoded = try request.serializedData()

            var buffer = rac_proto_buffer_t()
            rac_proto_buffer_init(&buffer)
            defer { rac_proto_buffer_free(&buffer) }

            let result = encoded.withUnsafeBytes { raw -> rac_result_t in
                rac_agent_bundle_export_proto(
                    raw.bindMemory(to: UInt8.self).baseAddress, encoded.count, &buffer
                )
            }
            guard result == RAC_SUCCESS, let data = buffer.data else {
                throw WorkflowErrors.failure(op: "rac_agent_bundle_export_proto", rc: result)
            }
            return try RAWorkflowBundle(serializedBytes: Data(bytes: data, count: buffer.size))
        }

        /// Install everything a bundle carries. A partial import is a normal
        /// answer: the per-item outcome is in the result, not thrown.
        public func importBundle(
            _ bundle: RAWorkflowBundle
        ) async throws -> RAWorkflowBundleImportResult {
            try await ensureReady()
            let encoded = try bundle.serializedData()

            var buffer = rac_proto_buffer_t()
            rac_proto_buffer_init(&buffer)
            defer { rac_proto_buffer_free(&buffer) }

            let result = encoded.withUnsafeBytes { raw -> rac_result_t in
                rac_agent_bundle_import_proto(
                    raw.bindMemory(to: UInt8.self).baseAddress, encoded.count, &buffer
                )
            }
            guard result == RAC_SUCCESS, let data = buffer.data else {
                throw WorkflowErrors.failure(op: "rac_agent_bundle_import_proto", rc: result)
            }
            return try RAWorkflowBundleImportResult(
                serializedBytes: Data(bytes: data, count: buffer.size)
            )
        }
    }
}

/// Carries one tool result from the async registry back to the synchronous C
/// callback that is blocked waiting on it.
private final class ToolOutcomeBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: RAToolResult?.none)

    func store(_ result: RAToolResult) {
        lock.withLock { $0 = result }
    }

    var value: RAToolResult? {
        lock.withLock { $0 }
    }
}

/// Carries the AsyncStream continuation across the C callback boundary.
///
/// Retained for the life of the run and released once the terminal event has
/// been delivered, because commons calls the event callback from a worker
/// thread that outlives the creating scope.
private final class WorkflowEventBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)

    var continuation: AsyncStream<RAWorkflowRunEvent>.Continuation?
    var onFinish: (() -> Void)?

    func yield(_ event: RAWorkflowRunEvent) {
        continuation?.yield(event)

        guard case .runFinished = event.event else { return }
        let alreadyFinished = lock.withLock { flag -> Bool in
            if flag { return true }
            flag = true
            return false
        }
        guard !alreadyFinished else { return }

        continuation?.finish()
        onFinish?()
    }
}
