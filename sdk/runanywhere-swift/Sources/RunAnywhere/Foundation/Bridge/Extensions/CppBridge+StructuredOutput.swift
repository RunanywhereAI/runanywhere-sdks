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

private enum StructuredOutputGeneratedProtoABI {
    static let parseName = "rac_structured_output_parse_proto"
    static let generateName = "rac_structured_output_generate_proto"
    static let preparePromptName = "rac_structured_output_prepare_prompt_proto"

    static let parse = NativeProtoABI.load(parseName, as: NativeProtoABI.ProtoRequest.self)
    static let generate = NativeProtoABI.load(generateName, as: NativeProtoABI.ProtoRequest.self)
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

        /// Full structured-output generation: commons handles prompt preparation,
        /// LLM generation, thinking-tag stripping, JSON extraction, and schema
        /// validation. Returns the canonical `RAStructuredOutputResult`.
        static func generate(_ request: RAStructuredOutputRequest) throws -> RAStructuredOutputResult {
            try NativeProtoABI.invoke(
                request,
                symbol: StructuredOutputGeneratedProtoABI.generate,
                symbolName: StructuredOutputGeneratedProtoABI.generateName,
                responseType: RAStructuredOutputResult.self
            )
        }

        static func preparePrompt(
            prompt: String,
            options: RAStructuredOutputOptions,
            requestID: String = UUID().uuidString
        ) throws -> RAStructuredOutputPromptResult {
            try NativeProtoABI.invoke(
                makeGenerateRequest(prompt: prompt, options: options, requestID: requestID),
                symbol: StructuredOutputGeneratedProtoABI.preparePrompt,
                symbolName: StructuredOutputGeneratedProtoABI.preparePromptName,
                responseType: RAStructuredOutputPromptResult.self
            )
        }

        static func makeParseRequest(
            text: String,
            schema: RAJSONSchema,
            requestID: String = UUID().uuidString
        ) -> RAStructuredOutputParseRequest {
            var request = RAStructuredOutputParseRequest()
            request.requestID = requestID
            request.text = text
            request.options = .defaults(schema: schema)
            return request
        }

        static func makeGenerateRequest(
            prompt: String,
            options: RAStructuredOutputOptions,
            requestID: String = UUID().uuidString
        ) -> RAStructuredOutputRequest {
            var request = RAStructuredOutputRequest()
            request.requestID = requestID
            request.prompt = prompt
            request.options = options
            return request
        }
    }
}
