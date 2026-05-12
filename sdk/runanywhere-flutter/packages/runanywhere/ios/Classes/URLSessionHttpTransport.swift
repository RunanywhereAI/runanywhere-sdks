//
//  URLSessionHttpTransport.swift
//  RunAnywhere Flutter Plugin
//
//  Swift façade around the ObjC++ implementation in
//  `URLSessionHttpTransport.mm`. The ObjC++ file owns the
//  `rac_http_transport_ops_t` vtable and the URLSession machinery; this
//  file exposes `URLSessionHttpTransport.register()` so the Flutter plugin
//  can install the adapter from `RunAnywherePlugin.register(with:)`.
//
//  This is the Flutter counterpart of:
//    sdk/runanywhere-swift/Sources/RunAnywhere/HttpTransport/URLSessionHttpTransport.swift
//
//  Registering this adapter routes every `rac_http_request_*` call through
//  Apple's URLSession stack — iOS consumers inherit the system trust store,
//  configured proxies, HTTP/2, and App Transport Security instead of going
//  through libcurl (which was deleted in Stage 5).
//

import Foundation

/// URLSession-backed HTTP transport adapter.
///
/// Registers a `rac_http_transport_ops_t` vtable with the C core so every
/// `rac_http_request_send` / `_stream` / `_resume` call is serviced by
/// `URLSession`. Safe to call `register()` multiple times — subsequent
/// calls are no-ops (the ObjC++ implementation guards with an atomic flag).
public enum URLSessionHttpTransport {

    /// Install the URLSession adapter as the active HTTP transport.
    /// Idempotent — subsequent calls are no-ops.
    public static func register() {
        RAFlutterRegisterURLSessionTransport()
    }

    /// Restore the default HTTP transport (no-op if none was installed).
    /// Also cancels every in-flight streaming/resume task and clears the
    /// streaming-session override, matching the Swift SDK reference.
    public static func unregister() {
        RAFlutterUnregisterURLSessionTransport()
    }

    /// Install a custom `URLSession` for streaming downloads (model GGUFs,
    /// resume). Passing `nil` restores the built-in per-call session. Hosts
    /// that need a true iOS background session —
    /// `URLSessionConfiguration.background(withIdentifier:)` — supply one
    /// here and wire `handleEventsForBackgroundURLSession` in their
    /// `AppDelegate`, since that hook can only live in the application
    /// layer.
    ///
    /// The override is consulted per call; there is no ownership transfer.
    /// Thread-safe.
    public static func register(streamingSession session: URLSession?) {
        if let session = session {
            // `Unmanaged.passUnretained` is the right tool here: the ObjC++
            // side bridges via `__bridge NSURLSession*` (no transfer) and
            // stores its own strong reference into the static override slot.
            // The caller is responsible for keeping `session` alive until
            // they replace it (or pass `nil`).
            let raw = Unmanaged.passUnretained(session).toOpaque()
            RAFlutterSetStreamingSession(raw)
        } else {
            RAFlutterSetStreamingSession(nil)
        }
    }

    /// Cancel every in-flight streaming / resume task. Each pending
    /// chunk-callback returns to its caller with `RAC_ERROR_CANCELLED`.
    /// Complements the per-callback `return RAC_FALSE` cancel contract —
    /// use this when the SDK is tearing down and there is no callback on
    /// the stack to signal.
    public static func cancelAllStreams() {
        RAFlutterCancelAllStreams()
    }
}

// MARK: - Bridge to ObjC++ implementation
//
// These symbols are implemented in URLSessionHttpTransport.mm. They
// cannot be declared in an ObjC header consumed by Swift unless the
// pod ships a module map, so we declare them here with `@_silgen_name`
// and match the C ABI in the .mm file.

@_silgen_name("ra_flutter_register_urlsession_transport")
private func RAFlutterRegisterURLSessionTransport()

@_silgen_name("ra_flutter_unregister_urlsession_transport")
private func RAFlutterUnregisterURLSessionTransport()

@_silgen_name("ra_flutter_set_streaming_session")
private func RAFlutterSetStreamingSession(_ session: UnsafeMutableRawPointer?)

@_silgen_name("ra_flutter_cancel_all_streams")
private func RAFlutterCancelAllStreams()
