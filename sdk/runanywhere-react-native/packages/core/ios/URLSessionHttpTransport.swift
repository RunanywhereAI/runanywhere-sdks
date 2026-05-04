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

    /// Restore the default libcurl transport. Primarily useful in tests.
    @objc(unregister)
    public static func unregister() {
        RAUnregisterURLSessionTransport()
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
