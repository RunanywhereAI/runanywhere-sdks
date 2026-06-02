//
//  HybridProtoWire.swift
//  RunAnywhere
//
//  Minimal proto3 wire codec for the `runanywhere.v1.Hybrid*` messages the
//  STT hybrid router's proto-byte C ABI exchanges
//  (rac_stt_hybrid_router_proto.h).
//
//  Why hand-rolled instead of SwiftProtobuf: `idl/hybrid_router.proto` is NOT
//  emitted to a `hybrid_router.pb.swift` by the Swift codegen pass (only the
//  Kotlin Wire + C++ protobuf bindings are generated for it), so there is no
//  generated `RAHybridRoutingPolicy` Message to serialize. Rather than add a
//  codegen step, this binding follows the instruction's "thin struct →
//  serialized bytes" path: it encodes exactly the handful of fields the
//  router reads and decodes exactly the fields the response carries, using the
//  proto3 wire format the C++ side (hybrid_router.pb.cc) parses.
//
//  Scope: this is a *marshalling* helper only. No routing / cascade / rank
//  logic lives here — commons owns all of that. These functions just move the
//  policy + descriptor + request across the FFI as bytes and read the response
//  metadata back.
//
//  Wire reference (idl/hybrid_router.proto):
//    HybridFilter            { network=1:bool | quality_tier=3:int32 |
//                              battery=4:msg | custom=5:msg }   (oneof)
//    BatteryFilter           { min_battery_percent=1:int32 }
//    CustomFilter            { name=1:string, description=2:string }
//    HybridCascade           { confidence=1:msg }               (oneof)
//    ConfidenceCascade       { threshold=1:float }
//    HybridRoutingPolicy     { hard_filters=1:repeated, cascade=2:msg,
//                              rank=3:enum }
//    HybridModelDescriptor   { model_id=1:string, model_type=2:enum,
//                              backend=3:enum, provider=4:string }
//    HybridSttTranscribeOptions  { language=1:string, sample_rate=2:int32,
//                                  audio_format=3:int32 }
//    HybridSttTranscribeRequest  { audio_bytes=1:bytes, context=2:msg,
//                                  options=3:msg }
//    HybridRoutedMetadata    { chosen_model_id=1:string, was_fallback=2:bool,
//                              attempt_count=3:int32, primary_error_code=4:int32,
//                              primary_error_message=5:string, confidence=6:float,
//                              primary_confidence=7:float }
//    HybridSttTranscribeResponse { rc=1:int32, text=2:string,
//                                  detected_language=3:string, routing=4:msg,
//                                  error_msg=5:string }
//

import Foundation

// MARK: - Encoder

/// Append-only proto3 wire writer. Just enough of the encoding to build the
/// hybrid request/policy/descriptor messages.
struct ProtoWireWriter {
    private(set) var bytes: [UInt8] = []

    // Wire types (proto3): 0 = varint, 2 = length-delimited, 5 = 32-bit.
    private enum WireType: UInt8 {
        case varint = 0
        case fixed32 = 5
        case lengthDelimited = 2
    }

    private mutating func appendTag(_ field: Int, _ type: WireType) {
        appendVarint(UInt64(field) << 3 | UInt64(type.rawValue))
    }

