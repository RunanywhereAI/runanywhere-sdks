//
//  ProtoUTF8Sanitizer.swift
//  RunAnywhere SDK
//
//  Best-effort repair of invalid UTF-8 inside serialized protobuf payloads.
//
//  WHY THIS EXISTS
//  ---------------
//  Commons builds proto `string` fields from on-device model output and from
//  byte-sliced document text. For RAG specifically, `RAGBackend::add_document`
//  stores `text.substr(0, 100)` as a chunk's `source_text` preview
//  (rag_backend.cpp), and the query result assembles `RAGResult.answer`
//  (model output), `RAGResult.context_used`, and `RAGSearchResult.text`. A byte
//  slice (or a generation cut mid-token) that lands inside a multi-byte UTF-8
//  scalar yields an invalid byte run. The C++ protobuf runtime serializes such a
//  `kUtf8String` field without failing (verify-on-serialize only *logs* in
//  optimized builds), so the bytes reach the SDKs intact.
//
//  Android (Wire) and Flutter (dart `protobuf`, `utf8.decode(..., allowMalformed:
//  true)`) decode strings leniently and substitute U+FFFD, so they never see a
//  failure. SwiftProtobuf is the strict outlier: `BinaryDecoder` validates every
//  `string` field and throws `BinaryDecodingError.invalidUTF8` (the third enum
//  case, surfaced to users as "BinaryDecodingError error 2"). That is why the
//  iOS RAG query failed to decode a result the C++ pipeline produced correctly,
//  while the same bytes decoded fine on Android/Flutter.
//
//  WHAT THIS DOES
//  --------------
//  `ProtoUTF8Sanitizer.repair(_:as:)` rewrites the offending `string` fields,
//  replacing only invalid byte runs with U+FFFD and reproducing every other
//  byte (varints, fixed32/64, valid strings, `bytes` fields, nested messages)
//  verbatim. Repair is SCHEMA-DRIVEN: a caller supplies a `MessageShape` that
//  names which field numbers are scalar `string` fields and which are nested
//  messages to recurse into. This is deliberate — a generic "guess from the
//  wire type" walker is unsafe because a plain string payload can coincidentally
//  parse as a well-formed sub-message (e.g. an ASCII first byte reads as a valid
//  tag), which would skip scrubbing or corrupt the field. Following the real
//  schema removes that ambiguity.
//
//  Repair is invoked ONLY as a fallback after a strict decode throws
//  `.invalidUTF8` AND a shape is registered for the message type (see
//  `NativeProtoABI.decode` / `ProtoUTF8Sanitizer.shape(forMessageNamed:)`).
//  Well-formed responses — every currently-passing path on every modality —
//  are decoded strictly, byte-for-byte, exactly as before. There is therefore
//  no behavioral change for valid payloads, the C ABI wire contract is
//  unchanged, and Android/Flutter are untouched.
//

import Foundation

/// Stateless helper that repairs invalid UTF-8 inside the `string` fields of a
/// serialized protobuf message, guided by an explicit per-message field map.
enum ProtoUTF8Sanitizer {

    /// Per-message description of which fields carry UTF-8 text and which are
    /// nested messages that may themselves contain text fields.
    struct MessageShape {
        /// Field numbers whose payload is a scalar proto `string` (wire type 2,
        /// UTF-8). Their byte run is scrubbed in place.
        let stringFields: Set<Int>
        /// Field numbers whose payload is a nested message (wire type 2),
        /// mapped to the shape used to repair that nested message. Covers both
        /// embedded messages and `map<...>` fields (the wire format encodes map
        /// entries as repeated `{key=1, value=2}` messages).
        let messageFields: [Int: MessageShape]

        init(stringFields: Set<Int>, messageFields: [Int: MessageShape] = [:]) {
            self.stringFields = stringFields
            self.messageFields = messageFields
        }
    }

    // MARK: - Registered shapes

    /// `map<string, string>` entry: key = field 1, value = field 2.
    private static let stringStringMapEntry = MessageShape(stringFields: [1, 2])

    /// `RAGSearchResult` (rag.proto): chunk_id=1, text=2, source_document=4 are
    /// strings; metadata=5 is a `map<string,string>`.
    private static let ragSearchResultShape = MessageShape(
        stringFields: [1, 2, 4],
        messageFields: [5: stringStringMapEntry]
    )

    /// `RAGResult` (rag.proto): answer=1, context_used=3, error_message=10,
    /// request_id=12 are strings; retrieved_chunks=2 is a repeated
    /// `RAGSearchResult`.
    private static let ragResultShape = MessageShape(
        stringFields: [1, 3, 10, 12],
        messageFields: [2: ragSearchResultShape]
    )

    /// Returns the repair shape for a fully-qualified proto message name, or
    /// `nil` when the type has no registered shape (in which case the caller
    /// keeps the original strict-decode error rather than guessing). Keyed by
    /// `SwiftProtobuf.Message.protoMessageName`, e.g. "runanywhere.v1.RAGResult".
    static func shape(forMessageNamed name: String) -> MessageShape? {
        switch name {
        case "runanywhere.v1.RAGResult":
            return ragResultShape
        default:
            return nil
        }
    }

    // MARK: - Repair

    /// Returns a wire-equivalent copy of `data` with invalid UTF-8 in the
    /// `string` fields named by `shape` (recursively) replaced by U+FFFD.
    /// Returns `nil` when the buffer is not a well-formed message, so the caller
    /// can surface the original error instead of a malformed rewrite.
    static func repair(_ data: Data, as shape: MessageShape) -> Data? {
        var output = Data()
        output.reserveCapacity(data.count)
        guard repairMessage(Array(data), shape: shape, into: &output) else { return nil }
        return output
    }

