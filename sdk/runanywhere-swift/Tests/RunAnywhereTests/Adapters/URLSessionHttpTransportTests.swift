//
//  URLSessionHttpTransportTests.swift
//  RunAnywhere SDK
//
//  Coverage for `URLSessionHttpTransport` — the URLSession-backed adapter
//  that replaces libcurl on Apple and services every `rac_http_request_*`
//  C ABI call (model download, catalog fetch, analytics). The Web SDK's
//  `FetchHttpTransport.test.ts` is the parity reference; this suite mirrors
//  its contracts against the real C router so a vtable regression fails
//  here instead of at first-run-download time:
//
//   1. `register()` is idempotent — the C router reports a transport after
//      the first call and a second call leaves it installed (no re-register
//      side effects). `unregister()` clears it.
//   2. `rac_http_request_send` round-trips status + headers + body through
//      a stubbed `URLProtocol` (no network).
//   3. `rac_http_request_stream` cancel: a chunk callback returning
//      `RAC_FALSE` mid-stream propagates `RAC_ERROR_CANCELLED`.
//   4. `rac_http_request_resume` attaches the canonical `Range: bytes=N-`
//      header for the requested resume offset.
//   5. Range-honored disclosure: a 206 response sets `X-RAC-Range-Honored:
//      true`, a 200 (server ignored the range) sets it to `false`.
//
//  All requests are intercepted by `StubURLProtocol` so the suite never
//  touches the network. The streaming / resume tests inject the stub via
//  `register(streamingSession:)`; the send test relies on the global
//  `URLProtocol.registerClass(_:)` hook the shared session inherits.
//

import CRACommons
import Foundation
import XCTest

@testable import RunAnywhere

