//
//  URLSessionHttpTransport.swift
//  RunAnywhere React Native Core
//
//  Swift URLSession-backed adapter for the cross-SDK HTTP transport
//  vtable (`rac_http_transport_*`). Registering this adapter routes
//  every `rac_http_request_*` call through Apple's URLSession stack —
//  so iOS consumers inherit the system trust store, configured
//  proxies, HTTP/2, and App Transport Security for free instead of
//  going through the bundled libcurl.
//
//  This is a near-copy of the Swift SDK's
//  `sdk/runanywhere-swift/Sources/RunAnywhere/HttpTransport/URLSessionHttpTransport.swift`.
//  The public `URLSessionHttpTransport.register()` entry point is preserved
//  and exposed via `@objc(RARegisterURLSessionTransport)` so the RN Nitro C++
//  layer can call it from `HybridRunAnywhereCore::initialize()`.
//
//  Because the RN core pod does not ship a `CRACommons` Swift module map,
//  the actual URLSession transport logic lives in the accompanying
//  `URLSessionHttpTransport.mm` file (so it can `#include
//  "rac/infrastructure/http/rac_http_transport.h"` directly). This Swift
//  file provides the public registration API surface that matches the
//  Swift SDK's file verbatim.
//

import Foundation

// MARK: - Adapter

/// URLSession-backed HTTP transport adapter.
///
/// Registers a static `rac_http_transport_ops_t` vtable with the C core
/// so every `rac_http_request_send` / `_stream` / `_resume` call is
/// serviced by `URLSession` on iOS. Safe to call `register()` multiple
/// times — subsequent calls are no-ops (the ObjC++ implementation
/// guards with an atomic flag).
@objc(RAURLSessionHttpTransport)
public final class URLSessionHttpTransport: NSObject {

    /// Install the URLSession adapter as the active HTTP transport.
    /// Idempotent — subsequent calls are no-ops.
    @objc(register)
    public static func register() {
        RARegisterURLSessionTransport()
    }

    /// Restore the default HTTP transport (no-op if none was installed).
    /// Also cancels every in-flight streaming/resume task and clears the
    /// streaming-session override, matching the Swift SDK reference.
    @objc(unregister)
    public static func unregister() {
        RAUnregisterURLSessionTransport()
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
            RASetStreamingSession(raw)
        } else {
            RASetStreamingSession(nil)
        }
    }

    /// Cancel every in-flight streaming / resume task. Each pending
    /// chunk-callback returns to its caller with `RAC_ERROR_CANCELLED`.
    /// Complements the per-callback `return RAC_FALSE` cancel contract —
    /// use this when the SDK is tearing down and there is no callback on
    /// the stack to signal.
    @objc(cancelAllStreams)
    public static func cancelAllStreams() {
        RACancelAllStreams()
    }
}

// MARK: - Bridge to ObjC++ implementation
//
// These symbols are implemented in URLSessionHttpTransport.mm. They
// cannot be declared in an ObjC header consumed by Swift unless the
// pod ships a module map, so we declare them here with `@_silgen_name`
// and match the C ABI in the .mm file.

@_silgen_name("rn_register_urlsession_transport")
private func RARegisterURLSessionTransport()

@_silgen_name("rn_unregister_urlsession_transport")
private func RAUnregisterURLSessionTransport()

@_silgen_name("rn_set_streaming_session")
private func RASetStreamingSession(_ session: UnsafeMutableRawPointer?)

@_silgen_name("rn_cancel_all_streams")
private func RACancelAllStreams()
