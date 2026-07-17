//
//  CppBridge+RAG.swift
//  RunAnywhere SDK
//
//  RAG component bridge - manages C++ RAG pipeline lifecycle
//

import CRACommons
import Foundation
import SwiftProtobuf

// MARK: - RAG streaming ABI

/// Typed streaming ABI for `rac_rag_query_stream_proto`: takes a session handle
/// plus a serialized `RAGQueryOptions` and emits serialized `RAGStreamEvent`s
/// (TOKEN* → terminal COMPLETED/ERROR). The control callback returns
/// `rac_bool_t` — RAC_FALSE stops generation early (backpressure). Consumers
/// that break the stream (or cancel the owning task) stop generation
/// cooperatively via this return; `RAGCancelProtoABI` provides the explicit,
/// session-scoped imperative cancel used by `RunAnywhere.ragCancelQuery()`.
private enum RAGStreamProtoABI {
    typealias StreamCallback = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutableRawPointer?
    ) -> rac_bool_t
    typealias Stream = @convention(c) (
        rac_handle_t?,
        UnsafePointer<UInt8>?,
        Int,
        StreamCallback?,
        UnsafeMutableRawPointer?
    ) -> rac_result_t

    static let streamName = "rac_rag_query_stream_proto"
    static let stream = NativeProtoABI.load(streamName, as: Stream.self)
}

/// Session-scoped cancel ABI for `rac_rag_cancel_proto`: requests cancellation
/// of the query currently running on a RAG session. The active unary/streaming
/// run ends with an ERROR event carrying the cancellation status. Loaded
/// dynamically (RAG is a backend-conditional feature); `nil` when RAG is not
/// linked, in which case cancellation falls back to the cooperative path.
private enum RAGCancelProtoABI {
    typealias Cancel = @convention(c) (rac_handle_t?) -> rac_result_t

    static let cancelName = "rac_rag_cancel_proto"
    static let cancel = NativeProtoABI.load(cancelName, as: Cancel.self)
}

/// Retained RAG stream context released by the detached worker after the
/// synchronous native stream call returns.
private struct RAGStreamContextPointer: @unchecked Sendable {
    let rawValue: UnsafeMutableRawPointer
}

/// Sendable box for the opaque session handle so it can cross into the detached
/// worker without tripping Swift 6 strict-concurrency checks.
private struct RAGSessionHandleBox: @unchecked Sendable {
    let handle: rac_handle_t?
}

// MARK: - RAG Pipeline Bridge

extension CppBridge {

