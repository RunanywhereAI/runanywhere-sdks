//
//  CppBridge+NativeProtoABI.swift
//  RunAnywhere SDK
//
//  Shared helpers for optional native proto-byte C ABI bindings.
//

import CRACommons
import Darwin
import Foundation
import SwiftProtobuf

enum NativeProtoABI {
    typealias ProtoBufferFree = @convention(c) (UnsafeMutablePointer<rac_proto_buffer_t>?) -> Void
    typealias ProtoRequest = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    static let unavailableMessage = "Native proto ABI is not exported by the linked RACommons binary"

    static func load<T>(_ symbolName: String, as _: T.Type) -> T? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), symbolName) else {
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    static let freeBuffer = load("rac_proto_buffer_free", as: ProtoBufferFree.self)

    static var canReceiveProtoBuffer: Bool {
        freeBuffer != nil
    }

    static func missingSymbolMessage(_ symbolName: String) -> String {
        "\(unavailableMessage): \(symbolName)"
    }

    static func require<T>(_ symbol: T?, named symbolName: String) throws -> T {
        guard let symbol, canReceiveProtoBuffer else {
            throw SDKException(code: .notSupported, message: missingSymbolMessage(symbolName), category: .internal)
        }
        return symbol
    }

    static func withSerializedBytes<Request: Message, Result>(
        _ request: Request,
        _ body: (UnsafePointer<UInt8>?, Int) -> Result
    ) throws -> Result {
        let data = try request.serializedData()
        if data.isEmpty {
            return body(nil, 0)
        }
        return data.withUnsafeBytes { rawBuffer in
            body(rawBuffer.bindMemory(to: UInt8.self).baseAddress, rawBuffer.count)
        }
    }

    static func decode<Response: Message>(
        _ responseType: Response.Type,
        from buffer: rac_proto_buffer_t
    ) throws -> Response {
        guard buffer.status == RAC_SUCCESS else {
            let message = buffer.error_message.map { String(cString: $0) } ?? unavailableMessage
            throw SDKException(code: .processingFailed, message: message, category: .internal)
        }
        guard let data = buffer.data, buffer.size > 0 else {
            return responseType.init()
        }
        let bytes = Data(bytes: data, count: buffer.size)
        do {
            return try responseType.init(serializedBytes: bytes)
        } catch BinaryDecodingError.invalidUTF8 {
            // Commons can emit proto `string` fields carrying invalid UTF-8
            // (model output and byte-sliced document text — see
            // `ProtoUTF8Sanitizer`). C++ protobuf serializes those bytes without
            // failing, and Android (Wire) / Flutter (dart-protobuf) decode them
            // leniently by substituting U+FFFD. SwiftProtobuf is the strict
            // outlier and throws `.invalidUTF8`. Match the other SDKs by
            // repairing the offending byte runs and decoding the wire-equivalent
            // payload. This runs ONLY on the strict-decode failure path, and only
            // for message types with a registered repair shape, so valid
            // responses are unaffected and there is no cross-SDK parity risk.
            guard let shape = ProtoUTF8Sanitizer.shape(forMessageNamed: responseType.protoMessageName),
                  let repaired = ProtoUTF8Sanitizer.repair(bytes, as: shape) else {
                throw BinaryDecodingError.invalidUTF8
            }
            return try responseType.init(serializedBytes: repaired)
        }
    }

    static func free(_ buffer: inout rac_proto_buffer_t) {
        freeBuffer?(&buffer)
    }

    /// The most specific description the native layer produced for a failure.
    ///
    /// The proto buffer usually carries the error code's generic name, while the
    /// engine that actually failed writes the reason to the thread-local detail
    /// through `rac_error_set_details`. Reporting only the first throws the
    /// diagnosis away: an MLX speech model that could not run reported
    /// "Inference failed" while the reason sat one call away, unread.
    ///
    /// The detail is thread-local and not stamped with the call that set it, so
    /// a stale one from an earlier failure on this thread can in principle be
    /// appended. It is read immediately after a failed call, the same window
    /// `RunAnywhere+Solutions` and `RunAnywhere+Workflows` already rely on, and
    /// a slightly wrong hint beats none at all.
    private static func nativeFailureMessage(_ status: rac_result_t, symbolName: String,
                                             buffer: rac_proto_buffer_t) -> String {
        let base = buffer.error_message.map { String(cString: $0) }
            ?? "Native proto request failed: \(symbolName) rc=\(status)"
        guard let detailPointer = rac_error_get_details() else { return base }
        let detail = String(cString: detailPointer).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty, !base.contains(detail) else { return base }
        return "\(base): \(detail)"
    }

    static func invoke<Request: Message, Response: Message>(
        _ request: Request,
        symbol: ProtoRequest?,
        symbolName: String,
        responseType: Response.Type
    ) throws -> Response {
        let symbol = try require(symbol, named: symbolName)
        var outBuffer = rac_proto_buffer_t()
        defer { free(&outBuffer) }
        let status = try withSerializedBytes(request) { bytes, size in
            symbol(bytes, size, &outBuffer)
        }
        guard status == RAC_SUCCESS else {
            throw SDKException(code: .processingFailed,
                               message: nativeFailureMessage(status, symbolName: symbolName,
                                                             buffer: outBuffer),
                               category: .internal)
        }
        return try decode(responseType, from: outBuffer)
    }

    // Usages live in `Sources/RunAnywhere/Generated/`, which `.swiftlint.yml`
    // excludes from analysis; the analyzer therefore cannot see them.
    // swiftlint:disable unused_declaration
    /// Context-threaded variant of `invoke` for C ABI symbols whose first
    /// parameter is an opaque handle (e.g. `rac_handle_t`,
    /// `rac_voice_agent_handle_t`, `rac_lora_registry_handle_t`, an actor
    /// session, ...). Mirrors the unary `invoke` shape; supersedes the
    /// per-domain `invokeRAGRequest`/`invokeLoRARequest`/`invokeRegistryRequest`/
    /// `invokeProto`/`invoke`/`invokeBytes` helpers scattered across the
    /// bridge layer (see `gaps/gaps/simplification/swift-bridge-duplication.md`
    /// §1 Pattern A).
    static func invoke<Ctx, Request: Message, Response: Message>(
        _ request: Request,
        on context: Ctx,
        symbol: ((Ctx?, UnsafePointer<UInt8>?, Int,
                  UnsafeMutablePointer<rac_proto_buffer_t>?) -> rac_result_t)?,
        symbolName: String,
        responseType: Response.Type
    ) throws -> Response {
        let symbol = try require(symbol, named: symbolName)
        var outBuffer = rac_proto_buffer_t()
        defer { free(&outBuffer) }
        let status = try withSerializedBytes(request) { bytes, size in
            symbol(context, bytes, size, &outBuffer)
        }
        guard status == RAC_SUCCESS else {
            throw SDKException(code: .processingFailed,
                               message: nativeFailureMessage(status, symbolName: symbolName,
                                                             buffer: outBuffer),
                               category: .internal)
        }
        return try decode(responseType, from: outBuffer)
    }
    // swiftlint:enable unused_declaration
}
