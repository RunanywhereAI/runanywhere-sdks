//
//  CppBridge+StructuredOutput.swift
//  RunAnywhere SDK
//
//  Generated-proto ABI bindings for structured-output operations.
//
//  All structured-output orchestration (prompt preparation, generation,
//  thinking-tag stripping, JSON extraction, schema validation) lives in the
//  commons C++ layer. The Swift façade is a thin proto-byte bridge.
//

import Foundation

// pass3-syn-110: `generate(_:)` + its `generateName`/`generate` symbol-cache
// properties were deleted because no Swift call site invoked them — the
// public `RunAnywhere.generateStructured(...)` facade routes through the
// LLM path (`LLM.generate(...)`), and the streaming variant lives in the
// generated `Generated/ModalityProtoABI+Generated.swift` extension.
// Periphery flagged them as dead at HEAD a2de2a4d6.
private enum StructuredOutputGeneratedProtoABI {
    static let parseName = "rac_structured_output_parse_proto"
    static let preparePromptName = "rac_structured_output_prepare_prompt_proto"

    static let parse = NativeProtoABI.load(parseName, as: NativeProtoABI.ProtoRequest.self)
    static let preparePrompt = NativeProtoABI.load(preparePromptName, as: NativeProtoABI.ProtoRequest.self)
}

extension CppBridge {
    enum StructuredOutput {
        static func parse(_ request: RAStructuredOutputParseRequest) throws -> RAStructuredOutputResult {
            try NativeProtoABI.invoke(
                request,
                symbol: StructuredOutputGeneratedProtoABI.parse,
                symbolName: StructuredOutputGeneratedProtoABI.parseName,
                responseType: RAStructuredOutputResult.self
            )
        }

        /// idl/structured_output.proto (so-p2) deleted the dedicated
        /// StructuredOutputRequest message outright: StructuredOutputParseRequest
        /// (request_id, text, options, metadata) is now the sole envelope shared
        /// by parse/validate/prepare-prompt, with `text` playing the role the
        /// old `prompt` field did.
        static func preparePrompt(
            prompt: String,
            options: RAStructuredOutputOptions,
            requestID: String = UUID().uuidString
        ) throws -> RAStructuredOutputPromptResult {
            var request = RAStructuredOutputParseRequest()
            request.requestID = requestID
            request.text = prompt
            request.options = options
            return try NativeProtoABI.invoke(
                request,
                symbol: StructuredOutputGeneratedProtoABI.preparePrompt,
                symbolName: StructuredOutputGeneratedProtoABI.preparePromptName,
                responseType: RAStructuredOutputPromptResult.self
            )
        }

        /// `RAJSONSchema` was deleted outright (idl/structured_output.proto):
        /// `StructuredOutputOptions.schema` is now a single JSON Schema
        /// STRING (the `oneof constraint` arm), so `schema` here is the raw
        /// schema text rather than a typed message.
        static func makeParseRequest(
            text: String,
            schema: String,
            requestID: String = UUID().uuidString
        ) -> RAStructuredOutputParseRequest {
            var request = RAStructuredOutputParseRequest()
            request.requestID = requestID
            request.text = text
            request.options = .defaults(schema: schema)
            return request
        }
    }
}