    /// RAG pipeline manager
    /// Provides thread-safe access to the C++ RAG pipeline
    public actor RAG {

        /// Shared RAG pipeline instance
        public static let shared = RAG()

        private var protoSession: rac_handle_t?
        private let logger = SDKLogger(category: "CppBridge.RAG")

        private init() {}

        // MARK: - Pipeline Lifecycle

        /// Check if pipeline is created
        public var isCreated: Bool { protoSession != nil }

        /// Destroy the pipeline
        public func destroy() {
            if let protoSession {
                destroyRAGProtoSessionIfAvailable(protoSession)
                self.protoSession = nil
                logger.debug("RAG proto session destroyed")
            }
        }

        /// Request cancellation of the query currently running on this session.
        /// Session-scoped via `rac_rag_cancel_proto`; the active run ends with an
        /// ERROR event. No-op when no session exists or RAG is not linked (the
        /// stream's cooperative backpressure path still applies).
        public func cancelActiveQuery() {
            guard let protoSession else { return }
            guard let cancel = RAGCancelProtoABI.cancel else {
                logger.debug("rac_rag_cancel_proto unavailable; relying on cooperative cancellation")
                return
            }
            let rc = cancel(protoSession)
            if rc != RAC_SUCCESS {
                logger.warning("rac_rag_cancel_proto failed: \(rc)")
            }
        }

        private func setProtoSession(_ session: rac_handle_t) {
            if let existing = protoSession {
                destroyRAGProtoSessionIfAvailable(existing)
            }
            protoSession = session
            logger.debug("RAG proto session created")
        }

        private func requireProtoSession() throws -> rac_handle_t {
            guard let protoSession else {
                throw SDKException(code: .notInitialized, message: "RAG proto session not created", category: .component)
            }
            return protoSession
        }

        func replacePipeline(_ config: RARAGConfiguration) throws {
            setProtoSession(try createPipeline(config))
        }

        func ingest(_ document: RARAGDocument) throws -> RARAGStatistics {
            try ingest(handle: requireProtoSession(), document)
        }

        func ingest(_ documents: [RARAGDocument]) throws {
            let session = try requireProtoSession()
            for document in documents {
                _ = try ingest(handle: session, document)
            }
        }

        func statistics() throws -> RARAGStatistics {
            try statsProto(handle: requireProtoSession())
        }

        func clearDocuments() throws -> RARAGStatistics {
            try clearProto(handle: requireProtoSession())
        }

        func runQuery(_ options: RARAGQueryOptions) throws -> RARAGResult {
            try query(handle: requireProtoSession(), options)
        }

        /// Streaming query. Emits a `RARAGStreamEvent` per generated token
        /// (kind = TOKEN) as the answer is produced, then a terminal COMPLETED
        /// carrying the full `RARAGResult`, or an ERROR event. Mirrors the shared
        /// typed stream contract used by LLM/VLM. Breaking out of the stream (or
        /// cancelling the owning task) stops native generation via the
        /// backpressure return, so callers do not need a wall-clock timeout.
        func runQueryStream(_ options: RARAGQueryOptions) throws -> AsyncStream<RARAGStreamEvent> {
            let handleBox = RAGSessionHandleBox(handle: try requireProtoSession())
            _ = try NativeProtoABI.require(RAGStreamProtoABI.stream, named: RAGStreamProtoABI.streamName)
            let requestData = try options.serializedData()
            return AsyncStream { continuation in
                let context = ProtoStreamContext<RARAGStreamEvent>(
                    continuation: continuation,
                    category: "CppBridge.RAG.ProtoStream"
                )
                let contextPtr = RAGStreamContextPointer(
                    rawValue: Unmanaged.passRetained(context).toOpaque()
                )

                // RAG has no native per-query cancel symbol; cancellation is
                // cooperative — flip the flag so the stream callback returns
                // RAC_FALSE and the native loop stops on its next token.
                continuation.onTermination = { @Sendable termination in
                    switch termination {
                    case .cancelled:
                        context.cancel()
                    case .finished:
                        break
                    @unknown default:
                        break
                    }
                }

                Task.detached {
                    guard let stream = RAGStreamProtoABI.stream else {
                        Unmanaged<ProtoStreamContext<RARAGStreamEvent>>
                            .fromOpaque(contextPtr.rawValue)
                            .release()
                        continuation.finish()
                        return
                    }
                    let rc = await withTaskCancellationHandler {
                        requestData.withUnsafeBytes { requestRaw in
                            stream(
                                handleBox.handle,
                                requestRaw.bindMemory(to: UInt8.self).baseAddress,
                                requestRaw.count,
                                { bytes, size, userData in
                                    guard let userData else { return RAC_FALSE }
                                    let ctx = Unmanaged<ProtoStreamContext<RARAGStreamEvent>>
                                        .fromOpaque(userData)
                                        .takeUnretainedValue()
                                    if ctx.isCancelled { return RAC_FALSE }
                                    ctx.yield(bytes: bytes, size: size)
                                    return ctx.isCancelled ? RAC_FALSE : RAC_TRUE
                                },
                                contextPtr.rawValue
                            )
                        }
                    } onCancel: {
                        context.cancel()
                    }
                    Unmanaged<ProtoStreamContext<RARAGStreamEvent>>
                        .fromOpaque(contextPtr.rawValue)
                        .release()
                    if rc != RAC_SUCCESS, !context.isCancelled {
                        SDKLogger(category: "CppBridge.RAG.ProtoStream")
                            .warning("RAG proto stream failed: \(rc)")
                    }
                    continuation.finish()
                }
            }
        }
    }
}