    /// Protobuf wire types we need to distinguish while walking the buffer.
    private enum WireType: UInt64 {
        case varint = 0
        case fixed64 = 1
        case lengthDelimited = 2
        case startGroup = 3
        case endGroup = 4
        case fixed32 = 5
    }

    /// Walks one message body field-by-field, repairing only the fields named by
    /// `shape`. Returns `false` if the bytes are not a well-formed message.
    private static func repairMessage(_ bytes: [UInt8], shape: MessageShape, into output: inout Data) -> Bool {
        var index = 0
        let end = bytes.count

        while index < end {
            guard let (tag, afterTag) = readVarint(bytes, index) else { return false }
            let fieldNumber = Int(tag >> 3)
            guard let wireType = WireType(rawValue: tag & 0x7) else { return false }
            appendVarint(tag, to: &output)  // re-emit tag verbatim
            index = afterTag

            switch wireType {
            case .varint:
                guard let (value, next) = readVarint(bytes, index) else { return false }
                appendVarint(value, to: &output)
                index = next

            case .fixed64:
                guard index + 8 <= end else { return false }
                output.append(contentsOf: bytes[index..<index + 8])
                index += 8

            case .fixed32:
                guard index + 4 <= end else { return false }
                output.append(contentsOf: bytes[index..<index + 4])
                index += 4

            case .lengthDelimited:
                guard let (length, afterLen) = readVarint(bytes, index) else { return false }
                let payloadEnd = afterLen + Int(length)
                guard payloadEnd <= end else { return false }
                let payload = Array(bytes[afterLen..<payloadEnd])
                guard appendLengthDelimited(payload, fieldNumber: fieldNumber, shape: shape, into: &output) else {
                    return false
                }
                index = payloadEnd

            case .startGroup, .endGroup:
                // Proto2 groups are not used by any RunAnywhere IDL message.
                // Bail so the caller keeps the original strict error.
                return false
            }
        }

        return index == end
    }

    /// Emits one length-delimited field's payload to `output`, choosing among:
    /// recurse (known nested message), scrub (known string field), or verbatim
    /// (everything else — `bytes` scalars and unmodeled fields). Returns `false`
    /// only when a known nested message fails to parse.
    private static func appendLengthDelimited(
        _ payload: [UInt8],
        fieldNumber: Int,
        shape: MessageShape,
        into output: inout Data
    ) -> Bool {
        if let nestedShape = shape.messageFields[fieldNumber] {
            // Known nested message: recurse so deeper string fields
            // (e.g. RAGSearchResult.text, map entries) are repaired too.
            var repaired = Data()
            guard repairMessage(payload, shape: nestedShape, into: &repaired) else { return false }
            appendVarint(UInt64(repaired.count), to: &output)
            output.append(repaired)
        } else if shape.stringFields.contains(fieldNumber) {
            // Known string field: scrub invalid UTF-8 in place.
            let scrubbed = scrubInvalidUTF8(payload)
            appendVarint(UInt64(scrubbed.count), to: &output)
            output.append(scrubbed)
        } else {
            // Unknown / `bytes` / unmodeled field: reproduce verbatim.
            appendVarint(UInt64(payload.count), to: &output)
            output.append(contentsOf: payload)
        }
        return true
    }

    /// Returns `bytes` unchanged when already valid UTF-8; otherwise a copy in
    /// which each maximal invalid byte run is replaced by a single U+FFFD,
    /// matching the substitution Wire / dart-protobuf perform implicitly.
    private static func scrubInvalidUTF8(_ bytes: [UInt8]) -> Data {
        if bytes.isEmpty { return Data() }
        if String(bytes: bytes, encoding: .utf8) != nil {
            return Data(bytes)
        }

        let replacement: [UInt8] = Array("\u{FFFD}".utf8)  // EF BF BD
        var result = Data()
        result.reserveCapacity(bytes.count)

        var parser = Unicode.UTF8.ForwardParser()
        var iterator = bytes.makeIterator()
        var pendingInvalid = false
        Loop: while true {
            switch parser.parseScalar(from: &iterator) {
            case let .valid(units):
                pendingInvalid = false
                result.append(contentsOf: units)
            case .error:
                // Collapse a run of consecutive invalid sequences into one
                // replacement character.
                if !pendingInvalid {
                    result.append(contentsOf: replacement)
                    pendingInvalid = true
                }
            case .emptyInput:
                break Loop
            }
        }
        return result
    }

    // MARK: - Varint helpers

    /// Reads a base-128 varint at `start`. Returns the value and the index just
    /// past it, or `nil` on truncation / overlong (> 64-bit) encoding.
    private static func readVarint(_ bytes: [UInt8], _ start: Int) -> (UInt64, Int)? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        var index = start
        let end = bytes.count
        while index < end {
            let byte = bytes[index]
            if shift >= 64 { return nil }
            value |= UInt64(byte & 0x7F) << shift
            index += 1
            if byte & 0x80 == 0 {
                return (value, index)
            }
            shift += 7
        }
        return nil
    }

    /// Appends `value` to `output` in protobuf base-128 varint encoding.
    private static func appendVarint(_ value: UInt64, to output: inout Data) {
        var remaining = value
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            output.append(byte)
        } while remaining != 0
    }
}
