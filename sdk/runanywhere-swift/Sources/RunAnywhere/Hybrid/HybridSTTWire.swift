//
//  HybridSTTWire.swift
//  RunAnywhere
//
//  STT-specific request encode / response decode for the hybrid router's
//  proto-byte ABI. Pairs with rac_stt_hybrid_router_proto.cpp, which
//  decodes/encodes the same runanywhere.v1.* messages on the C++ side.
//
//  Mirrors the Kotlin HybridSttRouterProto helper; pure marshalling only.
//

import Foundation

enum HybridSTTWire {

    /// Build a `runanywhere.v1.HybridSttTranscribeRequest` carrying the audio
    /// bytes, an (empty, present) routing context, and the options.
    ///
    /// HybridRoutingContext currently has no fields — device-state lives behind
    /// the `rac_hybrid_device_state` vtable. The empty message is still emitted
    /// so the wire shape is stable for future per-call hints.
    static func encodeRequest(audio: [UInt8], options: HybridTranscribeOptions) -> [UInt8] {
        var writer = ProtoWireWriter()
        writer.bytesField(1, audio)                                  // bytes audio_bytes = 1
        writer.message(2, [])                                        // HybridRoutingContext context = 2 (empty)
        writer.message(3, encodeOptions(options))                   // HybridSttTranscribeOptions options = 3
        return writer.bytes
    }

    private static func encodeOptions(_ options: HybridTranscribeOptions) -> [UInt8] {
        var writer = ProtoWireWriter()
        writer.string(1, options.language)        // string language = 1
        writer.int32(2, options.sampleRate)       // int32 sample_rate = 2
        writer.int32(3, options.audioFormat)      // int32 audio_format = 3
        return writer.bytes
    }

    /// Decode a `runanywhere.v1.HybridSttTranscribeResponse` into the public
    /// result, raising the native rc as an `SDKException` when non-zero.
    static func decodeResponse(_ data: [UInt8]) throws -> HybridTranscribeResult {
        var reader = ProtoWireReader(data)
        var rc: Int32 = 0
        var text = ""
        var detectedLanguage = ""
        var routingBytes: [UInt8] = []
        var errorMsg = ""

        while let tag = reader.readTag() {
            switch (tag.field, tag.wireType) {
            case (1, 0): rc = reader.readInt32()                       // int32 rc = 1
            case (2, 2): text = reader.readString()                    // string text = 2
            case (3, 2): detectedLanguage = reader.readString()        // string detected_language = 3
            case (4, 2): routingBytes = reader.readLengthDelimited()   // HybridRoutedMetadata routing = 4
            case (5, 2): errorMsg = reader.readString()                // string error_msg = 5
            default: reader.skip(wireType: tag.wireType)
            }
        }

        let routing = decodeRoutedMetadata(routingBytes)

        guard rc == 0 else {
            let message = errorMsg.isEmpty
                ? "Hybrid STT transcribe failed (rc=\(rc))"
                : errorMsg
            throw SDKException(
                code: .serviceNotAvailable,
                message: message,
                category: .component
            )
        }

        return HybridTranscribeResult(
            text: text,
            detectedLanguage: detectedLanguage,
            routing: routing
        )
    }

    private static func decodeRoutedMetadata(_ data: [UInt8]) -> HybridRoutedMetadata {
        var reader = ProtoWireReader(data)
        var chosenModelId = ""
        var wasFallback = false
        var attemptCount: Int32 = 0
        var primaryErrorCode: Int32 = 0
        var primaryErrorMessage = ""
        // Default to NaN: the field is omitted on the wire when the engine
        // surfaces no quality signal (proto3 drops 0.0, but commons sends NaN
        // explicitly via the C++ encoder, so a present 0.0 stays 0.0).
        var confidence = Float.nan
        var primaryConfidence = Float.nan

        while let tag = reader.readTag() {
            switch (tag.field, tag.wireType) {
            case (1, 2): chosenModelId = reader.readString()           // string chosen_model_id = 1
            case (2, 0): wasFallback = reader.readBool()               // bool was_fallback = 2
            case (3, 0): attemptCount = reader.readInt32()             // int32 attempt_count = 3
            case (4, 0): primaryErrorCode = reader.readInt32()         // int32 primary_error_code = 4
            case (5, 2): primaryErrorMessage = reader.readString()     // string primary_error_message = 5
            case (6, 5): confidence = reader.readFloat()               // float confidence = 6
            case (7, 5): primaryConfidence = reader.readFloat()        // float primary_confidence = 7
            default: reader.skip(wireType: tag.wireType)
            }
        }

        return HybridRoutedMetadata(
            chosenModelId: chosenModelId,
            wasFallback: wasFallback,
            attemptCount: attemptCount,
            primaryErrorCode: primaryErrorCode,
            primaryErrorMessage: primaryErrorMessage,
            confidence: confidence,
            primaryConfidence: primaryConfidence
        )
    }
}
