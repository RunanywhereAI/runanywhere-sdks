//
//  URLSessionHttpTransport.swift
//  RunAnywhere SDK
//
//  Swift URLSession-backed adapter for the cross-SDK HTTP transport
//  vtable (`rac_http_transport_*`). Registering this adapter routes
//  every `rac_http_request_*` call through Apple's URLSession stack —
//  so iOS/macOS consumers inherit the system trust store, configured
//  proxies, HTTP/2, and App Transport Security for free instead of
//  going through the bundled libcurl.
//
//  The adapter fills `rac_http_response_t` with heap-allocated buffers
//  (malloc + strdup) matching the libcurl default so the C core can
//  free them uniformly via `rac_http_response_free` / `rac_free`.
//

import CRACommons
import Foundation
import os

// MARK: - Adapter

/// URLSession-backed HTTP transport adapter.
///
/// Registers a static `rac_http_transport_ops_t` vtable with the C core
/// so every `rac_http_request_send` / `_stream` / `_resume` call is
/// serviced by `URLSession` on iOS/macOS/tvOS/watchOS. Safe to call
/// `register()` multiple times — subsequent calls are no-ops.
public enum URLSessionHttpTransport {

    private static let logger = SDKLogger(category: "URLSessionHttpTransport")

    /// Registration state guard. `OSAllocatedUnfairLock` is used instead
    /// of `NSLock` per project rules.
    private static let registrationState =
        OSAllocatedUnfairLock<Bool>(initialState: false)

    /// Shared URLSession backing all `request_send` calls. `timeoutIntervalForRequest`
    /// is set to a generous 60 s default; per-request timeouts from
    /// `rac_http_request_t.timeout_ms` override this when > 0.
    ///
    /// `urlCache = nil` because the commons layer owns its own caching
    /// strategy (cache keys land in the model registry, not in URL
    /// responses).
    fileprivate static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpAdditionalHeaders = nil
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Streaming-task coordinator. One instance per streaming call;
    /// bridges `URLSessionDataDelegate` callbacks back to the C chunk
    /// callback. Keyed by `URLSessionTask.taskIdentifier`.
    fileprivate static let streamRegistry = StreamRegistry()

    /// Static vtable handed to `rac_http_transport_register`. It must
    /// outlive every registered request, so we store it as a mutable
    /// static rather than a stack value.
    ///
    /// NOTE: deliberately `nonisolated(unsafe)` — the struct is written
    /// exactly once in `register()` under `registrationState`, and the
    /// C core reads the function-pointer fields from arbitrary threads
    /// thereafter (pointer reads are atomic on all supported targets).
    nonisolated(unsafe) private static var ops = rac_http_transport_ops_t()

    // MARK: - Public entry point

    /// Install the URLSession adapter as the active HTTP transport.
    /// Idempotent — subsequent calls are no-ops.
    public static func register() {
        let alreadyRegistered = registrationState.withLock { registered -> Bool in
            if registered { return true }
            registered = true
            return false
        }
        guard !alreadyRegistered else {
            logger.debug("URLSession HTTP transport already registered (skipping)")
            return
        }

        ops.request_send = URLSessionHttpTransport.cRequestSend
        ops.request_stream = URLSessionHttpTransport.cRequestStream
        ops.request_resume = URLSessionHttpTransport.cRequestResume
        // `init` is a reserved Swift identifier — must be backticked.
        ops.`init` = nil
        ops.destroy = nil

        let result = rac_http_transport_register(&ops, nil)
        if result == RAC_SUCCESS {
            logger.info("URLSession HTTP transport registered")
        } else {
            // Roll back flag so register() can be retried
            registrationState.withLock { $0 = false }
            logger.error("Failed to register URLSession HTTP transport (rc=\(result))")
        }
    }

    /// Restore the default libcurl transport. Primarily useful in tests.
    public static func unregister() {
        let wasRegistered = registrationState.withLock { registered -> Bool in
            let previous = registered
            registered = false
            return previous
        }
        guard wasRegistered else { return }
        _ = rac_http_transport_register(nil, nil)
        logger.info("URLSession HTTP transport unregistered")
    }
}

// MARK: - C callbacks

extension URLSessionHttpTransport {