final class URLSessionHttpTransportTests: XCTestCase {

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(StubURLProtocol.self)
    }

    override func tearDown() {
        StubURLProtocol.reset()
        URLProtocol.unregisterClass(StubURLProtocol.self)
        URLSessionHttpTransport.unregister()
        super.tearDown()
    }

    // MARK: - Test 1: register() idempotency + unregister()

    func testRegisterIsIdempotent() {
        // Start from a clean slate regardless of prior suite ordering.
        URLSessionHttpTransport.unregister()
        XCTAssertEqual(
            rac_http_transport_is_registered(),
            RAC_FALSE,
            "precondition: no transport installed before register()"
        )

        URLSessionHttpTransport.register()
        XCTAssertEqual(
            rac_http_transport_is_registered(),
            RAC_TRUE,
            "register() must install the transport vtable"
        )

        // Second call is a no-op; the transport stays installed.
        URLSessionHttpTransport.register()
        XCTAssertEqual(
            rac_http_transport_is_registered(),
            RAC_TRUE,
            "a redundant register() must leave the transport installed"
        )

        URLSessionHttpTransport.unregister()
        XCTAssertEqual(
            rac_http_transport_is_registered(),
            RAC_FALSE,
            "unregister() must clear the transport"
        )
    }

    // MARK: - Test 2: request_send round-trip

    func testRequestSendRoundTrip() throws {
        let bodyText = "hello-runanywhere"
        StubURLProtocol.responder = { _ in
            StubResponse(
                statusCode: 200,
                headers: ["X-Echo": "pong", "Content-Type": "text/plain"],
                body: Data(bodyText.utf8)
            )
        }

        URLSessionHttpTransport.register()

        var response = rac_http_response_t()
        let rc = withRequest(method: "GET", url: "https://example.test/ping") { reqPtr in
            rac_http_request_send(nil, reqPtr, &response)
        }
        defer { rac_http_response_free(&response) }

        XCTAssertEqual(rc, RAC_SUCCESS, "send must succeed for a stubbed 200 response")
        XCTAssertEqual(response.status, 200)

        let returnedBody = response.body_bytes.map { Data(bytes: $0, count: response.body_len) }
        XCTAssertEqual(returnedBody, Data(bodyText.utf8), "body bytes must round-trip verbatim")

        let headers = Self.headers(from: response)
        XCTAssertEqual(headers["X-Echo"], "pong", "response headers must be surfaced to the C core")
    }

    // MARK: - Test 3: stream cancel propagates RAC_ERROR_CANCELLED

    func testStreamCancelPropagatesCancelled() throws {
        // 256 KiB delivered in 64 KiB slices so the callback fires more than
        // once and can request cancellation mid-stream.
        let chunk = Data(repeating: 0xAB, count: 64 * 1024)
        StubURLProtocol.responder = { _ in
            StubResponse(statusCode: 200, headers: [:], body: chunk, chunkCount: 4)
        }
        installStubStreamingSession()

        // Callback returns RAC_FALSE on the first chunk to trigger cancel.
        let sink = ChunkSink(cancelAtCall: 1)
        var response = rac_http_response_t()
        let rc = withRequest(method: "GET", url: "https://example.test/model.gguf") { reqPtr in
            rac_http_request_stream(nil, reqPtr, ChunkSink.cCallback, sink.userData, &response)
        }
        defer { rac_http_response_free(&response) }

        XCTAssertEqual(rc, RAC_ERROR_CANCELLED, "a chunk callback returning RAC_FALSE must cancel")
        XCTAssertGreaterThanOrEqual(sink.callCount, 1, "the callback must have fired before cancel")
    }

    // MARK: - Test 4: resume attaches the canonical Range header

    func testResumeAttachesRangeHeader() throws {
        let captured = CapturedRequestBox()
        StubURLProtocol.responder = { request in
            captured.value = request
            // 206 Partial Content — the server honored the range.
            return StubResponse(statusCode: 206, headers: [:], body: Data([0x01, 0x02]))
        }
        installStubStreamingSession()

        let resumeFrom: UInt64 = 4096
        let sink = ChunkSink(cancelAtCall: nil)
        var response = rac_http_response_t()
        let rc = withRequest(method: "GET", url: "https://example.test/model.gguf") { reqPtr in
            rac_http_request_resume(
                nil,
                reqPtr,
                resumeFrom,
                ChunkSink.cCallback,
                sink.userData,
                &response
            )
        }
        defer { rac_http_response_free(&response) }

        XCTAssertEqual(rc, RAC_SUCCESS, "resume must succeed for a stubbed 206 response")
        let rangeHeader = captured.value?.value(forHTTPHeaderField: "Range")
        XCTAssertEqual(
            rangeHeader,
            "bytes=\(resumeFrom)-",
            "resume must attach the canonical open-ended Range header"
        )
    }

    // MARK: - Test 5: X-RAC-Range-Honored disclosure (206 vs 200)

    func testRangeHonoredDisclosure() throws {
        installStubStreamingSession()
        let resumeFrom: UInt64 = 1024

        // 206 → honored == true
        StubURLProtocol.responder = { _ in
            StubResponse(statusCode: 206, headers: [:], body: Data([0xFF]))
        }
        let honoredSink = ChunkSink(cancelAtCall: nil)
        var honoredResponse = rac_http_response_t()
        _ = withRequest(method: "GET", url: "https://example.test/partial") { reqPtr in
            rac_http_request_resume(
                nil,
                reqPtr,
                resumeFrom,
                ChunkSink.cCallback,
                honoredSink.userData,
                &honoredResponse
            )
        }
        defer { rac_http_response_free(&honoredResponse) }
        XCTAssertEqual(
            Self.headers(from: honoredResponse)["X-RAC-Range-Honored"],
            "true",
            "a 206 response must mark the range as honored"
        )

        // 200 → server ignored the range → honored == false
        StubURLProtocol.responder = { _ in
            StubResponse(statusCode: 200, headers: [:], body: Data([0xFF]))
        }
        let ignoredSink = ChunkSink(cancelAtCall: nil)
        var ignoredResponse = rac_http_response_t()
        _ = withRequest(method: "GET", url: "https://example.test/full") { reqPtr in
            rac_http_request_resume(
                nil,
                reqPtr,
                resumeFrom,
                ChunkSink.cCallback,
                ignoredSink.userData,
                &ignoredResponse
            )
        }
        defer { rac_http_response_free(&ignoredResponse) }
        XCTAssertEqual(
            Self.headers(from: ignoredResponse)["X-RAC-Range-Honored"],
            "false",
            "a 200 response to a ranged request must mark the range as NOT honored"
        )
    }

    // MARK: - Helpers

    /// Install the stub `URLProtocol` as the streaming session so resume /
    /// stream calls route through it instead of building a per-call session
    /// that hits the network.
    private func installStubStreamingSession() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        URLSessionHttpTransport.register(streamingSession: URLSession(configuration: config))
        URLSessionHttpTransport.register()
    }

    /// Materialize a C `rac_http_request_t` whose `method` / `url` C strings
    /// outlive the closure, then run `body` with a pointer to it.
    private func withRequest(
        method: String,
        url: String,
        _ body: (UnsafePointer<rac_http_request_t>) -> rac_result_t
    ) -> rac_result_t {
        method.withCString { methodPtr in
            url.withCString { urlPtr in
                var request = rac_http_request_t()
                request.method = methodPtr
                request.url = urlPtr
                return withUnsafePointer(to: &request) { body($0) }
            }
        }
    }

    /// Decode the C response header array into a Swift dictionary.
    private static func headers(from response: rac_http_response_t) -> [String: String] {
        guard let base = response.headers, response.header_count > 0 else { return [:] }
        var result: [String: String] = [:]
        for index in 0..<response.header_count {
            let kv = base[index]
            guard let namePtr = kv.name, let valuePtr = kv.value else { continue }
            result[String(cString: namePtr)] = String(cString: valuePtr)
        }
        return result
    }
}

