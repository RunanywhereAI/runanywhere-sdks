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
//    sdk/runanywhere-react-native/packages/core/ios/URLSessionHttpTransport.swift
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
    public static func unregister() {
        RAFlutterUnregisterURLSessionTransport()
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