    /// `request_send` vtable slot — blocking single-shot request.
    static let cRequestSend: @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<rac_http_request_t>?,
        UnsafeMutablePointer<rac_http_response_t>?
    ) -> rac_result_t = { _, reqPtr, outRespPtr in
        guard let reqPtr = reqPtr, let outRespPtr = outRespPtr else {
            return RAC_ERROR_INVALID_ARGUMENT
        }
        return RequestExecutor.send(req: reqPtr.pointee, out: outRespPtr)
    }

    /// `request_stream` vtable slot — streams body via chunk callback.
    static let cRequestStream: @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<rac_http_request_t>?,
        rac_http_body_chunk_fn?,
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<rac_http_response_t>?
    ) -> rac_result_t = { _, reqPtr, cb, cbUserData, outRespPtr in
        guard let reqPtr = reqPtr, let cb = cb, let outRespPtr = outRespPtr else {
            return RAC_ERROR_INVALID_ARGUMENT
        }
        return RequestExecutor.stream(
            req: reqPtr.pointee,
            chunkFn: cb,
            chunkUserData: cbUserData,
            out: outRespPtr,
            resumeFromByte: 0
        )
    }

    /// `request_resume` vtable slot — identical to `request_stream` but
    /// attaches a `Range: bytes=N-` header before dispatching.
    static let cRequestResume: @convention(c) (
        UnsafeMutableRawPointer?,
        UnsafePointer<rac_http_request_t>?,
        UInt64,
        rac_http_body_chunk_fn?,
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<rac_http_response_t>?
    ) -> rac_result_t = { _, reqPtr, resumeFromByte, cb, cbUserData, outRespPtr in
        guard let reqPtr = reqPtr, let cb = cb, let outRespPtr = outRespPtr else {
            return RAC_ERROR_INVALID_ARGUMENT
        }
        return RequestExecutor.stream(
            req: reqPtr.pointee,
            chunkFn: cb,
            chunkUserData: cbUserData,
            out: outRespPtr,
            resumeFromByte: resumeFromByte
        )
    }
}

// MARK: - Request snapshot

/// Caller-owned copy of a `rac_http_request_t`. The incoming C struct
/// is valid only for the lifetime of the adapter call, so we materialize
/// everything we need into Swift types up-front.
private struct RequestSnapshot {
    let method: String
    let url: URL
    let headers: [(name: String, value: String)]
    let body: Data?
    let timeoutMs: Int32
    let followRedirects: Bool

    init?(_ req: rac_http_request_t) {
        guard let methodPtr = req.method, let urlPtr = req.url else {
            return nil
        }
        let methodString = String(cString: methodPtr)
        let urlString = String(cString: urlPtr)
        guard let url = URL(string: urlString) else {
            return nil
        }

        var headerList: [(String, String)] = []
        if let headersPtr = req.headers, req.header_count > 0 {
            for index in 0..<req.header_count {
                let header = headersPtr[index]
                guard let namePtr = header.name, let valuePtr = header.value else { continue }
                headerList.append((String(cString: namePtr), String(cString: valuePtr)))
            }
        }

        var bodyData: Data?
        if let bytesPtr = req.body_bytes, req.body_len > 0 {
            bodyData = Data(bytes: bytesPtr, count: req.body_len)
        }

        self.method = methodString
        self.url = url
        self.headers = headerList
        self.body = bodyData
        self.timeoutMs = req.timeout_ms
        self.followRedirects = (req.follow_redirects == RAC_TRUE)
    }

    func makeURLRequest(additionalRangeFromByte: UInt64 = 0) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let body = body, !body.isEmpty {
            request.httpBody = body
        }
        if timeoutMs > 0 {
            request.timeoutInterval = TimeInterval(timeoutMs) / 1000.0
        }
        if additionalRangeFromByte > 0 {
            request.setValue("bytes=\(additionalRangeFromByte)-", forHTTPHeaderField: "Range")
        }
        return request
    }
}

// MARK: - Response allocation helpers

/// Fills `out_resp` with heap-allocated buffers that the C core can
/// release via `rac_http_response_free` / `rac_free`. All allocations
/// use `malloc` / `strdup` to match the libcurl default's ownership
/// contract.
private enum ResponseWriter {

