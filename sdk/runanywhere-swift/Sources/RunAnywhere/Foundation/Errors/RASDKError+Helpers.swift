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

import CRACommons
import Foundation

// MARK: - RASDKError factories

extension RASDKError {
    /// Construct a proto error directly.
    ///
    /// `cAbiCode` is NOT populated here. Callers that need to round-trip
    /// through the C ABI should go through `RASDKError.from(rcResult:)`,
    /// which delegates to commons (`rac_result_to_proto_error`) so the
    /// rac_result_t -> proto translation lives in a single place across
    /// every SDK.
    public static func make(
        code: RAErrorCode,
        message: String,
        category: RAErrorCategory = .component,
        nestedMessage: String? = nil
    ) -> RASDKError {
        var proto = RASDKError()
        proto.code = code
        proto.message = message
        proto.category = category
        if let nested = nestedMessage {
            proto.nestedMessage = nested
        }
        return proto
    }

    /// Map a `rac_result_t` to a proto `RASDKError` via the canonical
    /// commons ABI `rac_result_to_proto_error`. Returns nil for `RAC_SUCCESS`.
    ///
    /// Replaces the hand-written switch tables previously in
    /// `CommonsErrorMapping.swift`; the commons implementation is the single
    /// source of truth shared by every platform SDK.
    public static func from(rcResult result: rac_result_t) -> RASDKError? {
        guard result != RAC_SUCCESS else { return nil }
        var outBuffer = rac_proto_buffer_t()
        defer { NativeProtoABI.free(&outBuffer) }
        let status = rac_result_to_proto_error(result, &outBuffer)
        guard status == RAC_SUCCESS,
              let data = outBuffer.data,
              outBuffer.size > 0 else {
            return RASDKError.make(
                code: .unknown,
                message: "Unknown error code: \(result)",
                category: .internal
            )
        }
        let bytes = Data(bytes: data, count: outBuffer.size)
        return try? RASDKError(serializedBytes: bytes)
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

// MARK: - SDKException C ABI bridge

extension SDKException {
    /// Build an `SDKException` from a `rac_result_t` via the canonical
    /// commons ABI `rac_result_to_proto_error`. Returns nil on `RAC_SUCCESS`.
    public static func from(rcResult result: rac_result_t) -> SDKException? {
        guard let proto = RASDKError.from(rcResult: result) else { return nil }
        return SDKException(proto: proto)
    }

    /// Throw an `SDKException` if the `rac_result_t` indicates failure.
    public static func throwIfError(_ result: rac_result_t) throws {
        if let ex = SDKException.from(rcResult: result) {
            throw ex
        }
    }
}