// MARK: - Chunk callback sink

/// Bridges the C `rac_http_body_chunk_fn` back into a counter the test can
/// assert on. `cCallback` recovers the instance from `user_data` and
/// returns `RAC_FALSE` once `callCount` reaches `cancelAtCall`.
private final class ChunkSink {
    private(set) var callCount = 0
    private let cancelAtCall: Int?

    init(cancelAtCall: Int?) {
        self.cancelAtCall = cancelAtCall
    }

    var userData: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    func receive() -> rac_bool_t {
        callCount += 1
        if let cancelAt = cancelAtCall, callCount >= cancelAt {
            return RAC_FALSE
        }
        return RAC_TRUE
    }

    static let cCallback: rac_http_body_chunk_fn = { _, _, _, _, userData in
        guard let userData = userData else { return RAC_TRUE }
        let sink = Unmanaged<ChunkSink>.fromOpaque(userData).takeUnretainedValue()
        return sink.receive()
    }
}

/// Holds a captured `URLRequest` so the resume test can inspect the headers
/// the transport attached. A class so the `URLProtocol` responder closure
/// can write back into it.
private final class CapturedRequestBox: @unchecked Sendable {
    var value: URLRequest?
}

// MARK: - Stub URLProtocol

/// Fixed response definition handed back by the stub.
private struct StubResponse {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
    /// Number of `didLoad(_:)` slices the body is delivered in (>=1). Lets
    /// the cancel test drive multiple chunk callbacks.
    var chunkCount: Int = 1
}

/// In-process `URLProtocol` that answers every request from a configurable
/// closure — no sockets, no network. Mirrors the role of the `XHRStub` in
/// the Web SDK's `FetchHttpTransport.test.ts`.
private final class StubURLProtocol: URLProtocol {

    /// Builds the canned response for an intercepted request.
    nonisolated(unsafe) static var responder: ((URLRequest) -> StubResponse)?

    static func reset() {
        responder = nil
    }

    // `class` (not `static`) is required: these override URLProtocol's
    // overridable class methods, which `static` cannot do.
    override class func canInit(with request: URLRequest) -> Bool { true } // swiftlint:disable:this static_over_final_class

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request } // swiftlint:disable:this static_over_final_class

    override func startLoading() {
        guard let responder = StubURLProtocol.responder,
              let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        let stub = responder(request)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        let chunkCount = max(1, stub.chunkCount)
        if stub.body.isEmpty {
            // No body chunks to deliver.
        } else {
            let sliceSize = max(1, stub.body.count / chunkCount)
            var offset = 0
            while offset < stub.body.count {
                let end = min(offset + sliceSize, stub.body.count)
                client?.urlProtocol(self, didLoad: stub.body.subdata(in: offset..<end))
                offset = end
            }
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        // Cancellation surfaces through URLSession as NSURLErrorCancelled;
        // nothing to tear down for the in-memory stub.
    }
}