    static func write(
        status: Int32,
        bodyBytes: Data?,
        headers: [(name: String, value: String)],
        redirectedURL: String?,
        elapsedMs: UInt64,
        into out: UnsafeMutablePointer<rac_http_response_t>
    ) {
        // Zero the struct first so any early-return path leaves a
        // well-defined state.
        out.pointee = rac_http_response_t()
        out.pointee.status = status
        out.pointee.elapsed_ms = elapsedMs

        // Body
        if let body = bodyBytes, !body.isEmpty {
            if let buffer = malloc(body.count) {
                let typed = buffer.assumingMemoryBound(to: UInt8.self)
                body.copyBytes(to: UnsafeMutableBufferPointer(start: typed, count: body.count))
                out.pointee.body_bytes = typed
                out.pointee.body_len = body.count
            }
        }

        // Headers
        if !headers.isEmpty {
            let count = headers.count
            let byteCount = MemoryLayout<rac_http_header_kv_t>.stride * count
            if let buffer = malloc(byteCount) {
                let typed = buffer.assumingMemoryBound(to: rac_http_header_kv_t.self)
                for (index, header) in headers.enumerated() {
                    let namePtr = strdup(header.name)
                    let valuePtr = strdup(header.value)
                    typed[index] = rac_http_header_kv_t(
                        name: UnsafePointer(namePtr),
                        value: UnsafePointer(valuePtr)
                    )
                }
                out.pointee.headers = typed
                out.pointee.header_count = count
            }
        }

        // Redirected URL (only populated when different from the
        // request URL — matches libcurl semantics)
        if let redirected = redirectedURL {
            out.pointee.redirected_url = strdup(redirected)
        }
    }

    static func extractHeaders(from httpResponse: HTTPURLResponse) -> [(name: String, value: String)] {
        httpResponse.allHeaderFields.compactMap { key, value in
            guard let name = key as? String else { return nil }
            return (name, String(describing: value))
        }
    }
}

// MARK: - RequestExecutor

/// Core logic that turns a `RequestSnapshot` into a URLSession call,
/// blocks until completion, and writes the result back into the C
/// response struct. Two entry points: `send` (buffered body) and
/// `stream` (per-chunk callback).
private enum RequestExecutor {

    static func send(
        req: rac_http_request_t,
        out: UnsafeMutablePointer<rac_http_response_t>
    ) -> rac_result_t {
        guard let snapshot = RequestSnapshot(req) else {
            return RAC_ERROR_INVALID_ARGUMENT
        }

        let urlRequest = snapshot.makeURLRequest()
        let startTime = DispatchTime.now()

        let semaphore = DispatchSemaphore(value: 0)
        var capturedData: Data?
        var capturedResponse: URLResponse?
        var capturedError: Error?

        let task = URLSessionHttpTransport.sharedSession.dataTask(with: urlRequest) { data, response, error in
            capturedData = data
            capturedResponse = response
            capturedError = error
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        let elapsedMs = elapsedMilliseconds(since: startTime)

        if let error = capturedError {
            return mapTransportError(error)
        }

        guard let httpResponse = capturedResponse as? HTTPURLResponse else {
            return RAC_ERROR_NETWORK_ERROR
        }

        let headers = ResponseWriter.extractHeaders(from: httpResponse)
        let finalURL = httpResponse.url?.absoluteString
        let redirected = (finalURL != nil && finalURL != snapshot.url.absoluteString)
            ? finalURL
            : nil

        ResponseWriter.write(
            status: Int32(httpResponse.statusCode),
            bodyBytes: capturedData,
            headers: headers,
            redirectedURL: redirected,
            elapsedMs: elapsedMs,
            into: out
        )
        return RAC_SUCCESS
    }

    static func stream(
        req: rac_http_request_t,
        chunkFn: @escaping rac_http_body_chunk_fn,
        chunkUserData: UnsafeMutableRawPointer?,
        out: UnsafeMutablePointer<rac_http_response_t>,
        resumeFromByte: UInt64
    ) -> rac_result_t {
        guard let snapshot = RequestSnapshot(req) else {
            return RAC_ERROR_INVALID_ARGUMENT
        }

        let urlRequest = snapshot.makeURLRequest(additionalRangeFromByte: resumeFromByte)
        let startTime = DispatchTime.now()

        // Dedicated session per streaming call so the delegate lifetime is
        // bounded and there are no stray retain cycles with the shared
        // session.
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = snapshot.timeoutMs > 0
            ? TimeInterval(snapshot.timeoutMs) / 1000.0
            : 60
        config.timeoutIntervalForResource = max(config.timeoutIntervalForRequest, 600)
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let delegate = StreamDelegate(chunkFn: chunkFn, chunkUserData: chunkUserData)
        let session = URLSession(
            configuration: config,
            delegate: delegate,
            delegateQueue: nil
        )

        let task = session.dataTask(with: urlRequest)
        delegate.taskIdentifier = task.taskIdentifier
        URLSessionHttpTransport.streamRegistry.insert(taskId: task.taskIdentifier, delegate: delegate)

        task.resume()
        delegate.completion.wait()

        // Tear down the per-call session so URLSession releases the
        // delegate reference and flushes any pending sockets.
        session.finishTasksAndInvalidate()
        URLSessionHttpTransport.streamRegistry.remove(taskId: task.taskIdentifier)

        let elapsedMs = elapsedMilliseconds(since: startTime)

        if delegate.cancelled {
            return RAC_ERROR_CANCELLED
        }

        if let error = delegate.error {
            return mapTransportError(error)
        }

        guard let httpResponse = delegate.response else {
            return RAC_ERROR_NETWORK_ERROR
        }

        let headers = ResponseWriter.extractHeaders(from: httpResponse)
        let finalURL = httpResponse.url?.absoluteString
        let redirected = (finalURL != nil && finalURL != snapshot.url.absoluteString)
            ? finalURL
            : nil

        // Streaming responses never populate body_bytes (per the
        // `rac_http_request_stream` contract).
        ResponseWriter.write(
            status: Int32(httpResponse.statusCode),
            bodyBytes: nil,
            headers: headers,
            redirectedURL: redirected,
            elapsedMs: elapsedMs,
            into: out
        )
        return RAC_SUCCESS
    }

    // MARK: - Helpers

    private static func elapsedMilliseconds(since start: DispatchTime) -> UInt64 {
        let deltaNanos = DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds
        return deltaNanos / 1_000_000
    }

    private static func mapTransportError(_ error: Error) -> rac_result_t {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return RAC_ERROR_NETWORK_ERROR
        }
        switch nsError.code {
        case NSURLErrorTimedOut:
            return RAC_ERROR_TIMEOUT
        case NSURLErrorCancelled:
            return RAC_ERROR_CANCELLED
        default:
            return RAC_ERROR_NETWORK_ERROR
        }
    }
}