    private mutating func appendVarint(_ value: UInt64) {
        var v = value
        while v >= 0x80 {
            bytes.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        bytes.append(UInt8(v))
    }

    /// proto3 omits zero-valued scalar fields. Callers pass the proto default
    /// so a `false` / `0` / `""` field contributes nothing to the wire — this
    /// matches the C++/Wire encoders byte-for-byte so the router parses an
    /// identical message regardless of which SDK built it.
    mutating func int32(_ field: Int, _ value: Int32, skipDefault: Bool = true) {
        if skipDefault && value == 0 { return }
        appendTag(field, .varint)
        // int32 is sign-extended to 64 bits on the wire (proto spec).
        appendVarint(UInt64(bitPattern: Int64(value)))
    }

    mutating func bool(_ field: Int, _ value: Bool, skipDefault: Bool = true) {
        if skipDefault && !value { return }
        appendTag(field, .varint)
        appendVarint(value ? 1 : 0)
    }

    mutating func enumValue(_ field: Int, _ value: Int32) {
        // Enums encode as varint; default (0) is omitted like any scalar.
        int32(field, value)
    }

    mutating func float(_ field: Int, _ value: Float, skipDefault: Bool = true) {
        if skipDefault && value == 0 { return }
        appendTag(field, .fixed32)
        let bits = value.bitPattern
        bytes.append(UInt8(bits & 0xFF))
        bytes.append(UInt8((bits >> 8) & 0xFF))
        bytes.append(UInt8((bits >> 16) & 0xFF))
        bytes.append(UInt8((bits >> 24) & 0xFF))
    }

    mutating func string(_ field: Int, _ value: String, skipDefault: Bool = true) {
        if skipDefault && value.isEmpty { return }
        bytesField(field, Array(value.utf8))
    }

    mutating func bytesField(_ field: Int, _ value: [UInt8], skipDefault: Bool = false) {
        if skipDefault && value.isEmpty { return }
        appendTag(field, .lengthDelimited)
        appendVarint(UInt64(value.count))
        bytes.append(contentsOf: value)
    }

    /// Embed a nested message (already encoded to bytes) as a length-delimited
    /// field. Always emitted even when empty, so an explicitly-present empty
    /// sub-message (e.g. HybridRoutingContext) round-trips.
    mutating func message(_ field: Int, _ value: [UInt8]) {
        appendTag(field, .lengthDelimited)
        appendVarint(UInt64(value.count))
        bytes.append(contentsOf: value)
    }
}

// MARK: - Decoder

/// Single-pass proto3 wire reader used to decode HybridSttTranscribeResponse /
/// HybridRoutedMetadata. Skips unknown fields so a newer commons that adds
/// fields stays readable.
struct ProtoWireReader {
    private let bytes: [UInt8]
    private var index: Int = 0

    init(_ data: [UInt8]) { self.bytes = data }

    var isAtEnd: Bool { index >= bytes.count }

    /// A decoded (field number, wire type) tag header.
    struct Tag {
        let field: Int
        let wireType: UInt8
    }

    mutating func readTag() -> Tag? {
        guard let raw = readVarint() else { return nil }
        return Tag(field: Int(raw >> 3), wireType: UInt8(raw & 0x7))
    }

    mutating func readVarint() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift >= 64 { return nil }
        }
        return nil
    }

    mutating func readInt32() -> Int32 {
        // int32 is stored as a (possibly sign-extended) varint.
        Int32(truncatingIfNeeded: readVarint() ?? 0)
    }

    mutating func readBool() -> Bool {
        (readVarint() ?? 0) != 0
    }

    mutating func readFloat() -> Float {
        guard index + 4 <= bytes.count else { index = bytes.count; return 0 }
        let bits = UInt32(bytes[index])
            | UInt32(bytes[index + 1]) << 8
            | UInt32(bytes[index + 2]) << 16
            | UInt32(bytes[index + 3]) << 24
        index += 4
        return Float(bitPattern: bits)
    }

    mutating func readLengthDelimited() -> [UInt8] {
        guard let len = readVarint() else { return [] }
        let count = Int(len)
        guard index + count <= bytes.count else {
            let slice = Array(bytes[index..<bytes.count])
            index = bytes.count
            return slice
        }
        let slice = Array(bytes[index..<(index + count)])
        index += count
        return slice
    }

    mutating func readString() -> String {
        String(decoding: readLengthDelimited(), as: UTF8.self)
    }

    /// Advance past a field whose tag we don't recognise, honouring its wire
    /// type so the cursor stays aligned.
    mutating func skip(wireType: UInt8) {
        switch wireType {
        case 0: _ = readVarint()              // varint
        case 1: index = min(index + 8, bytes.count)   // 64-bit
        case 2: _ = readLengthDelimited()     // length-delimited
        case 5: index = min(index + 4, bytes.count)   // 32-bit
        default: index = bytes.count          // unknown — stop
        }
    }
}
