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

    private static let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)

    static func load<T>(_ symbolName: String, as _: T.Type) -> T? {
        guard let symbol = dlsym(defaultHandle, symbolName) else {
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
            throw SDKException.general(.notSupported, missingSymbolMessage(symbolName))
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
            throw SDKException.general(.processingFailed, message)
        }
        guard let data = buffer.data, buffer.size > 0 else {
            return responseType.init()
        }
        return try responseType.init(serializedBytes: Data(bytes: data, count: buffer.size))
    }

    static func free(_ buffer: inout rac_proto_buffer_t) {
        freeBuffer?(&buffer)
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
            let message = outBuffer.error_message.map { String(cString: $0) }
                ?? "Native proto request failed: \(symbolName) rc=\(status)"
            throw SDKException.general(.processingFailed, message)
        }
        return try decode(responseType, from: outBuffer)
    }
}