// MARK: - Streaming infrastructure

/// Lightweight thread-safe map from task identifier → delegate. Used
/// only to keep a strong reference to the delegate while URLSession is
/// firing callbacks; lookups during teardown remove the entry.
private final class StreamRegistry: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<[Int: StreamDelegate]>(initialState: [:])

    func insert(taskId: Int, delegate: StreamDelegate) {
        lock.withLock { $0[taskId] = delegate }
    }

    func remove(taskId: Int) {
        lock.withLock { _ = $0.removeValue(forKey: taskId) }
    }
}

/// URLSession delegate that proxies `didReceive data` into the C chunk
/// callback and signals a `DispatchSemaphore` on completion so the
/// synchronous C call can return.
private final class StreamDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {

    private let chunkFn: rac_http_body_chunk_fn
    private let chunkUserData: UnsafeMutableRawPointer?
    let completion = DispatchSemaphore(value: 0)

    // Populated on the delegate queue; read on the caller thread after
    // `completion` is signalled — no explicit lock needed because the
    // semaphore establishes the happens-before edge.
    var taskIdentifier: Int = 0
    var response: HTTPURLResponse?
    var totalBytesReceived: UInt64 = 0
    var contentLength: UInt64 = 0
    var cancelled: Bool = false
    var error: Error?

    init(
        chunkFn: @escaping rac_http_body_chunk_fn,
        chunkUserData: UnsafeMutableRawPointer?
    ) {
        self.chunkFn = chunkFn
        self.chunkUserData = chunkUserData
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let httpResponse = response as? HTTPURLResponse {
            self.response = httpResponse
            if httpResponse.expectedContentLength > 0 {
                self.contentLength = UInt64(httpResponse.expectedContentLength)
            }
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard !cancelled else { return }

        let chunkFn = self.chunkFn
        let chunkUserData = self.chunkUserData
        // Pull outside closure so we can update totals after the call.
        var shouldContinue = true
        let written = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> UInt64 in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }
            self.totalBytesReceived &+= UInt64(data.count)
            let boolResult = chunkFn(
                base,
                data.count,
                self.totalBytesReceived,
                self.contentLength,
                chunkUserData
            )
            shouldContinue = (boolResult == RAC_TRUE)
            return self.totalBytesReceived
        }
        _ = written

        if !shouldContinue {
            cancelled = true
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            // `cancelled` was already set if we initiated the abort; in
            // that case the NSURLErrorCancelled is expected.
            if !cancelled {
                self.error = error
            }
        }
        completion.signal()
    }
}
