//
//  RASDKError+Helpers.swift
//  RunAnywhere
//
//  Phase C-prime: ergonomic helpers attached to the canonical proto error
//  type `RASDKError`. The proto is the on-the-wire canonical form; this
//  extension restores Swift conveniences (LocalizedError-style descriptions,
//  category-specific factories) without needing the hand-rolled `SDKError`
//  struct.
//
//  Note: `RASDKError` is a value-type proto and cannot conform to `Error`
//  here because that protocol requires a class semantic in some Swift
//  versions when used as `any Error`. Use `SDKException(proto:)` to throw
//  these values; the wrapper handles the bridging.
//

import Foundation

// MARK: - RASDKError factories

extension RASDKError {
    /// Construct a proto error directly.
    ///
    /// `cAbiCode` is NOT populated here — the canonical C↔Swift translation
    /// of the ABI integer lives in `CommonsErrorMapping.toSDKException` and
    /// `fromSDKException`. Having a second derivation in this factory let
    /// the two sources drift. Callers that need to round-trip through the
    /// C ABI should go through `CommonsErrorMapping` directly.
    public static func make(
        code: RAErrorCode,
        message: String,
        category: RAErrorCategory = .component,
        nestedMessage: String? = nil
    ) -> RASDKError {
        var p = RASDKError()
        p.code = code
        p.message = message
        p.category = category
        if let nested = nestedMessage {
            p.nestedMessage = nested
        }
        return p
    }

    /// Format a one-line summary suitable for logs / debug output.
    public var summary: String {
        "[\(category)] \(code): \(message)"
    }

    /// Throw this error wrapped as a Swift `SDKException`.
    public func throwAsException() throws -> Never {
        throw SDKException(proto: self)
    }
}
